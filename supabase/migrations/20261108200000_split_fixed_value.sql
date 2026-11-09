-- O repasse da casa vai em fixedValue, igual ao líquido já ajustado.
-- A taxa estimada do Asaas sai só da comissão. Se o líquido não cabe
-- no netValue estimado, a reserva recusa com split_excede_liquido.

alter table public.platform_settings
  add column if not exists pix_receipt_fee_cents integer not null default 199
    check (pix_receipt_fee_cents >= 0),
  add column if not exists card_receipt_fee_cents integer not null default 49
    check (card_receipt_fee_cents >= 0),
  add column if not exists card_receipt_fee_bps integer not null default 299
    check (card_receipt_fee_bps between 0 and 10000);

alter table public.payment_charges
  add column if not exists house_fixed_cents integer not null default 0
    check (house_fixed_cents >= 0),
  add column if not exists split_divergence_at timestamptz,
  add column if not exists split_divergence_event text;

create or replace function private.estimated_receipt_fee_cents(
  p_billing text,
  p_charged integer
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pix integer;
  v_fixed integer;
  v_bps integer;
  v_charged integer := greatest(coalesce(p_charged, 0), 0);
  v_percent integer;
begin
  select pix_receipt_fee_cents, card_receipt_fee_cents, card_receipt_fee_bps
    into v_pix, v_fixed, v_bps
  from public.platform_settings
  where id = 1;
  v_pix := coalesce(v_pix, 199);
  v_fixed := coalesce(v_fixed, 49);
  v_bps := coalesce(v_bps, 299);
  if upper(coalesce(p_billing, '')) = 'PIX' then
    return least(v_pix, v_charged);
  end if;
  v_percent := ((v_charged::bigint * v_bps + 9999) / 10000)::integer;
  return least(v_charged, v_fixed + v_percent);
end;
$$;

create or replace function private.sync_house_fixed(p_charge_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fixed integer;
  v_net integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return 0;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_fixed := v_gross
    - private.reward_cents(v_gross, v_charge.commission_bps)
    + v_charge.venue_credit_applied_cents
    - v_charge.venue_credit_clawback_cents;
  if v_fixed < 0 then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  v_net := v_charge.amount_cents
    - private.estimated_receipt_fee_cents(
      v_charge.billing_type, v_charge.amount_cents
    );
  if v_fixed > v_net then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  update public.payment_charges
  set house_fixed_cents = v_fixed
  where id = p_charge_id;
  return v_fixed;
end;
$$;

create or replace function private.apply_share_adjustments(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee integer;
  v_house integer;
  v_discount integer;
  v_charged integer;
  v_asaas integer;
  v_net integer;
  v_room integer;
  v_credit integer;
  v_claw integer;
  v_for_house integer;
  v_split numeric;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null or v_charge.first_booking_discount_cents > 0 then
    return;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_discount := private.first_booking_discount_for(
    v_charge.user_id,
    v_charge.venue_id,
    v_gross,
    v_charge.commission_bps,
    v_charge.subsidy_cents,
    v_charge.id
  );
  v_fee := private.reward_cents(v_gross, v_charge.commission_bps);
  v_house := v_gross - v_fee;
  v_charged := v_gross - v_charge.subsidy_cents - v_discount;
  if v_charged <= 0 or v_house > v_charged then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
  end if;
  v_asaas := private.estimated_receipt_fee_cents(v_charge.billing_type, v_charged);
  v_net := v_charged - v_asaas;
  if v_discount > 0 and v_house > v_net then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
    v_asaas := private.estimated_receipt_fee_cents(
      v_charge.billing_type, v_charged
    );
    v_net := v_charged - v_asaas;
  end if;
  if v_house > v_net then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  v_room := greatest(v_net - v_house, 0);
  v_credit := private.apply_venue_credit(
    v_charge.id, v_charge.venue_id, v_room
  );
  if v_charged <= 0 or v_house + v_credit > v_net then
    return;
  end if;
  v_claw := private.apply_venue_clawback(
    v_charge.id, v_charge.venue_id, greatest(v_house, 0)
  );
  if v_discount = 0 and v_credit = 0 and v_claw = 0 then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_for_house := greatest(v_house - v_claw, 0) + v_credit;
  v_split := ceil((v_for_house::numeric * 1000000) / v_charged) / 10000;
  update public.payment_charges
  set amount_cents = v_charged,
      gross_amount_cents = v_gross,
      first_booking_discount_cents = v_discount,
      venue_credit_applied_cents = v_credit,
      venue_credit_clawback_cents = v_claw,
      split_percent = v_split
  where id = v_charge.id;
end;
$$;

create or replace function private.reserve_with_subsidy(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_billing_type text,
  p_gross_amount_cents integer default null,
  p_subsidy_cents integer default 0,
  p_points_redeemed integer default 0,
  p_split_percent numeric default null
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
  v_fixed integer;
begin
  if p_subsidy_cents > 0 and not exists (
    select 1
    from public.scape_point_entries e
    where e.client_key = p_idempotency_key
      and e.user_id = p_user_id
      and e.kind = 'redemption'
      and e.points = p_points_redeemed
      and e.amount_cents = p_subsidy_cents
      and not exists (
        select 1 from public.scape_point_entries r
        where r.relates_to = e.id and r.kind = 'redemption_reversal'
      )
  ) then
    raise exception 'hold ausente' using errcode = '42501';
  end if;

  insert into public.payment_charges (
    group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, provider_ref, idempotency_key, wallet_id, commission_bps,
    reserved_at, attempt_id, gross_amount_cents, subsidy_cents,
    points_redeemed, split_percent
  ) values (
    p_group_id, p_user_id, p_venue_id, p_amount_cents, p_billing_type, 'creating',
    'asaas', null, p_idempotency_key, p_wallet_id, p_commission_bps,
    pg_catalog.now(), gen_random_uuid(),
    case when p_subsidy_cents > 0 then p_gross_amount_cents else null end,
    coalesce(p_subsidy_cents, 0),
    case when p_subsidy_cents > 0 then p_points_redeemed else 0 end,
    case when p_subsidy_cents > 0 then p_split_percent else null end
  )
  on conflict (group_id, user_id) do nothing
  returning id into v_id;
  v_inserted := v_id is not null;

  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;

  if v_inserted and v_charge.points_redeemed > 0 then
    perform private.attach_point_hold(p_idempotency_key, v_charge.id);
  elsif not v_inserted and v_charge.points_redeemed = 0 then
    perform private.release_point_hold(p_idempotency_key);
  elsif not v_inserted and v_charge.points_redeemed > 0 then
    perform private.attach_point_hold(p_idempotency_key, v_charge.id);
  end if;

  if v_inserted then
    perform private.apply_share_adjustments(v_charge.id);
    select * into v_charge
    from public.payment_charges
    where id = v_charge.id;
  end if;

  if v_charge.provider_ref is not null then
    v_fixed := v_charge.house_fixed_cents;
  else
    v_fixed := private.sync_house_fixed(v_charge.id);
    select * into v_charge
    from public.payment_charges
    where id = v_charge.id;
  end if;

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
    'gross_amount_cents', v_charge.gross_amount_cents,
    'subsidy_cents', v_charge.subsidy_cents,
    'points_redeemed', v_charge.points_redeemed,
    'split_percent', v_charge.split_percent,
    'house_fixed_cents', v_fixed,
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

create or replace function private.note_split_divergence(
  p_provider_ref text,
  p_event text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_event not in (
    'PAYMENT_SPLIT_DIVERGENCE_BLOCK',
    'PAYMENT_SPLIT_DIVERGENCE_BLOCK_FINISHED'
  ) then
    return false;
  end if;
  update public.payment_charges
  set split_divergence_at = pg_catalog.now(),
      split_divergence_event = p_event
  where provider_ref = p_provider_ref
    and provider = 'asaas';
  return found;
end;
$$;

create or replace function public.note_split_divergence(
  p_provider_ref text,
  p_event text
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.note_split_divergence(p_provider_ref, p_event);
$$;

revoke all on function private.estimated_receipt_fee_cents(text, integer)
  from public, anon, authenticated;
revoke all on function private.sync_house_fixed(uuid)
  from public, anon, authenticated;
revoke all on function private.note_split_divergence(text, text)
  from public, anon, authenticated;
revoke all on function public.note_split_divergence(text, text)
  from public, anon, authenticated;
grant execute on function public.note_split_divergence(text, text) to service_role;
