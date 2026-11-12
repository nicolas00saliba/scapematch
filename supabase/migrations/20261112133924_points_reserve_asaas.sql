-- Subconta Asaas "Reserva de pontos". Não aplicar no remoto.
-- Não cria subconta e não chama o Asaas. A flag continua desligada.
-- O split reserva a indicação e o teto do cashback. O sorteio só existe
-- depois do pagamento: o que não virar ponto volta para a conta raiz.
-- Tudo isso só no sandbox.

create table if not exists public.point_reserve_transfers (
  id uuid primary key default gen_random_uuid(),
  payment_charge_id uuid not null references public.payment_charges (id),
  purpose text not null check (purpose in (
    'house', 'platform_return', 'cashback_in', 'cashback_out', 'cashback_excess'
  )),
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

-- Centavos de indicação (c2c e c2b) mais o teto do cashback que esta
-- cobrança deve separar. O cashback entra mesmo sem indicação: toda
-- reserva paga pode sortear ponto com lastro. Zero com a flag desligada,
-- ou quando a soma não cabe no líquido depois da taxa e do repasse da casa.

alter table public.payment_charges
  add column if not exists cashback_reserve_cents integer not null default 0
    check (cashback_reserve_cents >= 0);

comment on column public.payment_charges.cashback_reserve_cents is
  'Teto de cashback que o split da Reserva de pontos já separou nesta cobrança. Zero quando o split não levou o cashback.';

create or replace function public.cashback_reserve_split_cents(p_gross integer)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.referral_program_settings%rowtype;
  v_point integer;
  v_raw integer;
begin
  if p_gross is null or p_gross <= 0 then
    return 0;
  end if;
  select * into v_settings
  from public.referral_program_settings
  where id = 1;
  if not coalesce(v_settings.backed_full_slot_enabled, false) then
    return 0;
  end if;
  v_point := greatest(coalesce(v_settings.point_value_cents, 1), 1);
  v_raw := private.reward_cents(p_gross, coalesce(v_settings.cashback_max_bps, 0));
  return (v_raw / v_point) * v_point;
end;
$$;
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
  v_cents := public.cashback_reserve_split_cents(p_gross);

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
  if p_purpose not in (
    'house', 'platform_return', 'cashback_in', 'cashback_out', 'cashback_excess'
  ) then
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

-- Fila do lastro de cashback. O trigger grava a linha; o backend, só no
-- sandbox, transfere entre a conta raiz e a subconta Reserva de pontos.
create or replace function private.queue_cashback_reserve(
  p_charge_id uuid,
  p_purpose text,
  p_cents integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_charge_id is null or p_cents is null or p_cents <= 0 then
    return;
  end if;
  if p_purpose not in ('cashback_in', 'cashback_out', 'cashback_excess') then
    return;
  end if;
  insert into public.point_reserve_transfers (
    payment_charge_id, purpose, amount_cents, destination_wallet_id, status
  ) values (
    p_charge_id, p_purpose, p_cents, 'points-reserve', 'pending'
  )
  on conflict (payment_charge_id, purpose) do nothing;
end;
$$;

create or replace function public.cashback_reserve_pending(p_charge_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'purpose', purpose,
    'amount_cents', amount_cents
  )), '[]'::jsonb)
  from public.point_reserve_transfers
  where payment_charge_id = p_charge_id
    and purpose in ('cashback_in', 'cashback_out', 'cashback_excess')
    and status in ('pending', 'failed');
$$;

-- O split já separou o teto. Aqui só entra o que o sorteio passou do teto,
-- ou sai o que o teto passou do sorteio. Sem split, o valor inteiro entra.
create or replace function private.reconcile_cashback_reserve(
  p_charge_id uuid,
  p_posted integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reserved integer := 0;
begin
  if p_charge_id is null or p_posted is null or p_posted <= 0 then
    return;
  end if;
  select cashback_reserve_cents into v_reserved
  from public.payment_charges
  where id = p_charge_id;
  v_reserved := coalesce(v_reserved, 0);
  if p_posted > v_reserved then
    perform private.queue_cashback_reserve(
      p_charge_id, 'cashback_in', p_posted - v_reserved
    );
  elsif v_reserved > p_posted then
    perform private.queue_cashback_reserve(
      p_charge_id, 'cashback_excess', v_reserved - p_posted
    );
  end if;
end;
$$;

create or replace function public.note_cashback_reserve(
  p_charge_id uuid,
  p_cents integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_charge_id is null or p_cents is null or p_cents <= 0 then
    return;
  end if;
  update public.payment_charges
  set cashback_reserve_cents = p_cents
  where id = p_charge_id;
end;
$$;

revoke all on function private.queue_cashback_reserve(uuid, text, integer)
  from public, anon, authenticated;
revoke all on function private.reconcile_cashback_reserve(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.cashback_reserve_split_cents(integer)
  from public, anon, authenticated;
revoke all on function public.note_cashback_reserve(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.cashback_reserve_pending(uuid)
  from public, anon, authenticated;
grant execute on function public.cashback_reserve_split_cents(integer)
  to service_role;
grant execute on function public.note_cashback_reserve(uuid, integer)
  to service_role;
grant execute on function public.cashback_reserve_pending(uuid)
  to service_role;
