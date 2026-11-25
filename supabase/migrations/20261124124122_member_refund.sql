-- Estorno individual de verdade. Sair no prazo, ou ser removido pelo
-- organizador, não marca refunded na hora. A fila pede o estorno na
-- PagBank. refunded só entra quando a cobrança vira refunded ou cancelled.
--
-- Custódia HELD: a cobrança ganha refund_requested_at e ninguém chama
-- custody/release. O estorno devolve o saldo retido, inclusive juros.
-- Custódia já liberada: o mesmo POST /charges/{id}/cancel, pelo
-- charged_amount_cents, desfaz a parte da casa e a da EscapeMatch na
-- PagBank. Não há transferência extra da EscapeMatch para cobrir a casa.
-- Se a PagBank recusar, a fila continua e o status não vira refunded.

alter table public.group_members
  drop constraint if exists group_members_refund_status_check;

alter table public.group_members
  add constraint group_members_refund_status_check
  check (
    refund_status in (
      'none', 'pending', 'refund_pending', 'refunded', 'denied'
    )
  );

alter table public.payment_charges
  add column if not exists refund_requested_at timestamptz;

comment on column public.payment_charges.refund_requested_at is
  'Estorno individual pedido. Não capturar e não soltar a custódia.';

create table public.member_refund_queue (
  id uuid primary key default gen_random_uuid(),
  charge_id uuid not null unique references public.payment_charges (id),
  member_id uuid not null references public.group_members (id),
  group_id uuid not null references public.groups (id),
  user_id uuid not null references auth.users (id),
  action text not null check (action in ('refund', 'void')),
  status text not null default 'queued' check (status in ('queued', 'done')),
  attempts integer not null default 0 check (attempts >= 0),
  created_at timestamptz not null default now(),
  done_at timestamptz
);

create index member_refund_queue_open
  on public.member_refund_queue (created_at)
  where status = 'queued';

alter table public.member_refund_queue enable row level security;

revoke all on table public.member_refund_queue
  from public, anon, authenticated;
grant select, update on table public.member_refund_queue to service_role;

-- Devolve true quando há cobrança viva na PagBank para estornar ou cancelar.
create or replace function private.enqueue_member_refund(
  p_group_id uuid,
  p_user_id uuid,
  p_member_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_action text;
begin
  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;

  if v_charge.id is null then
    return false;
  end if;
  if v_charge.provider_ref is null
    or length(pg_catalog.btrim(v_charge.provider_ref)) = 0
  then
    return false;
  end if;
  if v_charge.status in ('refunded', 'cancelled', 'failed') then
    return false;
  end if;
  if v_charge.status = 'paid' then
    v_action := 'refund';
  elsif v_charge.status in ('authorized', 'pending', 'creating') then
    v_action := 'void';
  else
    return false;
  end if;

  update public.payment_charges
  set refund_requested_at = coalesce(refund_requested_at, pg_catalog.now())
  where id = v_charge.id;

  insert into public.member_refund_queue (
    charge_id, member_id, group_id, user_id, action
  ) values (
    v_charge.id, p_member_id, p_group_id, p_user_id, v_action
  )
  on conflict (charge_id) do nothing;

  return true;
end;
$$;

revoke all on function private.enqueue_member_refund(uuid, uuid, uuid)
  from public, anon, authenticated;

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
          when payment_status = 'paid' and v_in_time and v_queued then 'refund_pending'
          when payment_status = 'paid' and v_in_time then 'refunded'
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
          when v_queued then 'refund_pending'
          when payment_status = 'paid' then 'refunded'
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

-- Membro que já saiu não perde refund_pending quando a cobrança ainda
-- está paga. refunded chega com a confirmação da PagBank.
create or replace function private.sync_charge_member(
  p_charge public.payment_charges
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment text;
  v_refund text;
  v_reason text;
  v_attendance text;
  v_current_refund text;
  v_updated integer;
begin
  select attendance, refund_status, refund_reason
    into v_attendance, v_current_refund, v_reason
  from public.group_members
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id
  for update;

  if v_attendance = 'cancelled'
    and v_current_refund in ('refund_pending', 'pending', 'denied', 'refunded')
  then
    v_payment := case p_charge.status
      when 'paid' then 'paid'
      when 'authorized' then 'reserved'
      when 'refunded' then 'released'
      when 'cancelled' then 'released'
      when 'failed' then 'released'
      else 'pending'
    end;
    v_refund := case
      when p_charge.status = 'refunded' then 'refunded'
      when p_charge.status = 'cancelled'
        and v_current_refund in ('refund_pending', 'pending') then 'refunded'
      else v_current_refund
    end;
    if v_reason is null or v_reason = 'none' then
      v_reason := case
        when v_refund = 'refunded' then 'group_did_not_close'
        else 'hold_released'
      end;
    end if;
  else
    v_payment := case p_charge.status
      when 'paid' then 'paid'
      when 'authorized' then 'reserved'
      when 'refunded' then 'released'
      when 'cancelled' then 'released'
      when 'failed' then 'released'
      else 'pending'
    end;
    v_refund := case
      when p_charge.status = 'refunded' then 'refunded'
      else 'none'
    end;
    if p_charge.status = 'refunded' then
      if v_reason is null or v_reason = 'none' then
        v_reason := 'group_did_not_close';
      end if;
    elsif p_charge.status = 'cancelled' or p_charge.status = 'failed' then
      if v_reason is null or v_reason = 'none' then
        v_reason := 'hold_released';
      end if;
    else
      v_reason := 'none';
    end if;
  end if;

  update public.group_members
  set
    payment_status = v_payment,
    refund_status = v_refund,
    refund_reason = v_reason
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'member_missing' using errcode = 'P0002';
  end if;
end;
$$;
