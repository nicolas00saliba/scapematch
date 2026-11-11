-- Subconta Asaas "Reserva de pontos". Não aplicar no remoto.
-- Não cria subconta e não chama o Asaas. A flag continua desligada.
-- O split e a transferência só rodam no sandbox, no backend.

create table if not exists public.point_reserve_transfers (
  id uuid primary key default gen_random_uuid(),
  payment_charge_id uuid not null references public.payment_charges (id),
  purpose text not null check (purpose in ('house', 'platform_return')),
  amount_cents integer not null check (amount_cents > 0),
  destination_wallet_id text not null,
  status text not null default 'pending' check (
    status in ('pending', 'sending', 'done', 'failed')
  ),
  provider_ref text,
  created_at timestamptz not null default pg_catalog.now(),
  unique (payment_charge_id, purpose)
);

alter table public.point_reserve_transfers enable row level security;

drop policy if exists point_reserve_transfers_select
  on public.point_reserve_transfers;

create policy point_reserve_transfers_select
  on public.point_reserve_transfers
  for select to authenticated
  using (private.is_admin_aal2());

revoke all on public.point_reserve_transfers from public, anon, authenticated;
grant select on public.point_reserve_transfers to authenticated, service_role;

-- Centavos de indicação (c2c e c2b) que esta cobrança deve separar.
-- Zero com a flag desligada, sem indicação de jogador, ou quando a soma
-- não cabe no líquido depois da taxa e do repasse da casa.
create or replace function public.points_reserve_split_cents(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_charged integer,
  p_house_fixed integer,
  p_billing_type text
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.referral_program_settings%rowtype;
  v_player public.referral_attributions%rowtype;
  v_venue public.referral_attributions%rowtype;
  v_now timestamptz := pg_catalog.now();
  v_point integer;
  v_cents integer := 0;
  v_raw integer;
  v_fee integer;
  v_net integer;
begin
  if p_gross is null or p_gross <= 0 or p_charged is null or p_charged <= 0 then
    return 0;
  end if;
  select * into v_settings
  from public.referral_program_settings
  where id = 1;
  if not coalesce(v_settings.backed_full_slot_enabled, false) then
    return 0;
  end if;
  v_point := greatest(coalesce(v_settings.point_value_cents, 1), 1);

  select * into v_player
  from public.referral_attributions
  where subject_user_id = p_user_id;
  if v_player.id is not null
    and v_player.status = 'active'
    and v_player.referrer_kind = 'player'
    and v_now >= v_player.starts_at
    and v_now < v_player.ends_at
  then
    v_raw := private.reward_cents(
      p_gross,
      v_settings.c2c_bps + private.referrer_tier_bonus(v_player.referrer_user_id)
    );
    v_cents := v_cents + (v_raw / v_point) * v_point;
  end if;

  select * into v_venue
  from public.referral_attributions
  where subject_venue_id = p_venue_id;
  if v_venue.id is not null
    and v_venue.status = 'active'
    and v_venue.referrer_kind = 'player'
    and v_now >= v_venue.starts_at
    and v_now < v_venue.ends_at
  then
    v_raw := private.reward_cents(
      p_gross,
      v_settings.c2b_bps + private.referrer_tier_bonus(v_venue.referrer_user_id)
    );
    v_cents := v_cents + (v_raw / v_point) * v_point;
  end if;

  if v_cents <= 0 then
    return 0;
  end if;
  v_fee := private.estimated_receipt_fee_cents(p_billing_type, p_charged);
  v_net := p_charged - greatest(coalesce(v_fee, 0), 0);
  if coalesce(p_house_fixed, 0) + v_cents > v_net then
    return 0;
  end if;
  return v_cents;
end;
$$;

create or replace function public.claim_points_reserve_transfer(
  p_charge_id uuid,
  p_purpose text,
  p_amount_cents integer,
  p_wallet_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if p_purpose not in ('house', 'platform_return') then
    raise exception 'finalidade invalida' using errcode = '22023';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or p_wallet_id is null then
    raise exception 'transferencia invalida' using errcode = '22023';
  end if;
  insert into public.point_reserve_transfers (
    payment_charge_id, purpose, amount_cents, destination_wallet_id, status
  ) values (
    p_charge_id, p_purpose, p_amount_cents, p_wallet_id, 'pending'
  )
  on conflict (payment_charge_id, purpose) do nothing;

  select status into v_status
  from public.point_reserve_transfers
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
  for update;
  if v_status = 'done' then
    return 'done';
  end if;
  if v_status = 'sending' then
    return 'skip';
  end if;
  update public.point_reserve_transfers
  set status = 'sending',
      amount_cents = p_amount_cents,
      destination_wallet_id = p_wallet_id
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status in ('pending', 'failed');
  return 'send';
end;
$$;

create or replace function public.complete_points_reserve_transfer(
  p_charge_id uuid,
  p_purpose text,
  p_provider_ref text,
  p_ok boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.point_reserve_transfers
  set status = case when p_ok then 'done' else 'failed' end,
      provider_ref = coalesce(p_provider_ref, provider_ref)
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status = 'sending';
end;
$$;

create or replace function public.void_unapplied_points_reserve(p_charge_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.free_slot_topups%rowtype;
begin
  select * into v_row
  from public.free_slot_topups
  where payment_charge_id = p_charge_id
  for update;
  if v_row.id is null
    or v_row.voided_at is not null
    or v_row.applied_cents > 0
  then
    return false;
  end if;
  perform private.void_free_slot_topup(v_row.redemption_id);
  return true;
end;
$$;

revoke all on function public.points_reserve_split_cents(uuid, uuid, integer, integer, integer, text)
  from public, anon, authenticated;
revoke all on function public.claim_points_reserve_transfer(uuid, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.complete_points_reserve_transfer(uuid, text, text, boolean)
  from public, anon, authenticated;
revoke all on function public.void_unapplied_points_reserve(uuid)
  from public, anon, authenticated;

grant execute on function public.points_reserve_split_cents(uuid, uuid, integer, integer, integer, text)
  to service_role;
grant execute on function public.claim_points_reserve_transfer(uuid, text, integer, text)
  to service_role;
grant execute on function public.complete_points_reserve_transfer(uuid, text, text, boolean)
  to service_role;
grant execute on function public.void_unapplied_points_reserve(uuid)
  to service_role;
