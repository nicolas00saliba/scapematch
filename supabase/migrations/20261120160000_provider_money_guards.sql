-- Saque limitado ao livro, webhook que pode ser reprocessado,
-- estorno com débito pendente e status de chargeback.
-- Não apaga cobrança antiga e não desliga cron.

create or replace function private.provider_house_available(p_venue_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_net integer;
  v_taken integer;
begin
  select coalesce(sum(
    case when direction = 'credit' then amount_cents else -amount_cents end
  ), 0)::integer
  into v_net
  from public.ledger_entries
  where venue_id = p_venue_id
    and account = 'house';

  select coalesce(sum(amount_cents), 0)::integer
  into v_taken
  from public.venue_withdrawals
  where venue_id = p_venue_id
    and status in ('pending', 'done');

  return greatest(coalesce(v_net, 0) - coalesce(v_taken, 0), 0);
end;
$$;

revoke all on function private.provider_house_available(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.provider_house_withdrawable(
  p_venue_id uuid,
  p_actor uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return private.provider_house_available(p_venue_id);
end;
$$;

comment on function public.provider_house_withdrawable(uuid, uuid) is
  'Líquido já lançado no livro, menos saques pendentes e concluídos. Não lê o saldo da subconta.';

revoke all on function public.provider_house_withdrawable(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.provider_house_withdrawable(uuid, uuid) to service_role;

create or replace function public.claim_provider_withdrawal(
  p_venue_id uuid,
  p_actor uuid,
  p_source text,
  p_period_key text,
  p_amount_cents integer,
  p_available_cents integer,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_period text;
  v_blocked timestamptz;
  v_available integer;
begin
  perform private.venue_payouts_require();
  if p_provider is distinct from 'woovi' then
    raise exception 'valor' using errcode = '22023';
  end if;
  if p_source is distinct from 'manual' then
    raise exception 'valor' using errcode = '22023';
  end if;
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  -- Trava a conta da casa. O segundo saque espera e vê o pendente.
  perform 1
  from public.provider_payout_accounts
  where venue_id = p_venue_id
    and provider = 'woovi'
    and status = 'active'
    and pix_key is not null
  for update;
  if not found then
    raise exception 'sem subconta' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(hashtext(p_venue_id::text));
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'valor' using errcode = '22023';
  end if;
  select withdrawals_blocked_until into v_blocked
  from public.venue_bank_accounts
  where venue_id = p_venue_id;
  if v_blocked is not null and v_blocked > pg_catalog.now() then
    raise exception 'bloqueado' using errcode = '42501';
  end if;
  -- p_available_cents é ignorado: o teto é o livro, não o saldo da subconta.
  v_available := private.provider_house_available(p_venue_id);
  if p_amount_cents > v_available then
    raise exception 'saldo' using errcode = '22023';
  end if;
  v_id := pg_catalog.gen_random_uuid();
  v_period := 'woovi:' || v_id::text;
  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, requested_by
  ) values (
    v_id, p_venue_id, p_amount_cents, 'pending', 'manual', v_period,
    v_id::text, p_actor
  );
  return pg_catalog.jsonb_build_object(
    'id', v_id,
    'amount_cents', p_amount_cents,
    'available_cents', v_available,
    'fresh', true
  );
end;
$$;

create or replace function public.release_provider_webhook(
  p_provider text,
  p_event_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if p_provider not in ('woovi', 'mercadopago')
    or p_event_id is null
    or char_length(pg_catalog.btrim(p_event_id)) < 4
  then
    raise exception 'valor' using errcode = '22023';
  end if;
  delete from public.provider_webhook_events
  where provider = p_provider
    and event_id = pg_catalog.btrim(p_event_id);
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

comment on function public.release_provider_webhook(text, text) is
  'Apaga o evento quando o processamento falha, para o reenvio entrar de novo.';

revoke all on function public.release_provider_webhook(text, text)
  from public, anon, authenticated;
grant execute on function public.release_provider_webhook(text, text) to service_role;

create table public.provider_refund_debits (
  provider text not null check (provider in ('woovi', 'mercadopago')),
  end_to_end_id text not null,
  refund_cents integer not null check (refund_cents > 0),
  charge_id uuid not null,
  correlation_id text not null,
  debit_cents integer not null check (debit_cents >= 0),
  pix_key text not null,
  phase text not null check (phase in ('refunding', 'recorded', 'done')),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (provider, end_to_end_id, refund_cents)
);

alter table public.provider_refund_debits enable row level security;

revoke all on table public.provider_refund_debits
  from public, anon, authenticated, service_role;

create or replace function public.claim_provider_refund(
  p_provider text,
  p_end_to_end_id text,
  p_refund_cents integer,
  p_charge_id uuid,
  p_correlation_id text,
  p_debit_cents integer,
  p_pix_key text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phase text;
  v_updated timestamptz;
begin
  if p_provider is distinct from 'woovi'
    or p_end_to_end_id is null
    or char_length(pg_catalog.btrim(p_end_to_end_id)) < 4
    or p_refund_cents is null
    or p_refund_cents <= 0
    or p_debit_cents is null
    or p_debit_cents < 0
    or p_charge_id is null
  then
    raise exception 'valor' using errcode = '22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    hashtext(p_provider || ':' || p_end_to_end_id),
    p_refund_cents
  );
  select phase, updated_at
  into v_phase, v_updated
  from public.provider_refund_debits
  where provider = p_provider
    and end_to_end_id = pg_catalog.btrim(p_end_to_end_id)
    and refund_cents = p_refund_cents
  for update;
  if not found then
    insert into public.provider_refund_debits (
      provider, end_to_end_id, refund_cents, charge_id, correlation_id,
      debit_cents, pix_key, phase
    ) values (
      p_provider, pg_catalog.btrim(p_end_to_end_id), p_refund_cents, p_charge_id,
      p_correlation_id, p_debit_cents, coalesce(p_pix_key, ''), 'refunding'
    );
    return 'refund';
  end if;
  if v_phase = 'done' then
    return 'done';
  end if;
  if v_phase = 'recorded' then
    return 'debit';
  end if;
  if v_updated < pg_catalog.now() - interval '2 minutes' then
    update public.provider_refund_debits
    set updated_at = pg_catalog.now()
    where provider = p_provider
      and end_to_end_id = pg_catalog.btrim(p_end_to_end_id)
      and refund_cents = p_refund_cents
      and phase = 'refunding';
    return 'refund';
  end if;
  return 'busy';
end;
$$;

create or replace function public.mark_provider_refund_recorded(
  p_provider text,
  p_end_to_end_id text,
  p_refund_cents integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.provider_refund_debits
  set phase = 'recorded',
      updated_at = pg_catalog.now()
  where provider = p_provider
    and end_to_end_id = pg_catalog.btrim(p_end_to_end_id)
    and refund_cents = p_refund_cents
    and phase = 'refunding';
  return found;
end;
$$;

create or replace function public.mark_provider_debit_done(
  p_provider text,
  p_end_to_end_id text,
  p_refund_cents integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.provider_refund_debits
  set phase = 'done',
      updated_at = pg_catalog.now()
  where provider = p_provider
    and end_to_end_id = pg_catalog.btrim(p_end_to_end_id)
    and refund_cents = p_refund_cents
    and phase in ('recorded', 'refunding');
  return found;
end;
$$;

create or replace function public.release_provider_refund(
  p_provider text,
  p_end_to_end_id text,
  p_refund_cents integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.provider_refund_debits
  where provider = p_provider
    and end_to_end_id = pg_catalog.btrim(p_end_to_end_id)
    and refund_cents = p_refund_cents
    and phase = 'refunding';
  return found;
end;
$$;

revoke all on function public.claim_provider_refund(text, text, integer, uuid, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.mark_provider_refund_recorded(text, text, integer)
  from public, anon, authenticated;
revoke all on function public.mark_provider_debit_done(text, text, integer)
  from public, anon, authenticated;
revoke all on function public.release_provider_refund(text, text, integer)
  from public, anon, authenticated;

grant execute on function public.claim_provider_refund(text, text, integer, uuid, text, integer, text)
  to service_role;
grant execute on function public.mark_provider_refund_recorded(text, text, integer)
  to service_role;
grant execute on function public.mark_provider_debit_done(text, text, integer)
  to service_role;
grant execute on function public.release_provider_refund(text, text, integer)
  to service_role;

alter table public.payment_charges
  drop constraint if exists payment_charges_status_check;

alter table public.payment_charges
  add constraint payment_charges_status_check
  check (
    status in (
      'creating',
      'pending',
      'authorized',
      'paid',
      'refunded',
      'cancelled',
      'failed',
      'charged_back'
    )
  );

create or replace function private.payment_status_allowed(p_from text, p_to text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select p_from = p_to
    or (
      p_from = 'creating'
      and p_to in (
        'pending', 'authorized', 'paid', 'refunded', 'cancelled', 'failed'
      )
    )
    or (
      p_from = 'pending'
      and p_to in (
        'authorized', 'paid', 'refunded', 'cancelled', 'failed', 'charged_back'
      )
    )
    or (
      p_from = 'authorized'
      and p_to in ('paid', 'refunded', 'cancelled', 'failed', 'charged_back')
    )
    or (p_from = 'paid' and p_to in ('refunded', 'charged_back'));
$$;

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
  v_updated integer;
begin
  v_payment := case p_charge.status
    when 'paid' then 'paid'
    when 'authorized' then 'reserved'
    when 'refunded' then 'released'
    when 'charged_back' then 'released'
    when 'cancelled' then 'released'
    when 'failed' then 'released'
    else 'pending'
  end;
  v_refund := case
    when p_charge.status = 'refunded' then 'refunded'
    else 'none'
  end;

  select refund_reason into v_reason
  from public.group_members
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id
  for update;

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

create or replace function private.apply_payment_transition(
  p_charge_id uuid,
  p_next_status text,
  p_credit boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_previous text;
  v_applied boolean := false;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    raise exception 'charge_not_found' using errcode = 'P0002';
  end if;

  v_previous := v_charge.status;

  if v_previous = 'refunded' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
    perform private.sync_charge_member(v_charge);
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'status', v_charge.status,
      'paid_at', v_charge.paid_at,
      'refunded_at', v_charge.refunded_at
    );
  end if;

  if v_previous = 'charged_back' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
    perform private.sync_charge_member(v_charge);
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'status', v_charge.status,
      'paid_at', v_charge.paid_at,
      'refunded_at', v_charge.refunded_at
    );
  end if;

  if not private.payment_status_allowed(v_previous, p_next_status) then
    perform private.sync_charge_member(v_charge);
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'status', v_charge.status,
      'paid_at', v_charge.paid_at,
      'refunded_at', v_charge.refunded_at
    );
  end if;

  if v_previous is distinct from p_next_status
    or (p_next_status = 'paid' and v_charge.paid_at is null)
    or (p_next_status = 'refunded' and v_charge.refunded_at is null)
  then
    update public.payment_charges
    set
      status = p_next_status,
      paid_at = case
        when p_next_status = 'paid' then coalesce(paid_at, pg_catalog.now())
        else paid_at
      end,
      refunded_at = case
        when p_next_status = 'refunded'
          then coalesce(refunded_at, pg_catalog.now())
        else refunded_at
      end
    where id = v_charge.id
    returning * into v_charge;
    v_applied := v_previous is distinct from v_charge.status;
  end if;

  if v_charge.status = 'paid' and p_credit then
    perform private.ledger_credit_charge(v_charge.id);
    perform private.post_referral_rewards(v_charge.id);
  end if;
  if v_charge.status = 'refunded' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
  end if;
  if v_charge.status = 'charged_back' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
  end if;
  if v_charge.status in ('cancelled', 'failed') then
    perform private.release_unpaid_components(v_charge.id);
  end if;

  perform private.sync_charge_member(v_charge);
  return pg_catalog.jsonb_build_object(
    'applied', v_applied,
    'status', v_charge.status,
    'paid_at', v_charge.paid_at,
    'refunded_at', v_charge.refunded_at
  );
end;
$$;
