-- Scape Points (Modelo 2). Não aplicar no projeto remoto por este agente.
-- A recompensa sai da comissão da ScapeMatch. A casa continua com o líquido
-- cheio. 1 ponto = point_value_cents (padrão 1 centavo). O ponto não vence
-- e não saca. partner_invites continua sendo convite de cadastro da casa,
-- não código de indicação. venues.referred_by segue a casa que indicou
-- outra casa (B2B); jogador que indicou casa fica só na atribuição.

create table public.referral_program_settings (
  id integer primary key default 1 check (id = 1),
  c2c_bps integer not null default 250 check (c2c_bps between 0 and 10000),
  b2c_bps integer not null default 250 check (b2c_bps between 0 and 10000),
  c2b_bps integer not null default 250 check (c2b_bps between 0 and 10000),
  b2b_bps integer not null default 500 check (b2b_bps between 0 and 10000),
  point_value_cents integer not null default 1 check (point_value_cents > 0),
  attribution_days integer not null default 365 check (attribution_days > 0),
  hold_days integer not null default 30 check (hold_days >= 0),
  cashback_bps integer not null default 100 check (cashback_bps between 0 and 10000),
  first_booking_discount_bps integer not null default 2000 check (
    first_booking_discount_bps between 0 and 10000
  ),
  updated_at timestamptz not null default pg_catalog.now()
);

insert into public.referral_program_settings (id) values (1);

comment on table public.referral_program_settings is
  'Modelo 2. 1 ponto vale point_value_cents centavos (padrão R$ 0,01). cashback_bps é o percentual do pagador (padrão 1%). O desconto da primeira reserva fica guardado e ainda não é aplicado.';

alter table public.profiles
  add column phone text;

alter table public.profiles
  add constraint profiles_phone_digits
  check (phone is null or phone ~ '^[0-9]{10,13}$');

comment on column public.profiles.phone is
  'Opcional. A antifraude só compara quando os dois lados têm telefone. O app ainda não pede este campo.';

alter table public.payment_charges
  add column gross_amount_cents integer,
  add column subsidy_cents integer not null default 0,
  add column points_redeemed integer not null default 0,
  add column split_percent numeric(7, 4);

alter table public.payment_charges
  add constraint payment_charges_subsidy_nonnegative
  check (subsidy_cents >= 0 and points_redeemed >= 0);

alter table public.payment_charges
  add column first_booking_discount_cents integer not null default 0;

alter table public.payment_charges
  add constraint payment_charges_first_booking_discount
  check (first_booking_discount_cents >= 0);

alter table public.payment_charges
  add column payer_document_status text;

alter table public.payment_charges
  add constraint payment_charges_payer_document_status
  check (
    payer_document_status is null
    or payer_document_status in ('matched', 'mismatch', 'unverified')
  );

alter table public.payment_charges
  add constraint payment_charges_subsidy_matches
  check (
    subsidy_cents = 0
    or (
      gross_amount_cents is not null
      and points_redeemed > 0
      and gross_amount_cents = amount_cents + subsidy_cents
    )
  );

create table public.referral_codes (
  code text primary key check (code ~ '^[A-Z0-9]{8}$'),
  owner_kind text not null check (owner_kind in ('player', 'venue')),
  owner_user_id uuid references auth.users (id) on delete cascade,
  owner_venue_id uuid references public.venues (id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  check (
    (owner_kind = 'player' and owner_user_id is not null and owner_venue_id is null)
    or (owner_kind = 'venue' and owner_venue_id is not null and owner_user_id is null)
  )
);

create unique index referral_codes_one_player
  on public.referral_codes (owner_user_id)
  where owner_user_id is not null;

create unique index referral_codes_one_venue
  on public.referral_codes (owner_venue_id)
  where owner_venue_id is not null;

create table public.referral_attributions (
  id uuid primary key default gen_random_uuid(),
  subject_kind text not null check (subject_kind in ('player', 'venue')),
  subject_user_id uuid references auth.users (id) on delete cascade,
  subject_venue_id uuid references public.venues (id) on delete cascade,
  referrer_kind text not null check (referrer_kind in ('player', 'venue')),
  referrer_user_id uuid references auth.users (id) on delete cascade,
  referrer_venue_id uuid references public.venues (id) on delete cascade,
  code text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'active' check (status in ('active', 'blocked')),
  block_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  check (ends_at > starts_at),
  check (
    (subject_kind = 'player' and subject_user_id is not null and subject_venue_id is null)
    or (subject_kind = 'venue' and subject_venue_id is not null and subject_user_id is null)
  ),
  check (
    (referrer_kind = 'player' and referrer_user_id is not null and referrer_venue_id is null)
    or (referrer_kind = 'venue' and referrer_venue_id is not null and referrer_user_id is null)
  ),
  check (
    subject_user_id is null
    or subject_user_id is distinct from referrer_user_id
  ),
  check (
    subject_venue_id is null
    or subject_venue_id is distinct from referrer_venue_id
  ),
  check (
    block_reason is null
    or block_reason in (
      'shared_cpf',
      'shared_phone',
      'shared_card',
      'shared_document',
      'player_owns_venue'
    )
  )
);

create unique index referral_attributions_one_player
  on public.referral_attributions (subject_user_id)
  where subject_user_id is not null;

create unique index referral_attributions_one_venue
  on public.referral_attributions (subject_venue_id)
  where subject_venue_id is not null;

create index referral_attributions_by_referrer_user
  on public.referral_attributions (referrer_user_id, created_at desc);

create index referral_attributions_by_referrer_venue
  on public.referral_attributions (referrer_venue_id, created_at desc);

create table public.scape_point_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (
    kind in (
      'accrual',
      'release',
      'reversal',
      'redemption',
      'redemption_reversal'
    )
  ),
  points integer not null check (points > 0),
  amount_cents integer not null check (amount_cents > 0),
  program text check (
    program is null or program in ('c2c', 'c2b', 'cashback', 'redeem')
  ),
  source_charge_id uuid,
  payment_charge_id uuid references public.payment_charges (id) on delete set null,
  relates_to uuid references public.scape_point_entries (id),
  client_key text,
  gross_cents integer,
  split_percent numeric(7, 4),
  idempotency_key text not null unique,
  available_at timestamptz,
  review_status text check (
    review_status is null
    or review_status in ('em_revisao', 'approved', 'rejected')
  ),
  created_at timestamptz not null default pg_catalog.now()
);

create unique index scape_point_accrual_once
  on public.scape_point_entries (source_charge_id, program)
  where kind = 'accrual' and source_charge_id is not null;

create unique index scape_point_child_once
  on public.scape_point_entries (relates_to, kind)
  where relates_to is not null
    and kind in ('release', 'reversal', 'redemption_reversal');

create index scape_point_by_user
  on public.scape_point_entries (user_id, created_at desc);

create index scape_point_by_client_key
  on public.scape_point_entries (client_key)
  where client_key is not null;

create table public.venue_referral_entries (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  kind text not null check (kind in ('accrual', 'reversal')),
  amount_cents integer not null check (amount_cents > 0),
  program text not null check (program in ('b2c', 'b2b')),
  settlement text not null default 'pending' check (settlement = 'pending'),
  source_charge_id uuid,
  payment_charge_id uuid references public.payment_charges (id) on delete set null,
  relates_to uuid references public.venue_referral_entries (id),
  idempotency_key text not null unique,
  review_status text check (
    review_status is null
    or review_status in ('em_revisao', 'approved', 'rejected')
  ),
  created_at timestamptz not null default pg_catalog.now()
);

comment on column public.venue_referral_entries.settlement is
  'Crédito devido à casa. Ainda não abate repasse. Fica pendente de propósito.';

create unique index venue_referral_accrual_once
  on public.venue_referral_entries (source_charge_id, program)
  where kind = 'accrual' and source_charge_id is not null;

create unique index venue_referral_reversal_once
  on public.venue_referral_entries (relates_to)
  where kind = 'reversal' and relates_to is not null;

create index venue_referral_by_venue
  on public.venue_referral_entries (venue_id, created_at desc);

create or replace function private.reward_cents(p_amount integer, p_bps integer)
returns integer
language sql
immutable
security definer
set search_path = ''
as $$
  select ((p_amount::bigint * p_bps + 5000) / 10000)::integer;
$$;

create or replace function private.ensure_player_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_try integer := 0;
begin
  select code into v_code
  from public.referral_codes
  where owner_user_id = p_user_id;
  if v_code is not null then
    return v_code;
  end if;
  loop
    v_try := v_try + 1;
    v_code := pg_catalog.upper(pg_catalog.substr(
      pg_catalog.replace(gen_random_uuid()::text, '-', ''),
      1,
      8
    ));
    begin
      insert into public.referral_codes (code, owner_kind, owner_user_id)
      values (v_code, 'player', p_user_id);
      return v_code;
    exception
      when unique_violation then
        if v_try >= 8 then
          raise exception 'codigo indisponivel' using errcode = '23505';
        end if;
    end;
  end loop;
end;
$$;

create or replace function private.ensure_venue_code(p_venue_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_try integer := 0;
begin
  select code into v_code
  from public.referral_codes
  where owner_venue_id = p_venue_id;
  if v_code is not null then
    return v_code;
  end if;
  loop
    v_try := v_try + 1;
    v_code := pg_catalog.upper(pg_catalog.substr(
      pg_catalog.replace(gen_random_uuid()::text, '-', ''),
      1,
      8
    ));
    begin
      insert into public.referral_codes (code, owner_kind, owner_venue_id)
      values (v_code, 'venue', p_venue_id);
      return v_code;
    exception
      when unique_violation then
        if v_try >= 8 then
          raise exception 'codigo indisponivel' using errcode = '23505';
        end if;
    end;
  end loop;
end;
$$;

create or replace function private.identity_conflict(
  p_user_a uuid,
  p_user_b uuid,
  p_venue_a uuid,
  p_venue_b uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cpf_a text;
  v_cpf_b text;
  v_phone_a text;
  v_phone_b text;
  v_doc_a text;
  v_doc_b text;
  v_owner uuid;
  v_owner_cpf text;
begin
  if p_user_a is not null then
    select cpf, phone into v_cpf_a, v_phone_a
    from public.profiles where id = p_user_a;
  end if;
  if p_user_b is not null and p_user_b is distinct from p_user_a then
    select cpf, phone into v_cpf_b, v_phone_b
    from public.profiles where id = p_user_b;
    if v_cpf_a is not null and v_cpf_a = v_cpf_b then
      return 'shared_cpf';
    end if;
    if v_phone_a is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
    if exists (
      select 1
      from public.saved_cards a
      join public.saved_cards b
        on a.credit_card_token = b.credit_card_token
      where a.user_id = p_user_a
        and b.user_id = p_user_b
    ) then
      return 'shared_card';
    end if;
  end if;

  if p_user_a is not null and p_venue_a is not null then
    select document_number, phone, owner_id
      into v_doc_a, v_phone_b, v_owner
    from public.venues
    where id = p_venue_a;
    if v_cpf_a is not null and v_doc_a is not null and v_cpf_a = v_doc_a then
      return 'player_owns_venue';
    end if;
    if v_owner is not null then
      select cpf into v_owner_cpf from public.profiles where id = v_owner;
      if v_cpf_a is not null and v_cpf_a = v_owner_cpf then
        return 'player_owns_venue';
      end if;
    end if;
    if v_phone_a is not null and v_phone_b is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
  end if;

  if p_venue_a is not null and p_venue_b is not null and p_venue_a <> p_venue_b then
    select a.document_number, a.phone, b.document_number, b.phone
      into v_doc_a, v_phone_a, v_doc_b, v_phone_b
    from public.venues a
    join public.venues b on b.id = p_venue_b
    where a.id = p_venue_a;
    if v_doc_a is not null and v_doc_a = v_doc_b then
      return 'shared_document';
    end if;
    if v_phone_a is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
  end if;
  return null;
end;
$$;

create or replace function private.attach_referral(
  p_subject_kind text,
  p_subject_user uuid,
  p_subject_venue uuid,
  p_code text,
  p_enforce_window boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_owner_kind text;
  v_owner_user uuid;
  v_owner_venue uuid;
  v_started timestamptz;
  v_days integer;
  v_reason text;
begin
  if p_subject_kind = 'player' then
    if exists (
      select 1 from public.referral_attributions
      where subject_user_id = p_subject_user
    ) then
      return 'exists';
    end if;
    select created_at into v_started
    from public.profiles where id = p_subject_user;
  else
    if exists (
      select 1 from public.referral_attributions
      where subject_venue_id = p_subject_venue
    ) then
      return 'exists';
    end if;
    select created_at into v_started
    from public.venues where id = p_subject_venue;
  end if;
  if v_started is null then
    return 'invalid';
  end if;
  if p_enforce_window
    and v_started < pg_catalog.now() - interval '24 hours'
  then
    return 'late';
  end if;

  v_code := pg_catalog.upper(pg_catalog.regexp_replace(
    coalesce(p_code, ''),
    '[^A-Za-z0-9]',
    '',
    'g'
  ));
  if v_code !~ '^[A-Z0-9]{8}$' then
    return 'invalid';
  end if;
  select owner_kind, owner_user_id, owner_venue_id
    into v_owner_kind, v_owner_user, v_owner_venue
  from public.referral_codes
  where code = v_code;
  if v_owner_kind is null then
    return 'invalid';
  end if;
  if p_subject_user is not null and v_owner_user = p_subject_user then
    return 'self';
  end if;
  if p_subject_venue is not null and v_owner_venue = p_subject_venue then
    return 'self';
  end if;

  select attribution_days into v_days
  from public.referral_program_settings
  where id = 1;

  if p_subject_kind = 'player' and v_owner_kind = 'player' then
    v_reason := private.identity_conflict(p_subject_user, v_owner_user, null, null);
  elsif p_subject_kind = 'player' and v_owner_kind = 'venue' then
    v_reason := private.identity_conflict(p_subject_user, null, v_owner_venue, null);
  elsif p_subject_kind = 'venue' and v_owner_kind = 'player' then
    v_reason := private.identity_conflict(v_owner_user, null, p_subject_venue, null);
  else
    v_reason := private.identity_conflict(null, null, p_subject_venue, v_owner_venue);
  end if;

  insert into public.referral_attributions (
    subject_kind, subject_user_id, subject_venue_id,
    referrer_kind, referrer_user_id, referrer_venue_id,
    code, starts_at, ends_at, status, block_reason
  ) values (
    p_subject_kind,
    p_subject_user,
    p_subject_venue,
    v_owner_kind,
    v_owner_user,
    v_owner_venue,
    v_code,
    v_started,
    v_started + make_interval(days => v_days),
    case when v_reason is null then 'active' else 'blocked' end,
    v_reason
  );

  if p_subject_kind = 'venue'
    and v_owner_kind = 'venue'
    and v_reason is null
  then
    perform set_config('scapematch.referral_link', 'on', true);
    update public.venues
    set referred_by = v_owner_venue
    where id = p_subject_venue
      and referred_by is null;
  end if;

  if v_reason is null then
    perform private.flag_same_device_rewards(p_subject_user, p_subject_venue);
    return 'ok';
  end if;
  return 'blocked';
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
begin
  perform private.ensure_player_code(new.id);
  select raw_user_meta_data ->> 'referral_code',
         raw_user_meta_data ->> 'device_install_id'
    into v_code, v_device
  from auth.users
  where id = new.id;
  v_device := private.normalize_install_id(v_device);
  if v_device is not null then
    update public.profiles
    set device_install_id = v_device
    where id = new.id
      and device_install_id is null;
  end if;
  if v_code is not null and pg_catalog.btrim(v_code) <> '' then
    perform private.attach_referral('player', new.id, null, v_code, true);
  end if;
  return new;
end;
$$;

create or replace function private.venue_referral_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.ensure_venue_code(new.id);
  return new;
end;
$$;

drop trigger if exists profile_referral_code on public.profiles;
create trigger profile_referral_code
  after insert on public.profiles
  for each row execute function private.profile_referral_code();

drop trigger if exists venue_referral_code on public.venues;
create trigger venue_referral_code
  after insert on public.venues
  for each row execute function private.venue_referral_code();

create or replace function private.venues_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.asaas_wallet_id := null;
      if new.invite_id is not null then
        select i.badge
          into new.badge
        from public.partner_invites i
        where i.id = new.invite_id
          and i.active;
        if not found then
          raise exception 'unknown invite' using errcode = 'P0002';
        end if;
      else
        new.badge := null;
      end if;
    end if;
    if new.latitude is null or new.longitude is null then
      select c.latitude, c.longitude
        into new.latitude, new.longitude
      from public.cities c
      where c.id = new.city_id;
    end if;
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  if not private.is_admin() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.invite_id := old.invite_id;
    new.asaas_wallet_id := old.asaas_wallet_id;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.venues_guard() from public, anon, authenticated;

do $backfill$
declare
  r record;
  v_days integer;
begin
  select attribution_days into v_days
  from public.referral_program_settings where id = 1;
  for r in select id from public.profiles loop
    perform private.ensure_player_code(r.id);
  end loop;
  for r in select id from public.venues loop
    perform private.ensure_venue_code(r.id);
  end loop;
  insert into public.referral_attributions (
    subject_kind, subject_venue_id, referrer_kind, referrer_venue_id,
    code, starts_at, ends_at, status
  )
  select
    'venue',
    v.id,
    'venue',
    v.referred_by,
    c.code,
    v.created_at,
    v.created_at + make_interval(days => v_days),
    'active'
  from public.venues v
  join public.referral_codes c on c.owner_venue_id = v.referred_by
  where v.referred_by is not null
  on conflict (subject_venue_id) where subject_venue_id is not null do nothing;
end
$backfill$;

create or replace function private.scape_balances(p_user_id uuid)
returns table (pending_points integer, available_points integer)
language sql
stable
security definer
set search_path = ''
as $$
  with entries as (
    select *
    from public.scape_point_entries
    where user_id = p_user_id
  )
  select
    coalesce((
      select sum(a.points)::integer
      from entries a
      where a.kind = 'accrual'
        and a.review_status is distinct from 'em_revisao'
        and a.review_status is distinct from 'rejected'
        and not exists (
          select 1 from entries r
          where r.relates_to = a.id and r.kind = 'release'
        )
        and not exists (
          select 1 from entries r
          where r.relates_to = a.id and r.kind = 'reversal'
        )
    ), 0),
    coalesce((
      select sum(r.points)::integer
      from entries r
      where r.kind = 'release'
    ), 0)
    - coalesce((
      select sum(v.points)::integer
      from entries v
      join entries a on a.id = v.relates_to
      where v.kind = 'reversal'
        and exists (
          select 1 from entries rel
          where rel.relates_to = a.id and rel.kind = 'release'
        )
    ), 0)
    - coalesce((
      select sum(s.points)::integer
      from entries s
      where s.kind = 'redemption'
        and not exists (
          select 1 from entries back
          where back.relates_to = s.id and back.kind = 'redemption_reversal'
        )
    ), 0);
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
  v_max_points integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
begin
  if p_lock then
    perform 1 from public.profiles where id = p_user_id for update;
  end if;
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := coalesce(v_available, 0);
  if v_available < 0 then
    v_available := 0;
  end if;
  v_fee := private.reward_cents(p_gross, p_commission_bps);
  v_house := p_gross - v_fee;
  v_room := case when p_gross > 1 then p_gross - 1 else 0 end;
  v_max_subsidy := least(greatest(v_fee, 0), v_room);
  v_max_points := v_max_subsidy / v_point;
  v_points := greatest(coalesce(p_points, 0), 0);
  v_points := least(v_points, v_available, v_max_points);
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
    'point_value_cents', v_point
  );
end;
$$;

create or replace function private.hold_point_redemption(
  p_user_id uuid,
  p_idempotency_key text,
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
  v_existing public.scape_point_entries%rowtype;
  v_quote jsonb;
  v_points integer;
  v_subsidy integer;
  v_split numeric;
  v_gross integer;
begin
  if p_idempotency_key is null or length(pg_catalog.btrim(p_idempotency_key)) < 8 then
    raise exception 'idempotency ausente' using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  select e.* into v_existing
  from public.scape_point_entries e
  where e.user_id = p_user_id
    and e.client_key = p_idempotency_key
    and e.kind = 'redemption'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    )
  order by e.created_at desc
  limit 1;
  if v_existing.id is not null then
    return pg_catalog.jsonb_build_object(
      'gross_cents', v_existing.gross_cents,
      'charged_cents', v_existing.gross_cents - v_existing.amount_cents,
      'subsidy_cents', v_existing.amount_cents,
      'points', v_existing.points,
      'house_net_cents', null,
      'split_percent', v_existing.split_percent,
      'held', true
    );
  end if;

  v_quote := private.subsidy_quote(
    p_user_id, p_gross, p_commission_bps, p_points, false
  );
  v_points := (v_quote ->> 'points')::integer;
  v_subsidy := (v_quote ->> 'subsidy_cents')::integer;
  if v_points <= 0 or v_subsidy <= 0 then
    return v_quote || pg_catalog.jsonb_build_object('held', false);
  end if;
  v_split := (v_quote ->> 'split_percent')::numeric;
  v_gross := (v_quote ->> 'gross_cents')::integer;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    client_key, gross_cents, split_percent, idempotency_key
  ) values (
    p_user_id,
    'redemption',
    v_points,
    v_subsidy,
    'redeem',
    p_idempotency_key,
    v_gross,
    v_split,
    'redeem:' || p_idempotency_key || ':' || gen_random_uuid()::text
  );
  return v_quote || pg_catalog.jsonb_build_object('held', true);
end;
$$;

create or replace function private.release_point_hold(p_idempotency_key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.scape_point_entries%rowtype;
begin
  select e.* into v_row
  from public.scape_point_entries e
  where e.client_key = p_idempotency_key
    and e.kind = 'redemption'
    and e.payment_charge_id is null
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    )
  order by e.created_at desc
  limit 1
  for update;
  if v_row.id is null then
    return false;
  end if;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    relates_to, client_key, idempotency_key
  ) values (
    v_row.user_id,
    'redemption_reversal',
    v_row.points,
    v_row.amount_cents,
    'redeem',
    v_row.id,
    v_row.client_key,
    'redemption_reversal:' || v_row.id::text
  )
  on conflict (idempotency_key) do nothing;
  return true;
end;
$$;

create or replace function private.attach_point_hold(
  p_idempotency_key text,
  p_charge_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.scape_point_entries
  set
    payment_charge_id = p_charge_id,
    source_charge_id = p_charge_id
  where client_key = p_idempotency_key
    and kind = 'redemption'
    and payment_charge_id is null
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = scape_point_entries.id
        and r.kind = 'redemption_reversal'
    );
end;
$$;

create table public.referral_withholdings (
  id uuid primary key default gen_random_uuid(),
  payment_charge_id uuid not null references public.payment_charges (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reason text not null check (reason in ('payer_is_referrer', 'payer_account_cap')),
  program text not null,
  created_at timestamptz not null default pg_catalog.now(),
  unique (payment_charge_id, reason, program)
);

create index referral_withholdings_by_user
  on public.referral_withholdings (user_id, created_at desc);

alter table public.referral_withholdings enable row level security;

revoke all on table public.referral_withholdings
  from public, anon, authenticated, service_role;

grant select on table public.referral_withholdings to authenticated;

create policy referral_withholdings_select on public.referral_withholdings
  for select to authenticated
  using (user_id = auth.uid() or private.is_admin());

create or replace function private.note_payer_withholding(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id;
  return;
end;
$$;

create or replace function private.post_referral_rewards(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_settings public.referral_program_settings%rowtype;
  v_player public.referral_attributions%rowtype;
  v_venue public.referral_attributions%rowtype;
  v_gross integer;
  v_pool integer;
  v_paid timestamptz;
  v_reason text;
  v_cents integer;
  v_points integer;
  v_value integer;
  v_existing integer;
  v_referrer uuid;
  v_gate text;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  select * into v_settings from public.referral_program_settings where id = 1;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_pool := greatest(
    private.reward_cents(v_gross, v_charge.commission_bps)
      - v_charge.subsidy_cents
      - v_charge.first_booking_discount_cents,
    0
  );
  v_paid := coalesce(v_charge.paid_at, pg_catalog.now());
  v_value := v_settings.point_value_cents;

  -- Cashback fixo de 1%. O sorteio entra só na migration do #85.
  select amount_cents into v_existing
  from public.scape_point_entries
  where source_charge_id = v_charge.id
    and program = 'cashback'
    and kind = 'accrual';
  if found then
    v_pool := greatest(v_pool - v_existing, 0);
  else
    v_cents := least(
      private.reward_cents(v_charge.amount_cents, v_settings.cashback_bps),
      v_pool
    );
    v_points := v_cents / v_value;
    v_cents := v_points * v_value;
    if v_points > 0 then
      insert into public.scape_point_entries (
        user_id, kind, points, amount_cents, program,
        source_charge_id, payment_charge_id, idempotency_key, available_at
      ) values (
        v_charge.user_id, 'accrual', v_points, v_cents, 'cashback',
        v_charge.id, v_charge.id,
        'accrual:' || v_charge.id::text || ':cashback',
        v_paid + make_interval(days => v_settings.hold_days)
      )
      on conflict (idempotency_key) do nothing;
      v_pool := v_pool - v_cents;
    end if;
  end if;

  if private.identity_conflict(v_charge.user_id, null, v_charge.venue_id, null) is not null then
    return;
  end if;

  select * into v_player
  from public.referral_attributions
  where subject_user_id = v_charge.user_id;
  if v_player.id is not null
    and v_player.status = 'active'
    and v_paid >= v_player.starts_at
    and v_paid < v_player.ends_at
  then
    if v_player.referrer_kind = 'player' then
      v_reason := private.identity_conflict(
        v_charge.user_id, v_player.referrer_user_id, null, null
      );
    else
      v_reason := private.identity_conflict(
        v_charge.user_id, null, v_player.referrer_venue_id, null
      );
    end if;
    if v_reason is not null then
      update public.referral_attributions
      set status = 'blocked', block_reason = v_reason
      where id = v_player.id;
    elsif v_player.referrer_kind = 'venue' then
      if v_player.referrer_venue_id is distinct from v_charge.venue_id
        and exists (
          select 1 from public.profiles p
          where p.id = v_charge.user_id and p.cpf is not null
        )
      then
        select amount_cents into v_existing
        from public.venue_referral_entries
        where source_charge_id = v_charge.id
          and program = 'b2c'
          and kind = 'accrual';
        if found then
          v_pool := greatest(v_pool - v_existing, 0);
        else
          v_gate := private.referral_reward_gate(
            v_charge.id, 'b2c', null, v_player.referrer_venue_id,
            v_charge.user_id, null
          );
          v_cents := least(private.reward_cents(v_gross, v_settings.b2c_bps), v_pool);
          if v_gate is distinct from 'skip' and v_cents > 0 then
            insert into public.venue_referral_entries (
              venue_id, kind, amount_cents, program, source_charge_id,
              payment_charge_id, idempotency_key, review_status
            ) values (
              v_player.referrer_venue_id, 'accrual', v_cents, 'b2c',
              v_charge.id, v_charge.id,
              'accrual:' || v_charge.id::text || ':b2c',
              nullif(v_gate, 'post')
            )
            on conflict (idempotency_key) do nothing;
            perform private.note_payer_reward_subject(
              v_charge.id, v_charge.user_id, null
            );
            v_pool := v_pool - v_cents;
          end if;
        end if;
      end if;
    else
      if exists (
        select 1 from public.profiles p
        where p.id = v_charge.user_id and p.cpf is not null
      ) and exists (
        select 1 from public.profiles p
        where p.id = v_player.referrer_user_id and p.cpf is not null
      ) then
        select amount_cents into v_existing
        from public.scape_point_entries
        where source_charge_id = v_charge.id
          and program = 'c2c'
          and kind = 'accrual';
        if found then
          v_pool := greatest(v_pool - v_existing, 0);
        else
          v_gate := private.referral_reward_gate(
            v_charge.id, 'c2c', v_player.referrer_user_id, null,
            v_charge.user_id, null
          );
          v_cents := least(private.reward_cents(v_gross, v_settings.c2c_bps), v_pool);
          v_points := v_cents / v_value;
          v_cents := v_points * v_value;
          if v_gate is distinct from 'skip' and v_points > 0 then
            insert into public.scape_point_entries (
              user_id, kind, points, amount_cents, program,
              source_charge_id, payment_charge_id, idempotency_key, available_at,
              review_status
            ) values (
              v_player.referrer_user_id, 'accrual', v_points, v_cents, 'c2c',
              v_charge.id, v_charge.id,
              'accrual:' || v_charge.id::text || ':c2c',
              v_paid + make_interval(days => v_settings.hold_days),
              nullif(v_gate, 'post')
            )
            on conflict (idempotency_key) do nothing;
            perform private.note_payer_reward_subject(
              v_charge.id, v_charge.user_id, null
            );
            v_pool := v_pool - v_cents;
          end if;
        end if;
      end if;
    end if;
  end if;

  select * into v_venue
  from public.referral_attributions
  where subject_venue_id = v_charge.venue_id;
  if v_venue.id is null
    or v_venue.status <> 'active'
    or v_paid < v_venue.starts_at
    or v_paid >= v_venue.ends_at
  then
    return;
  end if;

  if v_venue.referrer_kind = 'player' then
    v_reason := private.identity_conflict(
      v_venue.referrer_user_id, null, v_charge.venue_id, null
    );
    v_referrer := v_venue.referrer_user_id;
  else
    v_reason := private.identity_conflict(
      null, null, v_charge.venue_id, v_venue.referrer_venue_id
    );
    v_referrer := null;
  end if;
  if v_reason is not null then
    update public.referral_attributions
    set status = 'blocked', block_reason = v_reason
    where id = v_venue.id;
    return;
  end if;

  if v_venue.referrer_kind = 'player' then
    if not exists (
      select 1 from public.profiles p
      where p.id = v_referrer and p.cpf is not null
    ) then
      return;
    end if;
    select amount_cents into v_existing
    from public.scape_point_entries
    where source_charge_id = v_charge.id
      and program = 'c2b'
      and kind = 'accrual';
    if found then
      return;
    end if;
    v_gate := private.referral_reward_gate(
      v_charge.id, 'c2b', v_referrer, null, null, v_charge.venue_id
    );
    v_cents := least(private.reward_cents(v_gross, v_settings.c2b_bps), v_pool);
    v_points := v_cents / v_value;
    v_cents := v_points * v_value;
    if v_gate = 'skip' or v_points <= 0 then
      return;
    end if;
    insert into public.scape_point_entries (
      user_id, kind, points, amount_cents, program,
      source_charge_id, payment_charge_id, idempotency_key, available_at,
      review_status
    ) values (
      v_referrer, 'accrual', v_points, v_cents, 'c2b',
      v_charge.id, v_charge.id,
      'accrual:' || v_charge.id::text || ':c2b',
      v_paid + make_interval(days => v_settings.hold_days),
      nullif(v_gate, 'post')
    )
    on conflict (idempotency_key) do nothing;
    perform private.note_payer_reward_subject(v_charge.id, null, v_charge.venue_id);
    return;
  end if;

  if v_charge.first_booking_discount_cents > 0 then
    return;
  end if;
  select amount_cents into v_existing
  from public.venue_referral_entries
  where source_charge_id = v_charge.id
    and program = 'b2b'
    and kind = 'accrual';
  if found then
    return;
  end if;
  v_gate := private.referral_reward_gate(
    v_charge.id, 'b2b', null, v_venue.referrer_venue_id, null, v_charge.venue_id
  );
  v_cents := least(private.reward_cents(v_gross, v_settings.b2b_bps), v_pool);
  if v_gate = 'skip' or v_cents <= 0 then
    return;
  end if;
  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, source_charge_id,
    payment_charge_id, idempotency_key, review_status
  ) values (
    v_venue.referrer_venue_id, 'accrual', v_cents, 'b2b',
    v_charge.id, v_charge.id,
    'accrual:' || v_charge.id::text || ':b2b',
    nullif(v_gate, 'post')
  )
  on conflict (idempotency_key) do nothing;
  perform private.note_payer_reward_subject(v_charge.id, null, v_charge.venue_id);
end;
$$;

create or replace function private.reverse_referral_rewards(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, idempotency_key
  )
  select
    e.user_id,
    'reversal',
    e.points,
    e.amount_cents,
    e.program,
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    'reversal:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, idempotency_key
  )
  select
    e.venue_id,
    'reversal',
    e.amount_cents,
    e.program,
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    'reversal:' || e.id::text
  from public.venue_referral_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  update public.venue_referral_entries e
  set settlement = 'reversed'
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and e.settlement in ('pending', 'released')
    and e.applied_cents = 0
    and exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  insert into public.venue_credit_clawbacks (venue_id, entry_id, amount_cents)
  select e.venue_id, e.id, e.applied_cents
  from public.venue_referral_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and e.applied_cents > 0
    and not exists (
      select 1 from public.venue_credit_applications a
      where a.entry_id = e.id and a.reversed_at is not null
    )
    and exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and not exists (
      select 1 from public.venue_credit_clawbacks c
      where c.entry_id = e.id and c.voided_at is null
    );

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, client_key, idempotency_key
  )
  select
    e.user_id,
    'redemption_reversal',
    e.points,
    e.amount_cents,
    'redeem',
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    e.client_key,
    'redemption_reversal:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'redemption'
    and (
      e.payment_charge_id = p_charge_id
      or e.source_charge_id = p_charge_id
    )
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    );
end;
$$;

create or replace function private.release_due_scape_points(
  p_now timestamptz default pg_catalog.now()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_released integer := 0;
  v_holds integer := 0;
begin
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, idempotency_key
  )
  select
    e.user_id, 'release', e.points, e.amount_cents, e.program,
    e.source_charge_id, e.payment_charge_id, e.id,
    'release:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'accrual'
    and e.available_at <= p_now
    and e.review_status is distinct from 'em_revisao'
    and e.review_status is distinct from 'rejected'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind in ('release', 'reversal')
    );
  get diagnostics v_released = row_count;

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    relates_to, client_key, idempotency_key
  )
  select
    e.user_id, 'redemption_reversal', e.points, e.amount_cents, 'redeem',
    e.id, e.client_key, 'redemption_reversal:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'redemption'
    and e.payment_charge_id is null
    and e.created_at <= p_now - interval '30 minutes'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    );
  get diagnostics v_holds = row_count;
  perform private.release_due_venue_credits(p_now);
  return v_released + v_holds;
end;
$$;

create or replace function private.scape_points_on_charge_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.reverse_referral_rewards(old.id);
  return old;
end;
$$;

drop trigger if exists scape_points_on_charge_delete on public.payment_charges;
create trigger scape_points_on_charge_delete
  before delete on public.payment_charges
  for each row execute function private.scape_points_on_charge_delete();

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
  v_fee := v_fee_gross - v_charge.subsidy_cents;
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

  perform private.sync_charge_member(v_charge);
  return pg_catalog.jsonb_build_object(
    'applied', v_applied,
    'status', v_charge.status,
    'paid_at', v_charge.paid_at,
    'refunded_at', v_charge.refunded_at
  );
end;
$$;

drop function if exists public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer);
drop function if exists private.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer);
drop function if exists public.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer);
drop function if exists private.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer);

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

create or replace function private.reserve_pix_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_gross_amount_cents integer default null,
  p_subsidy_cents integer default 0,
  p_points_redeemed integer default 0,
  p_split_percent numeric default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.reserve_with_subsidy(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps, 'PIX',
    p_gross_amount_cents, p_subsidy_cents, p_points_redeemed, p_split_percent
  );
$$;

create or replace function private.reserve_card_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_gross_amount_cents integer default null,
  p_subsidy_cents integer default 0,
  p_points_redeemed integer default 0,
  p_split_percent numeric default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.reserve_with_subsidy(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps, 'CREDIT_CARD',
    p_gross_amount_cents, p_subsidy_cents, p_points_redeemed, p_split_percent
  );
$$;

create or replace function public.reserve_pix_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_gross_amount_cents integer default null,
  p_subsidy_cents integer default 0,
  p_points_redeemed integer default 0,
  p_split_percent numeric default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.reserve_pix_charge(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps,
    p_gross_amount_cents, p_subsidy_cents, p_points_redeemed, p_split_percent
  );
$$;

create or replace function public.reserve_card_charge(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_amount_cents integer,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_gross_amount_cents integer default null,
  p_subsidy_cents integer default 0,
  p_points_redeemed integer default 0,
  p_split_percent numeric default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.reserve_card_charge(
    p_group_id, p_user_id, p_venue_id, p_amount_cents,
    p_idempotency_key, p_wallet_id, p_commission_bps,
    p_gross_amount_cents, p_subsidy_cents, p_points_redeemed, p_split_percent
  );
$$;

create or replace function public.hold_point_redemption(
  p_user_id uuid,
  p_idempotency_key text,
  p_gross integer,
  p_commission_bps integer,
  p_points integer
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.hold_point_redemption(
    p_user_id, p_idempotency_key, p_gross, p_commission_bps, p_points
  );
$$;

create or replace function public.release_point_hold(p_idempotency_key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.release_point_hold(p_idempotency_key);
$$;

create or replace function public.release_due_scape_points()
returns integer
language sql
security invoker
set search_path = ''
as $$
  select private.release_due_scape_points(pg_catalog.now());
$$;

create or replace function public.claim_referral_code(p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  return private.attach_referral('player', auth.uid(), null, p_code, true);
end;
$$;

create or replace function public.claim_venue_referral(
  p_venue_id uuid,
  p_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.venues
    where id = p_venue_id and owner_id = auth.uid()
  ) and not private.is_admin() then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return private.attach_referral('venue', null, p_venue_id, p_code, true);
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
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if v_group.id is null then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  v_bps := public.commission_bps_for_venue(v_group.venue_id);
  return private.subsidy_quote(
    auth.uid(), v_group.price_cents, v_bps, p_points, false
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
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances(v_uid);
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select created_at into v_created from public.profiles where id = v_uid;
  return pg_catalog.jsonb_build_object(
    'referral_code', (
      select code from public.referral_codes where owner_user_id = v_uid
    ),
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'point_value_cents', v_point,
    'attributed', exists (
      select 1 from public.referral_attributions
      where subject_user_id = v_uid
    ),
    'can_claim', v_created >= pg_catalog.now() - interval '24 hours'
      and not exists (
        select 1 from public.referral_attributions
        where subject_user_id = v_uid
      ),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s))
      from (
        select kind, program, points, amount_cents, available_at, created_at, review_status
        from public.scape_point_entries
        where user_id = v_uid
        order by created_at desc
        limit 50
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_scape_liability()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point integer;
  v_unused integer;
  v_pending integer;
  v_available integer;
  v_venue integer;
begin
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select coalesce(sum(
    case kind
      when 'accrual' then points
      when 'reversal' then -points
      when 'redemption' then -points
      when 'redemption_reversal' then points
      else 0
    end
  ), 0)::integer
  into v_unused
  from public.scape_point_entries;
  select coalesce(sum(pending_points), 0)::integer,
         coalesce(sum(available_points), 0)::integer
    into v_pending, v_available
  from (
    select (private.scape_balances(user_id)).*
    from (
      select distinct user_id from public.scape_point_entries
    ) owners
  ) balances;
  select coalesce(sum(
    case kind when 'accrual' then amount_cents else -amount_cents end
  ), 0)::integer
  into v_venue
  from public.venue_referral_entries;
  return pg_catalog.jsonb_build_object(
    'unused_points', v_unused,
    'unused_cents', v_unused * v_point,
    'pending_points', v_pending,
    'available_points', v_available,
    'point_value_cents', v_point,
    'venue_credit_pending_cents', v_venue
  );
end;
$$;

create or replace function public.set_my_phone(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_digits text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_digits := pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if v_digits !~ '^[0-9]{10,13}$' then
    raise exception 'telefone invalido' using errcode = '22023';
  end if;
  update public.profiles
  set phone = v_digits
  where id = auth.uid()
    and phone is null;
  return found;
end;
$$;

revoke all on function private.reward_cents(integer, integer) from public, anon, authenticated;
revoke all on function private.ensure_player_code(uuid) from public, anon, authenticated;
revoke all on function private.ensure_venue_code(uuid) from public, anon, authenticated;
revoke all on function private.identity_conflict(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.attach_referral(text, uuid, uuid, text, boolean) from public, anon, authenticated;
revoke all on function private.profile_referral_code() from public, anon, authenticated;
revoke all on function private.venue_referral_code() from public, anon, authenticated;
revoke all on function private.scape_balances(uuid) from public, anon, authenticated;
revoke all on function private.subsidy_quote(uuid, integer, integer, integer, boolean) from public, anon, authenticated;
revoke all on function private.hold_point_redemption(uuid, text, integer, integer, integer) from public, anon, authenticated;
revoke all on function private.release_point_hold(text) from public, anon, authenticated;
revoke all on function private.attach_point_hold(text, uuid) from public, anon, authenticated;
revoke all on function private.note_payer_withholding(uuid) from public, anon, authenticated;
revoke all on function private.post_referral_rewards(uuid) from public, anon, authenticated;
revoke all on function private.reverse_referral_rewards(uuid) from public, anon, authenticated;
revoke all on function private.release_due_scape_points(timestamptz) from public, anon, authenticated;
revoke all on function private.scape_points_on_charge_delete() from public, anon, authenticated;
revoke all on function private.reserve_with_subsidy(uuid, uuid, uuid, integer, text, text, integer, text, integer, integer, integer, numeric) from public, anon, authenticated;
revoke all on function private.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) from public, anon, authenticated;
revoke all on function private.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) from public, anon, authenticated;

grant execute on function private.hold_point_redemption(uuid, text, integer, integer, integer) to service_role;
grant execute on function private.release_point_hold(text) to service_role;
grant execute on function private.release_due_scape_points(timestamptz) to service_role;
grant execute on function private.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) to service_role;
grant execute on function private.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) to service_role;

revoke all on function public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) from public, anon, authenticated;
revoke all on function public.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) from public, anon, authenticated;
revoke all on function public.hold_point_redemption(uuid, text, integer, integer, integer) from public, anon, authenticated;
revoke all on function public.release_point_hold(text) from public, anon, authenticated;
revoke all on function public.release_due_scape_points() from public, anon, authenticated;
revoke all on function public.claim_referral_code(text) from public, anon;
revoke all on function public.claim_venue_referral(uuid, text) from public, anon;
revoke all on function public.quote_my_point_subsidy(uuid, integer) from public, anon;
revoke all on function public.my_scape_wallet() from public, anon;
revoke all on function public.admin_scape_liability() from public, anon, authenticated;
revoke all on function public.set_my_phone(text) from public, anon;

grant execute on function public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) to service_role;
grant execute on function public.reserve_card_charge(uuid, uuid, uuid, integer, text, text, integer, integer, integer, integer, numeric) to service_role;
grant execute on function public.hold_point_redemption(uuid, text, integer, integer, integer) to service_role;
grant execute on function public.release_point_hold(text) to service_role;
grant execute on function public.release_due_scape_points() to service_role;
grant execute on function public.claim_referral_code(text) to authenticated;
grant execute on function public.claim_venue_referral(uuid, text) to authenticated;
grant execute on function public.quote_my_point_subsidy(uuid, integer) to authenticated;
grant execute on function public.my_scape_wallet() to authenticated;
grant execute on function public.admin_scape_liability() to authenticated;
grant execute on function public.set_my_phone(text) to authenticated;

alter table public.referral_program_settings enable row level security;
alter table public.referral_codes enable row level security;
alter table public.referral_attributions enable row level security;
alter table public.scape_point_entries enable row level security;
alter table public.venue_referral_entries enable row level security;

revoke all on table public.referral_program_settings from public, anon, authenticated, service_role;
revoke all on table public.referral_codes from public, anon, authenticated, service_role;
revoke all on table public.referral_attributions from public, anon, authenticated, service_role;
revoke all on table public.scape_point_entries from public, anon, authenticated, service_role;
revoke all on table public.venue_referral_entries from public, anon, authenticated, service_role;

grant select on table public.scape_point_entries to authenticated;
grant select on table public.venue_referral_entries to authenticated;
grant select on table public.referral_attributions to authenticated;

drop policy if exists scape_point_select on public.scape_point_entries;
create policy scape_point_select on public.scape_point_entries
  for select to authenticated
  using (user_id = auth.uid() or private.is_admin());

drop policy if exists venue_referral_select on public.venue_referral_entries;
create policy venue_referral_select on public.venue_referral_entries
  for select to authenticated
  using (private.owns_venue(venue_id) or private.is_admin());

drop policy if exists referral_attribution_select on public.referral_attributions;
create policy referral_attribution_select on public.referral_attributions
  for select to authenticated
  using (
    subject_user_id = auth.uid()
    or referrer_user_id = auth.uid()
    or (subject_venue_id is not null and private.owns_venue(subject_venue_id))
    or (referrer_venue_id is not null and private.owns_venue(referrer_venue_id))
    or private.is_admin()
  );

-- Telefone do jogador fica fora do select/update que o app já tinha.
revoke select (phone) on table public.profiles from anon, authenticated;
revoke update (phone) on table public.profiles from anon, authenticated;
