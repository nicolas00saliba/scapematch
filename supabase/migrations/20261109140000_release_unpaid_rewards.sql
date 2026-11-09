-- O #85 também solta débito de horário vazio e devolução se a cobrança não paga.

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

  update public.venue_cashback_debits
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null;

  update public.venue_cashback_refunds
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null;

  update public.payment_charges
  set venue_credit_applied_cents = 0,
      venue_credit_clawback_cents = 0,
      empty_slot_offset_cents = 0,
      cashback_refund_cents = 0
  where id = p_charge_id;
end;
$$;

revoke all on function private.release_unpaid_components(uuid)
  from public, anon, authenticated;
