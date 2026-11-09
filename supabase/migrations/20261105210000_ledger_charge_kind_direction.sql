-- Transição da cobrança e livro-razão na mesma transação, mais a reserva do Pix.
-- Não aplicada no projeto remoto.
--
-- CREATE UNIQUE INDEX sem CONCURRENTLY (a migração roda dentro de uma
-- transação, e CONCURRENTLY não pode) toma um lock que impede escritas em
-- ledger_entries até o índice ficar pronto. No volume atual isso é aceitável.
--
-- Se já existir duplicata em (payment_charge_id, kind, direction), a migração
-- falha de propósito. Não apaga linha nenhuma.

do $guard$
declare
  v_dup bigint;
begin
  select count(*) into v_dup
  from (
    select 1
    from public.ledger_entries
    where payment_charge_id is not null
    group by payment_charge_id, kind, direction
    having count(*) > 1
  ) as dups;
  if v_dup > 0 then
    raise exception
      'ledger_entries tem duplicatas em (payment_charge_id, kind, direction); resolva antes de criar o índice único'
      using errcode = '23505';
  end if;
end
$guard$;

create unique index if not exists ledger_entries_charge_kind_direction_uidx
  on public.ledger_entries (payment_charge_id, kind, direction);

-- O índice parcial de crédito atrapalha o ON CONFLICT no índice completo.
-- O único novo já cobre crédito e débito.
drop index if exists public.ledger_one_credit_per_charge_kind;

alter table public.payment_charges
  add column if not exists reserved_at timestamptz;

alter table public.payment_charges
  add column if not exists attempt_id uuid;

-- Pix ou cartão que nasceu no Asaas e a tentativa perdeu o lease.
-- Sem policy e sem grant: a API não lê. A service role só entra pela função.
create table private.orphan_payments (
  id uuid primary key default gen_random_uuid(),
  provider_ref text not null,
  charge_id uuid,
  attempt_id uuid,
  billing_type text,
  reason text not null,
  created_at timestamptz not null default pg_catalog.now()
);

alter table private.orphan_payments enable row level security;

revoke all on table private.orphan_payments
  from public, anon, authenticated, service_role;

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
      'failed'
    )
  );

-- Mesma matriz de supabase/functions/_shared/charge_patch.ts.
-- refunded, cancelled e failed não têm saída: são terminais.
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
      and p_to in ('authorized', 'paid', 'refunded', 'cancelled', 'failed')
    )
    or (
      p_from = 'authorized'
      and p_to in ('paid', 'refunded', 'cancelled', 'failed')
    )
    or (p_from = 'paid' and p_to = 'refunded');
$$;

create or replace function private.ledger_credit_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_fee integer;
  v_net integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  v_fee := (
    (v_charge.amount_cents::bigint * v_charge.commission_bps + 5000) / 10000
  )::integer;
  v_net := v_charge.amount_cents - v_fee;
  if v_net > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'house_net', v_net, v_charge.id
    )
    on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_fee > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'platform', 'credit', 'commission', v_fee, v_charge.id
    )
    on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
end;
$$;

create or replace function private.ledger_reverse_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    credit.venue_id,
    credit.group_id,
    credit.user_id,
    credit.account,
    'debit',
    case credit.kind
      when 'commission' then 'commission_refund'
      when 'venue_credit_applied' then 'venue_credit_refund'
      else 'house_refund'
    end,
    credit.amount_cents,
    credit.payment_charge_id
  from public.ledger_entries as credit
  where credit.payment_charge_id = p_charge_id
    and credit.direction = 'credit'
  on conflict (payment_charge_id, kind, direction) do nothing;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    debit.venue_id,
    debit.group_id,
    debit.user_id,
    debit.account,
    'credit',
    'venue_credit_clawback_refund',
    debit.amount_cents,
    debit.payment_charge_id
  from public.ledger_entries as debit
  where debit.payment_charge_id = p_charge_id
    and debit.direction = 'debit'
    and debit.kind = 'venue_credit_clawback'
  on conflict (payment_charge_id, kind, direction) do nothing;

  perform private.restore_applied_venue_credits(p_charge_id);
end;
$$;

-- O membro acompanha o status que ficou, não o que o evento pediu.
-- refunded terminal continua released/refunded.
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

-- Trava a cobrança, aplica só a transição permitida e grava o livro
-- na mesma transação. Replay de pago não reescreve paid_at (coalesce).
-- refunded não volta para paid e não limpa refunded_at.
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
  end if;
  if v_charge.status = 'refunded' then
    perform private.ledger_reverse_charge(v_charge.id);
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

-- Reserva a linha do Pix antes do Asaas. Conflito não sobrescreve provider_ref.
create or replace function private.reserve_pix_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_inserted boolean := false;
  v_charge public.payment_charges%rowtype;
begin
  insert into public.payment_charges (
    group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, provider_ref, idempotency_key, wallet_id, commission_bps,
    reserved_at, attempt_id
  ) values (
    p_group_id, p_user_id, p_venue_id, p_amount_cents, 'PIX', 'creating',
    'asaas', null, p_idempotency_key, p_wallet_id, p_commission_bps,
    pg_catalog.now(), gen_random_uuid()
  )
  on conflict (group_id, user_id) do nothing
  returning id into v_id;
  v_inserted := v_id is not null;

  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;

  return pg_catalog.jsonb_build_object(
    'id', v_charge.id,
    'status', v_charge.status,
    'provider_ref', v_charge.provider_ref,
    'billing_type', v_charge.billing_type,
    'amount_cents', v_charge.amount_cents,
    'inserted', v_inserted,
    'reserved_at', v_charge.reserved_at,
    'attempt_id', v_charge.attempt_id,
    'idempotency_key', v_charge.idempotency_key,
    'lease_expired', (not v_inserted)
      and v_charge.provider_ref is null
      and v_charge.status = 'creating'
      and (
        v_charge.reserved_at is null
        or v_charge.reserved_at < pg_catalog.now() - interval '2 minutes'
      )
  );
end;
$$;

-- Grava o id só se o attempt_id ainda é o desta tentativa.
-- Attempt diferente não escreve. O retorno é o id que ficou gravado.
create or replace function private.attach_pix_provider(
  p_charge_id uuid,
  p_provider_ref text,
  p_attempt_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref text;
begin
  if p_provider_ref is null or length(pg_catalog.btrim(p_provider_ref)) = 0 then
    raise exception 'provider_ref ausente' using errcode = '22023';
  end if;

  update public.payment_charges
  set provider_ref = p_provider_ref
  where id = p_charge_id
    and provider_ref is null
    and attempt_id is not distinct from p_attempt_id
  returning provider_ref into v_ref;

  if v_ref is not null then
    return v_ref;
  end if;

  select provider_ref into v_ref
  from public.payment_charges
  where id = p_charge_id;
  return v_ref;
end;
$$;

-- Assume uma reserva vencida e devolve o attempt_id novo. Reserva fresca não muda.
create or replace function private.claim_expired_pix_reservation(p_charge_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt uuid;
begin
  update public.payment_charges
  set
    reserved_at = pg_catalog.now(),
    attempt_id = gen_random_uuid()
  where id = p_charge_id
    and status = 'creating'
    and provider_ref is null
    and (
      reserved_at is null
      or reserved_at < pg_catalog.now() - interval '2 minutes'
    )
  returning attempt_id into v_attempt;
  return v_attempt;
end;
$$;

-- Reserva vencida sem id no provedor, só se o attempt ainda for o lido.
create or replace function private.release_expired_pix_reservation(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  delete from public.payment_charges
  where id = p_charge_id
    and status = 'creating'
    and provider_ref is null
    and attempt_id is not distinct from p_attempt_id
    and (
      reserved_at is null
      or reserved_at < pg_catalog.now() - interval '2 minutes'
    )
  returning id into v_id;
  return v_id is not null;
end;
$$;

-- 4xx conhecido: a cobrança não nasceu no Asaas. Só apaga a própria tentativa.
create or replace function private.release_pix_reservation(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  delete from public.payment_charges
  where id = p_charge_id
    and status = 'creating'
    and provider_ref is null
    and attempt_id is not distinct from p_attempt_id
  returning id into v_id;
  return v_id is not null;
end;
$$;

create or replace function private.reserve_card_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_inserted boolean := false;
  v_charge public.payment_charges%rowtype;
begin
  insert into public.payment_charges (
    group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, provider_ref, idempotency_key, wallet_id, commission_bps,
    reserved_at, attempt_id
  ) values (
    p_group_id, p_user_id, p_venue_id, p_amount_cents, 'CREDIT_CARD', 'creating',
    'asaas', null, p_idempotency_key, p_wallet_id, p_commission_bps,
    pg_catalog.now(), gen_random_uuid()
  )
  on conflict (group_id, user_id) do nothing
  returning id into v_id;
  v_inserted := v_id is not null;

  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;

  return pg_catalog.jsonb_build_object(
    'id', v_charge.id,
    'status', v_charge.status,
    'provider_ref', v_charge.provider_ref,
    'billing_type', v_charge.billing_type,
    'amount_cents', v_charge.amount_cents,
    'inserted', v_inserted,
    'reserved_at', v_charge.reserved_at,
    'attempt_id', v_charge.attempt_id,
    'idempotency_key', v_charge.idempotency_key,
    'lease_expired', (not v_inserted)
      and v_charge.provider_ref is null
      and v_charge.status = 'creating'
      and (
        v_charge.reserved_at is null
        or v_charge.reserved_at < pg_catalog.now() - interval '2 minutes'
      )
  );
end;
$$;

create or replace function private.record_orphan_payment(
  p_provider_ref text,
  p_charge_id uuid,
  p_attempt_id uuid,
  p_billing_type text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_provider_ref is null or length(pg_catalog.btrim(p_provider_ref)) = 0 then
    raise exception 'provider_ref ausente' using errcode = '22023';
  end if;
  insert into private.orphan_payments (
    provider_ref, charge_id, attempt_id, billing_type, reason
  ) values (
    p_provider_ref, p_charge_id, p_attempt_id, p_billing_type, p_reason
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Só limpa o id depois que o DELETE do Pix foi confirmado.
create or replace function private.clear_pix_provider_ref(
  p_charge_id uuid,
  p_provider_ref text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt uuid;
begin
  update public.payment_charges
  set
    provider_ref = null,
    billing_type = 'CREDIT_CARD',
    status = 'creating',
    qr_code = null,
    qr_code_base64 = null,
    reserved_at = pg_catalog.now(),
    attempt_id = gen_random_uuid()
  where id = p_charge_id
    and provider_ref = p_provider_ref
    and billing_type = 'PIX'
    and status in ('pending', 'creating')
  returning attempt_id into v_attempt;
  return v_attempt;
end;
$$;

revoke all on function private.payment_status_allowed(text, text)
  from public, anon, authenticated;
revoke all on function private.ledger_credit_charge(uuid)
  from public, anon, authenticated;
revoke all on function private.ledger_reverse_charge(uuid)
  from public, anon, authenticated;
revoke all on function private.apply_payment_transition(uuid, text, boolean)
  from public, anon, authenticated;
revoke all on function private.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer)
  from public, anon, authenticated;
revoke all on function private.attach_pix_provider(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.sync_charge_member(public.payment_charges)
  from public, anon, authenticated;
revoke all on function private.claim_expired_pix_reservation(uuid)
  from public, anon, authenticated;
revoke all on function private.release_pix_reservation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.release_expired_pix_reservation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.clear_pix_provider_ref(uuid, text)
  from public, anon, authenticated;
revoke all on function private.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer)
  from public, anon, authenticated;
revoke all on function private.record_orphan_payment(text, uuid, uuid, text, text)
  from public, anon, authenticated;

grant execute on function private.apply_payment_transition(uuid, text, boolean)
  to service_role;
grant execute on function private.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer)
  to service_role;
grant execute on function private.attach_pix_provider(uuid, text, uuid)
  to service_role;
grant execute on function private.claim_expired_pix_reservation(uuid)
  to service_role;
grant execute on function private.release_pix_reservation(uuid, uuid)
  to service_role;
grant execute on function private.release_expired_pix_reservation(uuid, uuid)
  to service_role;
grant execute on function private.clear_pix_provider_ref(uuid, text)
  to service_role;
grant execute on function private.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer)
  to service_role;
grant execute on function private.record_orphan_payment(text, uuid, uuid, text, text)
  to service_role;

-- O schema private não entra na API. Estes wrappers só existem para o
-- PostgREST e só a service role executa.
create or replace function public.apply_payment_transition(
  p_charge_id uuid,
  p_next_status text,
  p_credit boolean
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.apply_payment_transition(p_charge_id, p_next_status, p_credit);
$$;

create or replace function public.reserve_pix_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.reserve_pix_charge(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps
  );
$$;

create or replace function public.attach_pix_provider(
  p_charge_id uuid,
  p_provider_ref text,
  p_attempt_id uuid
)
returns text
language sql
security invoker
set search_path = ''
as $$
  select private.attach_pix_provider(p_charge_id, p_provider_ref, p_attempt_id);
$$;

revoke all on function public.apply_payment_transition(uuid, text, boolean)
  from public, anon, authenticated;
revoke all on function public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer)
  from public, anon, authenticated;
create or replace function public.claim_expired_pix_reservation(p_charge_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.claim_expired_pix_reservation(p_charge_id);
$$;

create or replace function public.release_expired_pix_reservation(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.release_expired_pix_reservation(p_charge_id, p_attempt_id);
$$;

create or replace function public.release_pix_reservation(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.release_pix_reservation(p_charge_id, p_attempt_id);
$$;

create or replace function public.clear_pix_provider_ref(
  p_charge_id uuid,
  p_provider_ref text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.clear_pix_provider_ref(p_charge_id, p_provider_ref);
$$;

create or replace function public.reserve_card_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.reserve_card_charge(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps
  );
$$;

create or replace function public.record_orphan_payment(
  p_provider_ref text,
  p_charge_id uuid,
  p_attempt_id uuid,
  p_billing_type text,
  p_reason text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.record_orphan_payment(
    p_provider_ref, p_charge_id, p_attempt_id, p_billing_type, p_reason
  );
$$;

revoke all on function public.attach_pix_provider(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.claim_expired_pix_reservation(uuid)
  from public, anon, authenticated;
revoke all on function public.release_pix_reservation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.release_expired_pix_reservation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.clear_pix_provider_ref(uuid, text)
  from public, anon, authenticated;
revoke all on function public.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer)
  from public, anon, authenticated;
revoke all on function public.record_orphan_payment(text, uuid, uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.apply_payment_transition(uuid, text, boolean)
  to service_role;
grant execute on function public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer)
  to service_role;
grant execute on function public.attach_pix_provider(uuid, text, uuid)
  to service_role;
grant execute on function public.claim_expired_pix_reservation(uuid)
  to service_role;
grant execute on function public.release_pix_reservation(uuid, uuid)
  to service_role;
grant execute on function public.release_expired_pix_reservation(uuid, uuid)
  to service_role;
grant execute on function public.clear_pix_provider_ref(uuid, text)
  to service_role;
grant execute on function public.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer)
  to service_role;
grant execute on function public.record_orphan_payment(text, uuid, uuid, text, text)
  to service_role;
