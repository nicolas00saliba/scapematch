-- Reembolso em dinheiro = valor pago naquela cobrança menos a taxa
-- PagBank. A taxa fica com quem pagou. A parte fixa da casa
-- (house_fixed_cents) não entra nessa conta.
--
-- A taxa real, quando a PagBank já informou, é provider_fee_cents.
-- Sem ela, vale a estimativa da mesma cobrança (Pix fixo ou cartão
-- fixo + percentual, com teto no dinheiro pago).
--
-- Cancelar uma autorização ainda não capturada devolve a reserva
-- inteira: a taxa ainda não foi cobrada, e um estorno parcial
-- deixaria a autorização presa.
--
-- Pontos usados não mudam aqui.

alter table public.member_refund_queue
  add column if not exists amount_cents integer;

alter table public.member_refund_queue
  drop constraint if exists member_refund_queue_amount_nonnegative;

alter table public.member_refund_queue
  add constraint member_refund_queue_amount_nonnegative
  check (amount_cents is null or amount_cents >= 0);

comment on column public.member_refund_queue.amount_cents is
  'Centavos a devolver nesta cobrança. No estorno capturado, o pago menos a taxa. Na autorização aberta, o valor retido inteiro.';

create or replace function private.member_refund_cash_cents(
  p_charge public.payment_charges,
  p_action text
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_paid integer;
  v_fee integer;
begin
  v_paid := case
    when coalesce(p_charge.charged_amount_cents, 0) > 0
      then p_charge.charged_amount_cents
    else greatest(coalesce(p_charge.amount_cents, 0), 0)
  end;

  if p_action is distinct from 'refund' then
    return v_paid;
  end if;

  v_fee := p_charge.provider_fee_cents;
  if v_fee is null then
    v_fee := private.estimated_receipt_fee_cents(
      p_charge.billing_type,
      v_paid
    );
  end if;
  v_fee := least(greatest(coalesce(v_fee, 0), 0), v_paid);
  return v_paid - v_fee;
end;
$$;

revoke all on function private.member_refund_cash_cents(
  public.payment_charges, text
) from public, anon, authenticated;

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
  v_amount integer;
begin
  select *
    into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
    and provider_ref is not null
    and status in ('paid', 'authorized', 'pending', 'creating')
  order by created_at desc
  limit 1
  for update;

  if not found then
    return false;
  end if;
  if length(pg_catalog.btrim(v_charge.provider_ref)) = 0 then
    return false;
  end if;

  v_action := case
    when v_charge.status = 'paid' then 'refund'
    else 'void'
  end;
  v_amount := private.member_refund_cash_cents(v_charge, v_action);

  update public.payment_charges
  set refund_requested_at = coalesce(refund_requested_at, pg_catalog.now())
  where id = v_charge.id;

  insert into public.member_refund_queue (
    charge_id, member_id, group_id, user_id, action, amount_cents
  )
  values (
    v_charge.id, p_member_id, p_group_id, p_user_id, v_action, v_amount
  )
  on conflict (charge_id) do nothing;

  return true;
end;
$$;

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
      queue.amount_cents,
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
    'amount_cents', updated.amount_cents,
    'status', updated.status,
    'attempts', updated.attempts,
    'lease_until', updated.lease_until
  )), '[]'::jsonb)
  into v_rows
  from updated;

  return v_rows;
end;
$$;

create or replace function public.preview_member_refund(p_group_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_charge public.payment_charges%rowtype;
begin
  if v_user is null then
    return null;
  end if;

  select * into v_group
  from public.groups
  where id = p_group_id;

  if not found or v_group.cancelled_at is not null then
    return null;
  end if;

  if v_group.starts_at - pg_catalog.now()
    < make_interval(mins => v_group.cancel_window_minutes)
  then
    return null;
  end if;

  if not exists (
    select 1
    from public.group_members
    where group_id = p_group_id
      and user_id = v_user
      and attendance <> 'cancelled'
      and payment_status = 'paid'
  ) then
    return null;
  end if;

  select *
    into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = v_user
    and provider_ref is not null
    and status = 'paid'
  order by created_at desc
  limit 1;

  if not found then
    return null;
  end if;

  return private.member_refund_cash_cents(v_charge, 'refund');
end;
$$;

revoke all on function public.preview_member_refund(uuid) from public, anon;
grant execute on function public.preview_member_refund(uuid)
  to authenticated, service_role;

create or replace function public.remove_room_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_venue uuid;
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_queued boolean;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;

  select room.venue_id
    into v_venue
  from public.rooms room
  where room.id = v_session.room_id;

  if v_venue is null then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;

  if not private.owns_venue(v_venue) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;

  if v_session.cancelled_at is not null then
    return;
  end if;

  for v_group in
    select *
    from public.groups
    where session_id = v_session.id
      and cancelled_at is null
    for update
  loop
    update public.groups
      set cancelled_at = pg_catalog.now(),
          cancel_reason = 'Horário removido pela casa'
      where id = v_group.id;

    for v_member in
      select *
      from public.group_members
      where group_id = v_group.id
        and attendance <> 'cancelled'
      for update
    loop
      v_queued := private.enqueue_member_refund(
        v_group.id, v_member.user_id, v_member.id
      );
      update public.group_members
        set attendance = 'cancelled',
            refund_status = case
              when payment_status = 'paid' or v_queued then 'refund_pending'
              else 'none'
            end,
            refund_reason = case
              when payment_status = 'paid' or v_queued then 'organizer_cancelled_event'
              else 'hold_released'
            end,
            payment_status = case
              when payment_status = 'paid' then payment_status
              when v_queued then payment_status
              else 'released'
            end
        where id = v_member.id;

      perform private.post_app_notice(
        v_member.user_id,
        'group_cancelled',
        'Sessão cancelada',
        'A casa cancelou a sessão. Se você pagou, o estorno sai do valor pago, sem a taxa de pagamento.',
        v_group.id,
        'session-removed-' || v_session.id::text || '-' || v_member.user_id::text
      );
    end loop;
  end loop;

  update public.room_sessions
    set cancelled_at = pg_catalog.now()
  where id = v_session.id
    and cancelled_at is null;
end;
$$;
