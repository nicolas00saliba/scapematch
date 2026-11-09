-- Modelo 2 completo. Não aplicado no projeto remoto.
-- Desconto de 20% na primeira reserva qualificada, pago pela comissão.
-- Crédito de casa (B2C/B2B) libera em 30 dias e entra no split das
-- próximas cobranças da casa, também saindo da comissão.
-- Colunas novas têm default. Não apaga linha e não reescreve cobrança antiga.

alter table public.payment_charges
  add column if not exists venue_credit_applied_cents integer not null default 0;

alter table public.payment_charges
  add column if not exists venue_credit_clawback_cents integer not null default 0;

alter table public.payment_charges
  drop constraint if exists payment_charges_venue_credit_applied;

alter table public.payment_charges
  add constraint payment_charges_venue_credit_applied
  check (venue_credit_applied_cents >= 0);

alter table public.venue_referral_entries
  add column if not exists available_at timestamptz,
  add column if not exists applied_cents integer not null default 0;

alter table public.venue_referral_entries
  drop constraint if exists venue_referral_entries_settlement_check;

alter table public.venue_referral_entries
  add constraint venue_referral_entries_settlement_check
  check (settlement in ('pending', 'released', 'applied', 'reversed'));

alter table public.venue_referral_entries
  drop constraint if exists venue_referral_entries_applied_cents_check;

alter table public.venue_referral_entries
  add constraint venue_referral_entries_applied_cents_check
  check (applied_cents >= 0 and applied_cents <= amount_cents);

comment on column public.venue_referral_entries.settlement is
  'pending até a carência. released pode entrar no split. applied já foi para uma cobrança.';

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
      'venue_credit_refund',
      'venue_credit_clawback',
      'venue_credit_clawback_refund',
      'venue_credit_clawback_offset'
    )
  );

create table if not exists public.venue_credit_applications (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.venue_referral_entries (id),
  payment_charge_id uuid not null references public.payment_charges (id),
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default pg_catalog.now(),
  unique (entry_id, payment_charge_id)
);

alter table public.venue_credit_applications
  add column if not exists reversed_at timestamptz;

create table if not exists public.venue_credit_clawbacks (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  entry_id uuid not null references public.venue_referral_entries (id),
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  applied_charge_id uuid references public.payment_charges (id),
  voided_at timestamptz,
  neutralized_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (entry_id)
);

alter table public.venue_credit_clawbacks enable row level security;

revoke all on table public.venue_credit_clawbacks
  from public, anon, authenticated, service_role;

alter table public.venue_credit_applications enable row level security;

revoke all on table public.venue_credit_applications
  from public, anon, authenticated, service_role;

create or replace function private.stamp_venue_credit_hold()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days integer;
begin
  if new.kind = 'accrual' and new.available_at is null then
    select hold_days into v_days
    from public.referral_program_settings where id = 1;
    new.available_at := pg_catalog.now() + make_interval(days => coalesce(v_days, 30));
  end if;
  return new;
end;
$$;

drop trigger if exists venue_credit_hold on public.venue_referral_entries;
create trigger venue_credit_hold
  before insert on public.venue_referral_entries
  for each row execute function private.stamp_venue_credit_hold();

create or replace function private.release_due_venue_credits(
  p_now timestamptz default pg_catalog.now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.venue_referral_entries e
  set settlement = 'released'
  where e.kind = 'accrual'
    and e.settlement = 'pending'
    and e.available_at is not null
    and e.available_at <= p_now
    and e.review_status is distinct from 'em_revisao'
    and e.review_status is distinct from 'rejected'
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function private.first_booking_discount_for(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_subsidy_cents integer,
  p_except_charge uuid
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_bps integer;
  v_fee integer;
  v_wanted integer;
  v_room integer;
  v_referrer_venue uuid;
  v_qualifies boolean := false;
begin
  if p_gross is null or p_gross <= 1 then
    return 0;
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  if exists (
    select 1
    from public.payment_charges c
    where c.user_id = p_user_id
      and c.first_booking_discount_cents > 0
      and c.status in ('creating', 'pending', 'authorized', 'paid')
      and c.id is distinct from p_except_charge
  ) then
    return 0;
  end if;

  if exists (
    select 1
    from public.referral_attributions a
    where a.subject_user_id = p_user_id
      and a.status = 'active'
      and a.referrer_kind in ('player', 'venue')
  ) and not exists (
    select 1
    from public.payment_charges c
    where c.user_id = p_user_id
      and c.status in ('creating', 'pending', 'authorized', 'paid')
      and c.id is distinct from p_except_charge
  ) then
    v_qualifies := true;
  end if;

  if not v_qualifies then
    select a.referrer_venue_id into v_referrer_venue
    from public.referral_attributions a
    where a.subject_venue_id = p_venue_id
      and a.status = 'active'
      and a.referrer_kind = 'venue'
      and a.referrer_venue_id is not null;
    if v_referrer_venue is not null
      and exists (
        select 1
        from public.payment_charges c
        where c.user_id = p_user_id
          and c.venue_id = v_referrer_venue
          and c.status = 'paid'
      )
      and not exists (
        select 1
        from public.payment_charges c
        where c.user_id = p_user_id
          and c.venue_id = p_venue_id
          and c.status in ('creating', 'pending', 'authorized', 'paid')
          and c.id is distinct from p_except_charge
      )
    then
      v_qualifies := true;
    end if;
  end if;

  if not v_qualifies then
    return 0;
  end if;

  select first_booking_discount_bps into v_bps
  from public.referral_program_settings where id = 1;
  v_fee := private.reward_cents(p_gross, p_commission_bps);
  v_wanted := private.reward_cents(p_gross, coalesce(v_bps, 0));
  v_room := least(
    greatest(v_fee - coalesce(p_subsidy_cents, 0), 0),
    p_gross - coalesce(p_subsidy_cents, 0) - 1
  );
  if v_room < 0 then
    v_room := 0;
  end if;
  return least(v_wanted, v_room);
end;
$$;

create or replace function private.apply_venue_credit(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer
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
      and not exists (
        select 1 from public.venue_referral_entries r
        where r.relates_to = venue_referral_entries.id and r.kind = 'reversal'
      )
    order by available_at, created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    update public.venue_referral_entries
    set applied_cents = amount_cents,
        settlement = 'applied'
    where id = v_row.id;
    insert into public.venue_credit_applications (
      entry_id, payment_charge_id, amount_cents
    ) values (
      v_row.id, p_charge_id, v_open
    );
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

create or replace function private.restore_applied_venue_credits(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.venue_credit_clawbacks c
  set voided_at = pg_catalog.now()
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and c.entry_id = a.entry_id
    and c.voided_at is null
    and c.neutralized_at is null
    and c.applied_cents = 0;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    ch.venue_id,
    ch.group_id,
    ch.user_id,
    'house',
    'credit',
    'venue_credit_clawback_offset',
    sum(c.applied_cents),
    p_charge_id
  from public.venue_credit_clawbacks c
  join public.venue_credit_applications a on a.entry_id = c.entry_id
  join public.payment_charges ch on ch.id = p_charge_id
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and c.voided_at is null
    and c.neutralized_at is null
    and c.applied_cents > 0
  group by ch.venue_id, ch.group_id, ch.user_id
  on conflict (payment_charge_id, kind, direction) do nothing;

  update public.venue_credit_clawbacks c
  set neutralized_at = pg_catalog.now()
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and c.entry_id = a.entry_id
    and c.voided_at is null
    and c.neutralized_at is null
    and c.applied_cents > 0;

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

  update public.venue_credit_applications
  set reversed_at = pg_catalog.now()
  where payment_charge_id = p_charge_id
    and reversed_at is null;

  update public.venue_credit_clawbacks
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null
    and neutralized_at is null;
end;
$$;

create or replace function private.apply_venue_clawback(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.venue_credit_clawbacks%rowtype;
  v_open integer;
begin
  if v_left <= 0 then
    return 0;
  end if;
  for v_row in
    select *
    from public.venue_credit_clawbacks
    where venue_id = p_venue_id
      and voided_at is null
      and applied_cents < amount_cents
    order by created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    update public.venue_credit_clawbacks
    set applied_cents = amount_cents,
        applied_charge_id = p_charge_id
    where id = v_row.id
      and applied_cents = v_row.applied_cents
      and voided_at is null;
    if not found then
      continue;
    end if;
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

revoke all on function private.restore_applied_venue_credits(uuid) from public, anon, authenticated;
revoke all on function private.apply_venue_clawback(uuid, uuid, integer) from public, anon, authenticated;

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
  v_room := greatest(v_charged - v_house, 0);
  v_credit := private.apply_venue_credit(v_charge.id, v_charge.venue_id, v_room);
  if v_charged <= 0 or v_house + v_credit > v_charged then
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
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_fee_gross := (
    (v_gross::bigint * v_charge.commission_bps + 5000) / 10000
  )::integer;
  v_fee := v_fee_gross
    - v_charge.subsidy_cents
    - v_charge.first_booking_discount_cents
    - v_charge.venue_credit_applied_cents
    + v_charge.venue_credit_clawback_cents;
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
    )
    on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_charge.venue_credit_applied_cents > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'venue_credit_applied',
      v_charge.venue_credit_applied_cents, v_charge.id
    )
    on conflict (payment_charge_id, kind, direction) do nothing;
  end if;
  if v_charge.venue_credit_clawback_cents > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'debit', 'venue_credit_clawback',
      v_charge.venue_credit_clawback_cents, v_charge.id
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
  v_quote jsonb;
  v_discount integer;
  v_fee integer;
  v_subsidy integer;
  v_points integer;
  v_value integer;
  v_max_subsidy integer;
  v_charged integer;
  v_house integer;
  v_split numeric;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if v_group.id is null then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  v_bps := public.commission_bps_for_venue(v_group.venue_id);
  v_discount := private.first_booking_discount_for(
    auth.uid(), v_group.venue_id, v_group.price_cents, v_bps, 0, null
  );
  v_quote := private.subsidy_quote(
    auth.uid(), v_group.price_cents, v_bps, p_points, false
  );
  v_fee := (v_quote ->> 'commission_cents')::integer;
  v_value := (v_quote ->> 'point_value_cents')::integer;
  v_house := (v_quote ->> 'house_net_cents')::integer;
  v_max_subsidy := greatest(least(v_fee - v_discount, v_group.price_cents - v_discount - 1), 0);
  v_points := least(
    (v_quote ->> 'points')::integer,
    v_max_subsidy / greatest(v_value, 1)
  );
  v_subsidy := v_points * v_value;
  v_charged := v_group.price_cents - v_subsidy;
  if v_subsidy = 0 then
    v_split := null;
  else
    v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
  end if;
  return v_quote || pg_catalog.jsonb_build_object(
    'points', v_points,
    'subsidy_cents', v_subsidy,
    'charged_cents', v_charged,
    'split_percent', v_split,
    'max_points', v_max_subsidy / greatest(v_value, 1),
    'first_booking_discount_cents', v_discount
  );
end;
$$;

create or replace function public.my_venue_referral_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select id into v_venue
  from public.venues
  where owner_id = auth.uid()
  order by created_at desc
  limit 1;
  if v_venue is null then
    return null;
  end if;
  perform private.ensure_venue_code(v_venue);
  select code into v_code
  from public.referral_codes
  where owner_venue_id = v_venue;
  return v_code;
end;
$$;

create or replace function private.profile_referral_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_device text;
  v_phone text;
begin
  perform private.ensure_player_code(new.id);
  select raw_user_meta_data ->> 'referral_code',
         raw_user_meta_data ->> 'device_install_id',
         raw_user_meta_data ->> 'phone'
    into v_code, v_device, v_phone
  from auth.users
  where id = new.id;
  v_device := private.normalize_install_id(v_device);
  if v_device is not null then
    update public.profiles
    set device_install_id = v_device
    where id = new.id
      and device_install_id is null;
  end if;
  v_phone := pg_catalog.regexp_replace(coalesce(v_phone, ''), '\D', '', 'g');
  if v_phone ~ '^[0-9]{10,13}$' then
    update public.profiles
    set phone = v_phone
    where id = new.id
      and phone is null;
  end if;
  if v_code is not null and pg_catalog.btrim(v_code) <> '' then
    perform private.attach_referral('player', new.id, null, v_code, true);
  end if;
  return new;
end;
$$;

revoke all on function private.stamp_venue_credit_hold() from public, anon, authenticated;
revoke all on function private.release_due_venue_credits(timestamptz) from public, anon, authenticated;
revoke all on function private.first_booking_discount_for(uuid, uuid, integer, integer, integer, uuid) from public, anon, authenticated;
revoke all on function private.apply_venue_credit(uuid, uuid, integer) from public, anon, authenticated;
revoke all on function private.apply_share_adjustments(uuid) from public, anon, authenticated;
revoke all on function public.my_venue_referral_code() from public, anon, authenticated;

grant execute on function public.my_venue_referral_code() to authenticated;
