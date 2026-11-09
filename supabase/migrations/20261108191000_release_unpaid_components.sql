-- Cobrança que não foi paga devolve crédito, clawback e a sala.
-- release_pix apaga a linha; as aplicações precisam sair antes da foreign key.

create or replace function private.release_unpaid_components(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_status is null or v_status in ('paid', 'refunded', 'authorized') then
    return;
  end if;

  perform private.lock_venue_rewards(ch.venue_id)
  from public.payment_charges ch
  where ch.id = p_charge_id;

  update public.venue_credit_clawbacks c
  set voided_at = pg_catalog.now()
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.entry_id = c.entry_id
    and c.voided_at is null
    and c.neutralized_at is null
    and (c.applied_charge_id is null or c.applied_charge_id = p_charge_id);

  update public.venue_credit_clawbacks
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null
    and neutralized_at is null;

  update public.venue_referral_entries e
  set settlement = 'released',
      applied_cents = 0
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and a.entry_id = e.id
    and e.settlement = 'applied'
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  delete from public.venue_credit_applications
  where payment_charge_id = p_charge_id;

  update public.payment_charges
  set venue_credit_applied_cents = 0,
      venue_credit_clawback_cents = 0
  where id = p_charge_id;
end;
$$;

revoke all on function private.release_unpaid_components(uuid)
  from public, anon, authenticated;

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
  select id into v_id
  from public.payment_charges
  where id = p_charge_id
    and status = 'creating'
    and provider_ref is null
    and attempt_id is not distinct from p_attempt_id
  for update;
  if v_id is null then
    return false;
  end if;
  perform private.release_unpaid_components(v_id);
  delete from public.payment_charges where id = v_id;
  return true;
end;
$$;

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
  select id into v_id
  from public.payment_charges
  where id = p_charge_id
    and status = 'creating'
    and provider_ref is null
    and attempt_id is not distinct from p_attempt_id
    and (
      reserved_at is null
      or reserved_at < pg_catalog.now() - interval '2 minutes'
    )
  for update;
  if v_id is null then
    return false;
  end if;
  perform private.release_unpaid_components(v_id);
  delete from public.payment_charges where id = v_id;
  return true;
end;
$$;

create or replace function private.delete_compensated_charge(
  p_charge_id uuid,
  p_attempt_id uuid,
  p_provider_ref text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.ledger_entries entry
    where entry.payment_charge_id = p_charge_id
      and entry.direction = 'credit'
  ) then
    return false;
  end if;
  if not exists (
    select 1
    from public.payment_charges charge
    where charge.id = p_charge_id
      and charge.attempt_id is not distinct from p_attempt_id
      and charge.provider_ref = p_provider_ref
      and charge.status = 'cancelled'
      and charge.billing_type = 'CREDIT_CARD'
  ) then
    return false;
  end if;
  perform private.release_unpaid_components(p_charge_id);
  delete from public.payment_charges charge
  where charge.id = p_charge_id
    and charge.attempt_id is not distinct from p_attempt_id
    and charge.provider_ref = p_provider_ref
    and charge.status = 'cancelled'
    and charge.billing_type = 'CREDIT_CARD';
  return found;
end;
$$;
