-- Regras extras de Scape Points. Não aplicado no remoto.
-- Resgate mínimo, teto de 30%, boas-vindas, cashback sorteado,
-- horário vazio e níveis de quem indica. Tudo em referral_program_settings.

alter table public.referral_program_settings
  add column if not exists redeem_min_points integer not null default 1000
    check (redeem_min_points >= 0),
  add column if not exists redeem_max_bps integer not null default 3000
    check (redeem_max_bps between 0 and 10000),
  add column if not exists welcome_points integer not null default 100
    check (welcome_points >= 0),
  add column if not exists cashback_min_bps integer not null default 50
    check (cashback_min_bps between 0 and 10000),
  add column if not exists cashback_max_bps integer not null default 500
    check (cashback_max_bps between 0 and 10000),
  add column if not exists cashback_ev_cap_bps integer not null default 100
    check (cashback_ev_cap_bps between 0 and 10000),
  add column if not exists cashback_distribution jsonb not null default
    '[{"bps":50,"weight":700},{"bps":100,"weight":170},{"bps":200,"weight":90},{"bps":500,"weight":40}]'::jsonb,
  add column if not exists empty_slot_house_share_bps integer not null default 5000
    check (empty_slot_house_share_bps between 0 and 10000),
  add column if not exists tier_silver_active integer not null default 5
    check (tier_silver_active >= 0),
  add column if not exists tier_silver_bonus_bps integer not null default 50
    check (tier_silver_bonus_bps >= 0),
  add column if not exists tier_gold_active integer not null default 15
    check (tier_gold_active >= 0),
  add column if not exists tier_gold_bonus_bps integer not null default 100
    check (tier_gold_bonus_bps >= 0),
  add column if not exists tier_active_days integer not null default 90
    check (tier_active_days > 0);

alter table public.payment_charges
  add column if not exists empty_slot_offset_cents integer not null default 0
    check (empty_slot_offset_cents >= 0);

alter table public.payment_charges
  drop constraint if exists payment_charges_subsidy_matches;

alter table public.payment_charges
  add constraint payment_charges_subsidy_matches
  check (
    subsidy_cents = 0
    or (
      gross_amount_cents is not null
      and points_redeemed > 0
      and gross_amount_cents = amount_cents
        + subsidy_cents
        + first_booking_discount_cents
    )
  );

alter table public.scape_point_entries
  drop constraint if exists scape_point_entries_program_check;

alter table public.scape_point_entries
  add constraint scape_point_entries_program_check
  check (
    program is null
    or program in ('c2c', 'c2b', 'cashback', 'redeem', 'welcome')
  );

alter table public.ledger_entries
  drop constraint if exists ledger_entries_kind_check;

alter table public.ledger_entries
  add constraint ledger_entries_kind_check
  check (
    kind in (
      'house_net',
      'commission',
      'house_refund',
      'commission_refund',
      'venue_credit_applied',
      'empty_slot_offset'
    )
  );

create table if not exists public.cashback_draws (
  payment_charge_id uuid primary key references public.payment_charges (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  drawn_bps integer not null check (drawn_bps >= 0),
  applied_bps integer not null check (applied_bps >= 0),
  doubled boolean not null default false,
  house_share_cents integer not null default 0 check (house_share_cents >= 0),
  platform_cents integer not null default 0 check (platform_cents >= 0),
  seed text not null,
  distribution jsonb not null,
  created_at timestamptz not null default pg_catalog.now()
);

alter table public.cashback_draws enable row level security;
revoke all on table public.cashback_draws from public, anon, authenticated, service_role;

create policy cashback_draws_select on public.cashback_draws
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_admin());

grant select on table public.cashback_draws to authenticated;

create table if not exists public.venue_empty_slots (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  starts_minute integer not null check (starts_minute between 0 and 1439),
  ends_minute integer not null check (ends_minute between 1 and 1440),
  active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  check (ends_minute > starts_minute),
  unique (venue_id, weekday, starts_minute, ends_minute)
);

alter table public.venue_empty_slots enable row level security;
revoke all on table public.venue_empty_slots from public, anon, authenticated, service_role;

create policy venue_empty_slots_owner on public.venue_empty_slots
  for all to authenticated
  using (private.owns_venue(venue_id))
  with check (private.owns_venue(venue_id));

grant select, insert, update, delete on table public.venue_empty_slots to authenticated;

create table if not exists public.venue_cashback_debits (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  source_charge_id uuid not null references public.payment_charges (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  applied_charge_id uuid references public.payment_charges (id),
  created_at timestamptz not null default pg_catalog.now(),
  unique (source_charge_id)
);

alter table public.venue_cashback_debits enable row level security;
revoke all on table public.venue_cashback_debits from public, anon, authenticated, service_role;

create or replace function private.referrer_active_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.referral_attributions a
  where a.referrer_user_id = p_user_id
    and a.status = 'active'
    and exists (
      select 1
      from public.payment_charges c
      where c.status = 'paid'
        and c.paid_at >= pg_catalog.now() - make_interval(
          days => (
            select tier_active_days
            from public.referral_program_settings
            where id = 1
          )
        )
        and (
          (a.subject_user_id is not null and c.user_id = a.subject_user_id)
          or (a.subject_venue_id is not null and c.venue_id = a.subject_venue_id)
        )
    );
$$;

create or replace function private.referrer_tier_bonus(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_user_id is null then 0
    when private.referrer_active_count(p_user_id) >= s.tier_gold_active then s.tier_gold_bonus_bps
    when private.referrer_active_count(p_user_id) >= s.tier_silver_active then s.tier_silver_bonus_bps
    else 0
  end
  from public.referral_program_settings s
  where s.id = 1;
$$;

create or replace function private.referrer_tier_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case private.referrer_tier_bonus(p_user_id)
    when 0 then 'bronze'
    when (
      select tier_gold_bonus_bps from public.referral_program_settings where id = 1
    ) then 'ouro'
    else 'prata'
  end;
$$;

create or replace function private.cashback_distribution()
returns table (bps integer, weight integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.referral_program_settings%rowtype;
  v_ev numeric;
  v_weight integer;
begin
  select * into v_settings from public.referral_program_settings where id = 1;
  -- Faixa primeiro. A média só olha o que cabe entre o mínimo e o máximo.
  select coalesce(sum(band.weight), 0),
         coalesce(sum(band.bps::numeric * band.weight), 0)
    into v_weight, v_ev
  from (
    select (item ->> 'bps')::integer as bps,
           (item ->> 'weight')::integer as weight
    from pg_catalog.jsonb_array_elements(v_settings.cashback_distribution) item
    where (item ->> 'bps') ~ '^[0-9]+$'
      and (item ->> 'weight') ~ '^[0-9]+$'
      and (item ->> 'bps')::integer between v_settings.cashback_min_bps
        and v_settings.cashback_max_bps
      and (item ->> 'weight')::integer > 0
  ) band;
  if v_weight <= 0
    or v_ev / v_weight > v_settings.cashback_ev_cap_bps
  then
    return query select v_settings.cashback_min_bps, 1;
    return;
  end if;
  return query
  select (item ->> 'bps')::integer, (item ->> 'weight')::integer
  from pg_catalog.jsonb_array_elements(v_settings.cashback_distribution) item
  where (item ->> 'bps') ~ '^[0-9]+$'
    and (item ->> 'weight') ~ '^[0-9]+$'
    and (item ->> 'bps')::integer between v_settings.cashback_min_bps
      and v_settings.cashback_max_bps
    and (item ->> 'weight')::integer > 0;
end;
$$;

create or replace function private.venue_in_empty_slot(
  p_venue_id uuid,
  p_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venue_empty_slots s
    where s.venue_id = p_venue_id
      and s.active
      and s.weekday = extract(isodow from p_at at time zone 'America/Sao_Paulo')::integer
      and (
        extract(hour from p_at at time zone 'America/Sao_Paulo')::integer * 60
        + extract(minute from p_at at time zone 'America/Sao_Paulo')::integer
      ) >= s.starts_minute
      and (
        extract(hour from p_at at time zone 'America/Sao_Paulo')::integer * 60
        + extract(minute from p_at at time zone 'America/Sao_Paulo')::integer
      ) < s.ends_minute
  );
$$;

create or replace function private.post_player_cashback(
  p_charge_id uuid,
  p_pool integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_settings public.referral_program_settings%rowtype;
  v_existing integer;
  v_seed text;
  v_total integer := 0;
  v_roll integer;
  v_bps integer;
  v_row record;
  v_cursor integer := 0;
  v_paid timestamptz;
  v_value integer;
  v_base integer;
  v_extra integer := 0;
  v_house integer := 0;
  v_platform_extra integer := 0;
  v_cents integer;
  v_points integer;
  v_doubled boolean := false;
  v_platform_cost integer;
  v_inserted integer;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null then
    return 0;
  end if;
  select platform_cents into v_existing
  from public.cashback_draws
  where payment_charge_id = p_charge_id;
  if found then
    return v_existing;
  end if;
  select * into v_settings from public.referral_program_settings where id = 1;
  v_paid := coalesce(v_charge.paid_at, pg_catalog.now());
  v_value := v_settings.point_value_cents;
  select coalesce(sum(weight), 0)::integer into v_total from private.cashback_distribution();
  if v_total <= 0 then
    return 0;
  end if;
  v_seed := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(p_charge_id::text || ':' || pg_catalog.clock_timestamp()::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  v_roll := ('x' || pg_catalog.substr(v_seed, 1, 8))::bit(32)::bigint % v_total;
  v_bps := v_settings.cashback_min_bps;
  for v_row in select * from private.cashback_distribution() loop
    v_cursor := v_cursor + v_row.weight;
    if v_roll < v_cursor then
      v_bps := v_row.bps;
      exit;
    end if;
  end loop;
  v_base := least(private.reward_cents(v_charge.amount_cents, v_bps), greatest(p_pool, 0));
  if private.venue_in_empty_slot(v_charge.venue_id, v_paid) and v_base > 0 then
    v_doubled := true;
    v_extra := v_base;
    v_house := (v_extra * v_settings.empty_slot_house_share_bps) / 10000;
    v_platform_extra := v_extra - v_house;
    if v_platform_extra > greatest(p_pool, 0) - v_base then
      v_platform_extra := greatest(greatest(p_pool, 0) - v_base, 0);
      v_extra := v_platform_extra + v_house;
    end if;
  end if;
  v_cents := ((v_base + v_extra) / v_value) * v_value;
  v_points := v_cents / v_value;
  v_platform_cost := least(
    ((v_base + v_platform_extra) / v_value) * v_value,
    greatest(p_pool, 0)
  );
  insert into public.cashback_draws (
    payment_charge_id, user_id, drawn_bps, applied_bps, doubled,
    house_share_cents, platform_cents, seed, distribution
  ) values (
    p_charge_id, v_charge.user_id, v_bps,
    case when v_charge.amount_cents > 0 then (v_cents * 10000) / v_charge.amount_cents else 0 end,
    v_doubled, v_house, v_platform_cost, v_seed, v_settings.cashback_distribution
  )
  on conflict (payment_charge_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select platform_cents into v_platform_cost
    from public.cashback_draws
    where payment_charge_id = p_charge_id;
    return coalesce(v_platform_cost, 0);
  end if;
  if v_house > 0 then
    insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
    values (v_charge.venue_id, p_charge_id, v_house)
    on conflict (source_charge_id) do nothing;
  end if;
  if v_points > 0 then
    insert into public.scape_point_entries (
      user_id, kind, points, amount_cents, program,
      source_charge_id, payment_charge_id, idempotency_key, available_at
    ) values (
      v_charge.user_id, 'accrual', v_points, v_cents, 'cashback',
      p_charge_id, p_charge_id,
      'accrual:' || p_charge_id::text || ':cashback',
      v_paid + make_interval(days => v_settings.hold_days)
    )
    on conflict (idempotency_key) do nothing;
  end if;
  return v_platform_cost;
end;
$$;

create or replace function private.apply_empty_slot_debit(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer,
  p_commit boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.venue_cashback_debits%rowtype;
  v_open integer;
begin
  if v_left <= 0 then
    return 0;
  end if;
  for v_row in
    select *
    from public.venue_cashback_debits
    where venue_id = p_venue_id
      and applied_cents < amount_cents
      and source_charge_id is distinct from p_charge_id
    order by created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    if p_commit then
      update public.venue_cashback_debits
      set applied_cents = amount_cents,
          applied_charge_id = p_charge_id
      where id = v_row.id
        and applied_cents = v_row.applied_cents;
      if not found then
        continue;
      end if;
    end if;
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

create or replace function private.grant_welcome_points(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_points integer;
  v_value integer;
  v_cents integer;
  v_id uuid;
begin
  if p_user_id is null then
    return;
  end if;
  if not exists (
    select 1 from public.profiles
    where id = p_user_id and cpf is not null
  ) then
    return;
  end if;
  select welcome_points, point_value_cents into v_points, v_value
  from public.referral_program_settings where id = 1;
  if coalesce(v_points, 0) <= 0 then
    return;
  end if;
  v_cents := v_points * v_value;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key, available_at
  ) values (
    p_user_id, 'accrual', v_points, v_cents, 'welcome',
    'welcome:' || p_user_id::text, pg_catalog.now()
  )
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    return;
  end if;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, relates_to, idempotency_key
  ) values (
    p_user_id, 'release', v_points, v_cents, 'welcome', v_id,
    'release:welcome:' || p_user_id::text
  )
  on conflict (idempotency_key) do nothing;
end;
$$;

create or replace function public.set_my_cpf(p_cpf text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_digits text;
  v_current text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_digits := pg_catalog.regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  if not public.is_valid_cpf(v_digits) then
    raise exception 'cpf invalido' using errcode = '22023';
  end if;
  select p.cpf into v_current
  from public.profiles p
  where p.id = auth.uid()
  for update;
  if not found then
    raise exception 'perfil ausente' using errcode = 'P0002';
  end if;
  if v_current is not null then
    raise exception 'cpf ja definido' using errcode = '55000';
  end if;
  update public.profiles
    set cpf = v_digits
    where id = auth.uid()
      and cpf is null;
  if not found then
    raise exception 'cpf ja definido' using errcode = '55000';
  end if;
  insert into public.profile_cpf_audit (user_id, defined_at)
  values (auth.uid(), pg_catalog.clock_timestamp());
  perform private.grant_welcome_points(auth.uid());
  return true;
end;
$$;

create or replace function private.quote_redemption(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote jsonb;
  v_discount integer;
  v_fee integer;
  v_value integer;
  v_min integer;
  v_house integer;
  v_room integer;
  v_cap_points integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
  v_cash_min integer;
  v_cash_max integer;
begin
  v_discount := private.first_booking_discount_for(
    p_user_id, p_venue_id, p_gross, p_commission_bps, 0, null
  );
  v_quote := private.subsidy_quote(
    p_user_id, p_gross, p_commission_bps, p_points, false
  );
  v_fee := (v_quote ->> 'commission_cents')::integer;
  v_value := greatest((v_quote ->> 'point_value_cents')::integer, 1);
  v_min := coalesce((v_quote ->> 'redeem_min_points')::integer, 0);
  v_house := (v_quote ->> 'house_net_cents')::integer;
  v_room := greatest(least(v_fee - v_discount, p_gross - v_discount - 1), 0);
  v_cap_points := least(
    coalesce((v_quote ->> 'max_points')::integer, 0),
    v_room / v_value
  );
  if v_cap_points < v_min then
    v_cap_points := 0;
  end if;
  v_points := least(coalesce((v_quote ->> 'points')::integer, 0), v_cap_points);
  if v_points < v_min then
    v_points := 0;
  end if;
  v_subsidy := v_points * v_value;
  v_charged := p_gross - v_subsidy;
  if v_subsidy = 0 or v_charged <= 0 then
    v_split := null;
  else
    v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
  end if;
  select cashback_min_bps, cashback_max_bps into v_cash_min, v_cash_max
  from public.referral_program_settings where id = 1;
  return v_quote || pg_catalog.jsonb_build_object(
    'points', v_points,
    'subsidy_cents', v_subsidy,
    'charged_cents', v_charged,
    'split_percent', v_split,
    'max_points', v_cap_points,
    'first_booking_discount_cents', v_discount,
    'cashback_min_bps', v_cash_min,
    'cashback_max_bps', v_cash_max
  );
end;
$$;

create or replace function public.cap_point_redemption(
  p_group_id uuid,
  p_user_id uuid,
  p_points integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups%rowtype;
  v_bps integer;
  v_quote jsonb;
begin
  select * into v_group from public.groups where id = p_group_id;
  if v_group.id is null then
    return 0;
  end if;
  v_bps := public.commission_bps_for_venue(v_group.venue_id);
  v_quote := private.quote_redemption(
    p_user_id, v_group.venue_id, v_group.price_cents, v_bps, p_points
  );
  return coalesce((v_quote ->> 'points')::integer, 0);
end;
$$;

create or replace function private.subsidy_quote(
  p_user_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_points integer,
  p_lock boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point integer;
  v_available integer;
  v_fee integer;
  v_house integer;
  v_room integer;
  v_max_subsidy integer;
  v_cap_cents integer;
  v_max_points integer;
  v_min integer;
  v_max_bps integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
begin
  if p_lock then
    perform 1 from public.profiles where id = p_user_id for update;
  end if;
  select point_value_cents, redeem_min_points, redeem_max_bps
    into v_point, v_min, v_max_bps
  from public.referral_program_settings where id = 1;
  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := greatest(coalesce(v_available, 0), 0);
  v_fee := private.reward_cents(p_gross, p_commission_bps);
  v_house := p_gross - v_fee;
  v_room := case when p_gross > 1 then p_gross - 1 else 0 end;
  v_cap_cents := private.reward_cents(p_gross, coalesce(v_max_bps, 10000));
  v_max_subsidy := least(greatest(v_fee, 0), v_room, greatest(v_cap_cents, 0));
  v_max_points := v_max_subsidy / v_point;
  if v_available < coalesce(v_min, 0) or v_max_points < coalesce(v_min, 0) then
    v_max_points := 0;
  end if;
  v_points := least(greatest(coalesce(p_points, 0), 0), v_available, v_max_points);
  if v_points < coalesce(v_min, 0) then
    v_points := 0;
  end if;
  v_subsidy := v_points * v_point;
  v_charged := p_gross - v_subsidy;
  if v_subsidy = 0 then
    v_split := null;
  else
    v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
  end if;
  return pg_catalog.jsonb_build_object(
    'gross_cents', p_gross,
    'charged_cents', v_charged,
    'subsidy_cents', v_subsidy,
    'points', v_points,
    'house_net_cents', v_house,
    'commission_cents', v_fee,
    'split_percent', v_split,
    'max_points', v_max_points,
    'available_points', v_available,
    'point_value_cents', v_point,
    'redeem_min_points', v_min,
    'redeem_max_bps', v_max_bps
  );
end;
$$;

create or replace function public.my_rewards_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_active integer;
  v_bonus integer;
  v_min integer;
  v_pending integer;
  v_available integer;
  v_silver integer;
  v_gold integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points into v_pending, v_available
  from private.scape_balances(v_uid);
  v_active := private.referrer_active_count(v_uid);
  v_bonus := private.referrer_tier_bonus(v_uid);
  select redeem_min_points, tier_silver_active, tier_gold_active
    into v_min, v_silver, v_gold
  from public.referral_program_settings where id = 1;
  return pg_catalog.jsonb_build_object(
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'redeem_min_points', v_min,
    'tier', private.referrer_tier_name(v_uid),
    'tier_bonus_bps', v_bonus,
    'active_referrals', v_active,
    'silver_at', v_silver,
    'gold_at', v_gold,
    'cashback_min_bps', (select cashback_min_bps from public.referral_program_settings where id = 1),
    'cashback_max_bps', (select cashback_max_bps from public.referral_program_settings where id = 1)
  );
end;
$$;

create or replace function public.upsert_venue_empty_slot(
  p_venue_id uuid,
  p_weekday integer,
  p_starts_minute integer,
  p_ends_minute integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.owns_venue(p_venue_id) and not private.is_admin() then
    raise exception 'not owner' using errcode = '42501';
  end if;
  insert into public.venue_empty_slots (
    venue_id, weekday, starts_minute, ends_minute
  ) values (
    p_venue_id, p_weekday, p_starts_minute, p_ends_minute
  )
  on conflict (venue_id, weekday, starts_minute, ends_minute)
  do update set active = true
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.my_venue_empty_slots()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.weekday, s.starts_minute)
    from (
      select id, venue_id, weekday, starts_minute, ends_minute, active
      from public.venue_empty_slots
      where private.owns_venue(venue_id) and active
    ) s
  ), '[]'::jsonb);
end;
$$;

revoke all on function private.referrer_active_count(uuid) from public, anon, authenticated;
revoke all on function private.referrer_tier_bonus(uuid) from public, anon, authenticated;
revoke all on function private.referrer_tier_name(uuid) from public, anon, authenticated;
revoke all on function private.cashback_distribution() from public, anon, authenticated;
revoke all on function private.venue_in_empty_slot(uuid, timestamptz) from public, anon, authenticated;
revoke all on function private.post_player_cashback(uuid, integer) from public, anon, authenticated;
revoke all on function private.apply_empty_slot_debit(uuid, uuid, integer, boolean) from public, anon, authenticated;
revoke all on function private.grant_welcome_points(uuid) from public, anon, authenticated;
revoke all on function private.quote_redemption(uuid, uuid, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.cap_point_redemption(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.my_rewards_summary() from public, anon;
revoke all on function public.upsert_venue_empty_slot(uuid, integer, integer, integer) from public, anon;
revoke all on function public.my_venue_empty_slots() from public, anon;

grant execute on function public.cap_point_redemption(uuid, uuid, integer) to service_role;
grant execute on function public.my_rewards_summary() to authenticated;
grant execute on function public.upsert_venue_empty_slot(uuid, integer, integer, integer) to authenticated;
grant execute on function public.my_venue_empty_slots() to authenticated;

drop function if exists private.apply_venue_credit(uuid, uuid, integer);

create or replace function private.apply_venue_credit(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer,
  p_commit boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.venue_referral_entries%rowtype;
  v_open integer;
begin
  if v_left <= 0 then
    return 0;
  end if;
  if exists (
    select 1 from public.venue_credit_applications
    where payment_charge_id = p_charge_id
  ) then
    select coalesce(sum(amount_cents), 0)::integer into v_taken
    from public.venue_credit_applications
    where payment_charge_id = p_charge_id;
    return v_taken;
  end if;
  for v_row in
    select *
    from public.venue_referral_entries
    where venue_id = p_venue_id
      and kind = 'accrual'
      and settlement = 'released'
      and review_status is distinct from 'em_revisao'
      and review_status is distinct from 'rejected'
    order by available_at, created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    if p_commit then
      update public.venue_referral_entries
      set applied_cents = amount_cents,
          settlement = 'applied'
      where id = v_row.id
        and settlement = 'released';
      if not found then
        continue;
      end if;
      insert into public.venue_credit_applications (
        entry_id, payment_charge_id, amount_cents
      ) values (
        v_row.id, p_charge_id, v_open
      );
    end if;
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

revoke all on function private.apply_venue_credit(uuid, uuid, integer, boolean) from public, anon, authenticated;

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
  v_room integer;
  v_credit integer;
  v_debit integer;
  v_for_house integer;
  v_split numeric;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  if v_charge.first_booking_discount_cents > 0
    or v_charge.venue_credit_applied_cents > 0
    or v_charge.empty_slot_offset_cents > 0
  then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_discount := private.first_booking_discount_for(
    v_charge.user_id, v_charge.venue_id, v_gross,
    v_charge.commission_bps, v_charge.subsidy_cents, v_charge.id
  );
  v_fee := private.reward_cents(v_gross, v_charge.commission_bps);
  v_house := v_gross - v_fee;
  v_charged := v_gross - v_charge.subsidy_cents - v_discount;
  if v_charged <= 0 then
    if v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_room := greatest(v_charged - v_house, 0);
  v_credit := private.apply_venue_credit(
    v_charge.id, v_charge.venue_id, v_room, false
  );
  v_debit := private.apply_empty_slot_debit(
    v_charge.id, v_charge.venue_id, greatest(v_house, 0), false
  );
  v_for_house := greatest(v_house - v_debit, 0) + v_credit;
  if v_for_house > v_charged then
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if v_discount = 0 and v_credit = 0 and v_debit = 0 then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if private.apply_venue_credit(v_charge.id, v_charge.venue_id, v_room, true)
    is distinct from v_credit
    or private.apply_empty_slot_debit(
      v_charge.id, v_charge.venue_id, greatest(v_house, 0), true
    ) is distinct from v_debit
  then
    raise exception 'ajuste mudou antes de gravar' using errcode = '40001';
  end if;
  v_split := ceil((v_for_house::numeric * 1000000) / v_charged) / 10000;
  update public.payment_charges
  set amount_cents = v_charged,
      gross_amount_cents = v_gross,
      first_booking_discount_cents = v_discount,
      venue_credit_applied_cents = v_credit,
      empty_slot_offset_cents = v_debit,
      split_percent = v_split
  where id = v_charge.id;
end;
$$;

create or replace function private.ledger_credit_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee_gross integer;
  v_fee integer;
  v_net integer;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_fee_gross := ((v_gross::bigint * v_charge.commission_bps + 5000) / 10000)::integer;
  v_fee := v_fee_gross
    - v_charge.subsidy_cents
    - v_charge.first_booking_discount_cents
    - v_charge.venue_credit_applied_cents
    + v_charge.empty_slot_offset_cents;
  v_net := v_gross - v_fee_gross;
  if v_net < 0 or v_fee < 0 then
    raise exception 'comissao negativa' using errcode = '23514';
  end if;
  if v_net > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'house_net', v_net, v_charge.id
    ) on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_charge.venue_credit_applied_cents > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'venue_credit_applied',
      v_charge.venue_credit_applied_cents, v_charge.id
    ) on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_charge.empty_slot_offset_cents > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'debit', 'empty_slot_offset',
      v_charge.empty_slot_offset_cents, v_charge.id
    ) on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_fee > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'platform', 'credit', 'commission', v_fee, v_charge.id
    ) on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
end;
$$;

create or replace function private.cashback_points_ok(p_charge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.scape_point_entries e
    join public.cashback_draws d on d.payment_charge_id = e.source_charge_id
    join public.referral_program_settings s on s.id = 1
    where e.source_charge_id = p_charge_id
      and e.program = 'cashback'
      and e.kind = 'accrual'
      and d.drawn_bps between s.cashback_min_bps and s.cashback_max_bps
      and e.points > 0
      and e.amount_cents = e.points * s.point_value_cents
  );
$$;

revoke all on function private.cashback_points_ok(uuid) from public, anon, authenticated;

create or replace function public.quote_my_point_subsidy(
  p_group_id uuid,
  p_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups%rowtype;
  v_bps integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if v_group.id is null then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  v_bps := public.commission_bps_for_venue(v_group.venue_id);
  return private.quote_redemption(
    auth.uid(), v_group.venue_id, v_group.price_cents, v_bps, p_points
  );
end;
$$;

create or replace function public.my_scape_wallet()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pending integer;
  v_available integer;
  v_point integer;
  v_created timestamptz;
  v_summary jsonb;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points into v_pending, v_available
  from private.scape_balances(v_uid);
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select created_at into v_created from public.profiles where id = v_uid;
  v_summary := public.my_rewards_summary();
  return pg_catalog.jsonb_build_object(
    'referral_code', (select code from public.referral_codes where owner_user_id = v_uid),
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'point_value_cents', v_point,
    'redeem_min_points', v_summary -> 'redeem_min_points',
    'tier', v_summary -> 'tier',
    'tier_bonus_bps', v_summary -> 'tier_bonus_bps',
    'active_referrals', v_summary -> 'active_referrals',
    'silver_at', v_summary -> 'silver_at',
    'gold_at', v_summary -> 'gold_at',
    'attributed', exists (
      select 1 from public.referral_attributions where subject_user_id = v_uid
    ),
    'can_claim', v_created >= pg_catalog.now() - interval '24 hours'
      and not exists (
        select 1 from public.referral_attributions where subject_user_id = v_uid
      ),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s))
      from (
        select e.kind, e.program, e.points, e.amount_cents, e.available_at,
               e.created_at, e.review_status, d.drawn_bps, d.doubled
        from public.scape_point_entries e
        left join public.cashback_draws d
          on d.payment_charge_id = e.source_charge_id
         and e.program = 'cashback'
        where e.user_id = v_uid
        order by e.created_at desc
        limit 50
      ) s
    ), '[]'::jsonb)
  );
end;
$$;
