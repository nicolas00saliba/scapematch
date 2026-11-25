-- Lease do estorno individual. Dois workers não pegam a mesma cobrança.
-- processing segura a linha por 90 segundos. O prazo vencido volta para
-- queued. refunded não nasce aqui: saída paga sem fila fica refund_pending.
--
-- POST /charges/{id}/cancel (Cancelar pagamento, API de Pedidos) não
-- documenta header de idempotência. x-idempotency-key está no estorno de
-- pagamento recorrente (PAYM_), outro recurso. O catálogo de Pedidos cita
-- 40005 idempotency_key_in_use sem dizer o header deste cancelamento.
-- Não enviamos header não documentado. A trava é este lease.

alter table public.member_refund_queue
  drop constraint if exists member_refund_queue_status_check;

alter table public.member_refund_queue
  add constraint member_refund_queue_status_check
  check (status in ('queued', 'processing', 'done'));

alter table public.member_refund_queue
  add column if not exists lease_until timestamptz;

comment on column public.member_refund_queue.lease_until is
  'Fim do lease. processing vencido volta para queued no próximo claim.';

create or replace function private.claim_member_refunds(
  p_limit integer,
  p_group_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_rows jsonb;
begin
  update public.member_refund_queue queue
  set status = 'queued',
      lease_until = null
  where queue.id in (
    select id
    from public.member_refund_queue
    where status = 'processing'
      and lease_until <= pg_catalog.now()
    for update skip locked
  );

  with picked as (
    select id
    from public.member_refund_queue
    where status = 'queued'
      and attempts < 8
      and (p_group_id is null or group_id = p_group_id)
      and (p_user_id is null or user_id = p_user_id)
    order by created_at, id
    limit v_limit
    for update skip locked
  ),
  updated as (
    update public.member_refund_queue queue
    set status = 'processing',
        lease_until = pg_catalog.now() + interval '90 seconds',
        attempts = queue.attempts + 1
    from picked
    where queue.id = picked.id
    returning
      queue.id,
      queue.charge_id,
      queue.group_id,
      queue.user_id,
      queue.action,
      queue.status,
      queue.attempts,
      queue.lease_until
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', updated.id,
    'charge_id', updated.charge_id,
    'group_id', updated.group_id,
    'user_id', updated.user_id,
    'action', updated.action,
    'status', updated.status,
    'attempts', updated.attempts,
    'lease_until', updated.lease_until
  )), '[]'::jsonb)
  into v_rows
  from updated;

  return v_rows;
end;
$$;

revoke all on function private.claim_member_refunds(integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function private.claim_member_refunds(integer, uuid, uuid)
  to service_role;

create or replace function public.claim_member_refunds(
  p_limit integer,
  p_group_id uuid,
  p_user_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.claim_member_refunds(p_limit, p_group_id, p_user_id);
$$;

revoke all on function public.claim_member_refunds(integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.claim_member_refunds(integer, uuid, uuid)
  to service_role;

create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_in_time boolean;
  v_queued boolean := false;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where group_id = p_group_id and user_id = v_user and attendance <> 'cancelled';
  if not found then
    raise exception 'not member' using errcode = 'P0002';
  end if;
  if v_member.is_creator then
    raise exception 'creator must delete' using errcode = 'P0001';
  end if;

  v_in_time := v_group.starts_at - pg_catalog.now() >= make_interval(mins => v_group.cancel_window_minutes);
  if v_in_time or v_member.payment_status is distinct from 'paid' then
    v_queued := private.enqueue_member_refund(p_group_id, v_user, v_member.id);
  end if;

  update public.group_members
    set attendance = 'cancelled',
        refund_status = case
          when payment_status = 'paid' and v_in_time then 'refund_pending'
          when v_queued and v_in_time then 'refund_pending'
          when payment_status = 'paid' then 'denied'
          else 'none'
        end,
        refund_reason = case
          when payment_status = 'paid' and v_in_time then 'cancelled_in_time'
          when v_queued and v_in_time then 'cancelled_in_time'
          when payment_status = 'paid' then 'cancelled_too_late'
          else 'hold_released'
        end,
        payment_status = case
          when payment_status = 'paid' then payment_status
          when v_queued and v_in_time then payment_status
          else 'released'
        end
    where id = v_member.id;

  update public.groups set closed_at = null where id = p_group_id and closed_at is not null
    and private.group_filled_spots(p_group_id) < total_spots;
  perform private.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.remove_member(p_group_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_room public.rooms%rowtype;
  v_queued boolean := false;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at <= pg_catalog.now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= pg_catalog.now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where id = p_member_id and group_id = p_group_id and attendance <> 'cancelled';
  if not found then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  if v_member.is_creator or v_member.user_id = v_user then
    raise exception 'cannot remove creator' using errcode = 'P0001';
  end if;

  v_queued := private.enqueue_member_refund(p_group_id, v_member.user_id, v_member.id);

  update public.group_members
    set attendance = 'cancelled',
        refund_status = case
          when payment_status = 'paid' or v_queued then 'refund_pending'
          else 'none'
        end,
        refund_reason = case
          when payment_status = 'paid' or v_queued then 'organizer_removed_member'
          else 'hold_released'
        end,
        payment_status = case
          when payment_status = 'paid' then payment_status
          when v_queued then payment_status
          else 'released'
        end
    where id = v_member.id;

  update public.groups set closed_at = null
    where id = p_group_id
      and private.group_filled_spots(p_group_id) < total_spots;
  perform private.offer_waitlist(p_group_id);
end;
$$;
