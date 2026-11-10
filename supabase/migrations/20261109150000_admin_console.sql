-- Painel EscapeMatch Admin. Não aplica no projeto remoto por este agente.
-- Não reescreve 20261105210000.
-- Toda leitura e escrita nova passa por RPC SECURITY DEFINER com
-- search_path vazio e private.is_admin(). A taxa já cobrada fica em
-- payment_charges.commission_bps: mudar a casa não mexe nessa coluna.
-- asaas_fee_cents nasce nulo. O painel só mostra a taxa quando o dado existe.

alter table public.venues
  add column if not exists suspended_at timestamptz;

alter table public.venues
  add column if not exists featured_rank integer;

alter table public.venues
  drop constraint if exists venues_featured_rank_nonnegative;

alter table public.venues
  add constraint venues_featured_rank_nonnegative
  check (featured_rank is null or featured_rank >= 0);

alter table public.profiles
  add column if not exists suspended_at timestamptz;

alter table public.rooms
  add column if not exists featured_rank integer;

alter table public.rooms
  drop constraint if exists rooms_featured_rank_nonnegative;

alter table public.rooms
  add constraint rooms_featured_rank_nonnegative
  check (featured_rank is null or featured_rank >= 0);

alter table public.news_items
  add column if not exists carousel_rank integer;

alter table public.news_items
  drop constraint if exists news_carousel_rank_nonnegative;

alter table public.news_items
  add constraint news_carousel_rank_nonnegative
  check (carousel_rank is null or carousel_rank >= 0);

alter table public.payment_charges
  add column if not exists asaas_fee_cents integer;

alter table public.payment_charges
  drop constraint if exists payment_charges_asaas_fee_nonnegative;

alter table public.payment_charges
  add constraint payment_charges_asaas_fee_nonnegative
  check (asaas_fee_cents is null or asaas_fee_cents >= 0);

comment on column public.payment_charges.asaas_fee_cents is
  'Taxa do Asaas em centavos, quando o split informar. Nulo significa que o dado não chegou. O painel não estima.';

comment on column public.venues.featured_rank is
  'Ordem na vitrine. Nulo fica fora do destaque. Menor número vem antes.';

comment on column public.news_items.carousel_rank is
  'Ordem no carrossel da home do jogador. Nulo não entra na seleção.';

grant select (featured_rank, suspended_at)
  on table public.venues to anon, authenticated;

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id),
  action text not null check (char_length(action) between 1 and 80),
  target_table text not null check (char_length(target_table) between 1 and 80),
  target_id text,
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default pg_catalog.now()
);

create index if not exists admin_audit_log_by_time
  on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;

revoke all on table public.admin_audit_log
  from public, anon, authenticated, service_role;

create table if not exists public.reward_settings_changes (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id),
  before_state jsonb not null,
  after_state jsonb not null,
  created_at timestamptz not null default pg_catalog.now()
);

alter table public.reward_settings_changes enable row level security;

revoke all on table public.reward_settings_changes
  from public, anon, authenticated, service_role;

create or replace function private.admin_require()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

revoke all on function private.admin_require()
  from public, anon, authenticated, service_role;

create or replace function private.admin_audit(
  p_actor uuid,
  p_action text,
  p_table text,
  p_id text,
  p_before jsonb,
  p_after jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.admin_audit_log (
    actor_id, action, target_table, target_id, before_state, after_state
  ) values (
    p_actor, p_action, p_table, p_id, p_before, p_after
  );
end;
$$;

revoke all on function private.admin_audit(uuid, text, text, text, jsonb, jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.admin_like(p_query text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '%' || replace(replace(btrim(coalesce(p_query, '')), '%', ''), '_', '') || '%';
$$;

revoke all on function private.admin_like(text)
  from public, anon, authenticated, service_role;

create or replace function private.venue_is_visible(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and (
        (status = 'approved' and suspended_at is null)
        or owner_id = (select auth.uid())
        or private.is_admin()
      )
  );
$$;

revoke all on function private.venue_is_visible(uuid) from public;
grant execute on function private.venue_is_visible(uuid)
  to anon, authenticated, service_role;

create or replace view public.venues_vitrine
with (security_invoker = true) as
select
  id,
  city_id,
  name,
  neighborhood,
  street_address,
  address_number,
  postal_code,
  latitude,
  longitude,
  category,
  badge,
  status,
  created_at,
  receives_payments,
  featured_rank
from public.venues;

revoke all on table public.venues_vitrine from public, anon, authenticated;
grant select on table public.venues_vitrine to anon, authenticated, service_role;

-- O anon não lê owner_id. A policy dele só olha status e suspensão.
drop policy if exists venues_select_anon on public.venues;
create policy venues_select_anon on public.venues
  for select to anon
  using (status = 'approved' and suspended_at is null);

drop policy if exists venues_select on public.venues;
create policy venues_select on public.venues
  for select to authenticated
  using (
    (status = 'approved' and suspended_at is null)
    or owner_id = (select auth.uid())
    or private.is_admin()
  );

create or replace function private.groups_require_payout_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet text;
  v_status text;
  v_suspended timestamptz;
begin
  if auth.uid() is null then
    return new;
  end if;
  select v.status, v.asaas_wallet_id, v.suspended_at
    into v_status, v_wallet, v_suspended
  from public.venues v
  where v.id = new.venue_id;
  if v_suspended is not null then
    raise exception 'casa suspensa' using errcode = 'P0001';
  end if;
  if v_status = 'approved'
    and v_wallet is not null
    and btrim(v_wallet) <> ''
  then
    return new;
  end if;
  raise exception 'conta de recebimento pendente' using errcode = 'P0001';
end;
$$;

revoke all on function private.groups_require_payout_account()
  from public, anon, authenticated;

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
      new.suspended_at := null;
      new.featured_rank := null;
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
    new.suspended_at := old.suspended_at;
    new.featured_rank := old.featured_rank;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.venues_guard()
  from public, anon, authenticated;

create or replace function private.profiles_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.asaas_customer_id := old.asaas_customer_id;
    if not exists (
      select 1
      from public.admins admin_row
      where admin_row.user_id = auth.uid()
    ) then
      new.suspended_at := old.suspended_at;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.profiles_guard()
  from public, anon, authenticated;

create or replace function private.freeze_room_highlight()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin() then
      new.featured_rank := null;
    end if;
    return new;
  end if;
  if auth.uid() is not null and not private.is_admin() then
    new.featured_rank := old.featured_rank;
  end if;
  return new;
end;
$$;

revoke all on function private.freeze_room_highlight()
  from public, anon, authenticated, service_role;

drop trigger if exists rooms_freeze_highlight on public.rooms;
create trigger rooms_freeze_highlight
  before insert or update on public.rooms
  for each row execute function private.freeze_room_highlight();

create or replace function private.freeze_news_carousel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin() then
      new.carousel_rank := null;
    end if;
    return new;
  end if;
  if auth.uid() is not null and not private.is_admin() then
    new.carousel_rank := old.carousel_rank;
  end if;
  return new;
end;
$$;

revoke all on function private.freeze_news_carousel()
  from public, anon, authenticated, service_role;

drop trigger if exists news_freeze_carousel on public.news_items;
create trigger news_freeze_carousel
  before insert or update on public.news_items
  for each row execute function private.freeze_news_carousel();

create or replace function private.reject_suspended_player()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_row jsonb := pg_catalog.to_jsonb(new);
begin
  v_user := (
    v_row ->> case
      when tg_table_name = 'groups' then 'created_by'
      else 'user_id'
    end
  )::uuid;
  if v_user is not null and exists (
    select 1
    from public.profiles
    where id = v_user
      and suspended_at is not null
  ) then
    raise exception 'conta suspensa' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.reject_suspended_player()
  from public, anon, authenticated, service_role;

drop trigger if exists groups_reject_suspended on public.groups;
create trigger groups_reject_suspended
  before insert on public.groups
  for each row execute function private.reject_suspended_player();

drop trigger if exists members_reject_suspended on public.group_members;
create trigger members_reject_suspended
  before insert on public.group_members
  for each row execute function private.reject_suspended_player();

drop trigger if exists charges_reject_suspended on public.payment_charges;
create trigger charges_reject_suspended
  before insert on public.payment_charges
  for each row execute function private.reject_suspended_player();

create or replace function private.admin_int(
  p_patch jsonb,
  p_key text,
  p_current integer,
  p_min integer,
  p_max integer
)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v_value integer;
begin
  if p_patch is null or not (p_patch ? p_key) then
    return p_current;
  end if;
  if pg_catalog.jsonb_typeof(p_patch -> p_key) <> 'number' then
    raise exception 'campo % invalido', p_key using errcode = '22023';
  end if;
  v_value := (p_patch ->> p_key)::integer;
  if v_value < p_min or v_value > p_max then
    raise exception 'campo % fora da faixa', p_key using errcode = '22023';
  end if;
  return v_value;
end;
$$;

revoke all on function private.admin_int(jsonb, text, integer, integer, integer)
  from public, anon, authenticated, service_role;

create or replace function public.admin_whoami()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return (
    select pg_catalog.jsonb_build_object(
      'user_id', v_uid,
      'email', u.email,
      'display_name', p.display_name
    )
    from auth.users u
    join public.profiles p on p.id = u.id
    where u.id = v_uid
  );
end;
$$;

create or replace function public.admin_list_venues(
  p_status text default null,
  p_query text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_like text := private.admin_like(p_query);
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
begin
  if v_status is not null
    and v_status not in ('pending', 'approved', 'rejected', 'merged', 'suspended')
  then
    raise exception 'status invalido' using errcode = '22023';
  end if;
  return pg_catalog.jsonb_build_object(
    'platform_bps', (select commission_bps from public.platform_settings where id = 1),
    'houses', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.name)
      from (
        select
          v.id,
          v.name,
          v.city_id,
          v.status,
          v.suspended_at is not null as suspended,
          v.asaas_wallet_id is not null as has_wallet,
          coalesce(c.commission_bps, s.commission_bps) as commission_bps,
          c.venue_id is not null as commission_override,
          v.created_at
        from public.venues v
        cross join public.platform_settings s
        left join public.venue_commissions c on c.venue_id = v.id
        where s.id = 1
          and (
            v_status is null
            or (v_status = 'suspended' and v.suspended_at is not null)
            or (v_status <> 'suspended' and v.status = v_status)
          )
          and (
            btrim(coalesce(p_query, '')) = ''
            or v.name ilike v_like
          )
        order by v.name
        limit 200
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_venue(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_house public.venues%rowtype;
  v_platform integer;
  v_rate integer;
  v_override boolean;
begin
  select * into v_house from public.venues where id = p_venue_id;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  select commission_bps into v_platform
  from public.platform_settings where id = 1;
  select c.commission_bps into v_rate
  from public.venue_commissions c where c.venue_id = p_venue_id;
  v_override := v_rate is not null;
  v_rate := coalesce(v_rate, v_platform);
  return pg_catalog.jsonb_build_object(
    'id', v_house.id,
    'name', v_house.name,
    'city_id', v_house.city_id,
    'neighborhood', v_house.neighborhood,
    'street_address', v_house.street_address,
    'address_number', v_house.address_number,
    'postal_code', v_house.postal_code,
    'phone', v_house.phone,
    'category', v_house.category,
    'badge', v_house.badge,
    'status', v_house.status,
    'suspended', v_house.suspended_at is not null,
    'suspended_at', v_house.suspended_at,
    'has_wallet', v_house.asaas_wallet_id is not null,
    'document_kind', v_house.document_kind,
    'document_last4', right(v_house.document_number, 4),
    'owner_id', v_house.owner_id,
    'owner_name', (select display_name from public.profiles where id = v_house.owner_id),
    'owner_email', (select email from auth.users where id = v_house.owner_id),
    'invite_code', (
      select i.code from public.partner_invites i where i.id = v_house.invite_id
    ),
    'platform_bps', v_platform,
    'commission_bps', v_rate,
    'commission_override', v_override,
    'featured_rank', v_house.featured_rank,
    'snapshots', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(c) order by c.created_at desc)
      from (
        select id, commission_bps, status, created_at
        from public.payment_charges
        where venue_id = p_venue_id
        order by created_at desc
        limit 8
      ) c
    ), '[]'::jsonb),
    'rooms', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(r) order by r.name)
      from (
        select id, name, featured_rank
        from public.rooms
        where venue_id = p_venue_id
        order by name
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_review_venue(
  p_venue_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before text;
  v_wallet text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  select status into v_before from public.venues where id = p_venue_id for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v_before <> 'pending' then
    raise exception 'casa nao esta pendente' using errcode = 'P0001';
  end if;
  update public.venues
  set status = p_decision,
      reviewed_by = v_uid,
      reviewed_at = pg_catalog.now()
  where id = p_venue_id;
  select asaas_wallet_id into v_wallet from public.venues where id = p_venue_id;
  perform private.admin_audit(
    v_uid,
    'review_venue',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('status', v_before),
    pg_catalog.jsonb_build_object('status', p_decision)
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'status', p_decision,
    'needs_subaccount', p_decision = 'approved'
      and (v_wallet is null or btrim(v_wallet) = '')
  );
end;
$$;

create or replace function public.admin_suspend_venue(
  p_venue_id uuid,
  p_suspended boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before timestamptz;
  v_status text;
  v_after timestamptz;
begin
  if p_suspended is null then
    raise exception 'suspensao invalida' using errcode = '22023';
  end if;
  select status, suspended_at into v_status, v_before
  from public.venues where id = p_venue_id for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if p_suspended and v_status <> 'approved' then
    raise exception 'so casa aprovada suspende' using errcode = 'P0001';
  end if;
  v_after := case when p_suspended then pg_catalog.now() else null end;
  update public.venues
  set suspended_at = v_after
  where id = p_venue_id;
  perform private.admin_audit(
    v_uid, 'suspend_venue', 'venues', p_venue_id::text,
    pg_catalog.jsonb_build_object('suspended_at', v_before),
    pg_catalog.jsonb_build_object('suspended_at', v_after)
  );
  return pg_catalog.jsonb_build_object('venue_id', p_venue_id, 'suspended', p_suspended);
end;
$$;

create or replace function public.admin_update_venue(
  p_venue_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_house public.venues%rowtype;
  v_before jsonb;
  v_key text;
  v_name text;
  v_neighborhood text;
  v_street text;
  v_number text;
  v_postal text;
  v_phone text;
  v_category text;
  v_badge text;
  v_city text;
begin
  if p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object' then
    raise exception 'patch invalido' using errcode = '22023';
  end if;
  for v_key in select pg_catalog.jsonb_object_keys(p_patch)
  loop
    if v_key not in (
      'name', 'neighborhood', 'street_address', 'address_number',
      'postal_code', 'phone', 'category', 'badge', 'city_id'
    ) then
      raise exception 'campo % nao editavel', v_key using errcode = '22023';
    end if;
  end loop;
  select * into v_house from public.venues where id = p_venue_id for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  v_before := pg_catalog.jsonb_build_object(
    'name', v_house.name,
    'neighborhood', v_house.neighborhood,
    'street_address', v_house.street_address,
    'address_number', v_house.address_number,
    'postal_code', v_house.postal_code,
    'phone', v_house.phone,
    'category', v_house.category,
    'badge', v_house.badge,
    'city_id', v_house.city_id
  );
  v_name := coalesce(p_patch ->> 'name', v_house.name);
  v_neighborhood := coalesce(p_patch ->> 'neighborhood', v_house.neighborhood);
  v_street := case
    when p_patch ? 'street_address'
      then btrim(coalesce(p_patch ->> 'street_address', ''))
    else v_house.street_address
  end;
  v_number := case
    when p_patch ? 'address_number'
      then btrim(coalesce(p_patch ->> 'address_number', ''))
    else v_house.address_number
  end;
  v_postal := coalesce(p_patch ->> 'postal_code', v_house.postal_code);
  v_phone := coalesce(p_patch ->> 'phone', v_house.phone);
  v_category := coalesce(p_patch ->> 'category', v_house.category);
  v_badge := case
    when p_patch ? 'badge' then nullif(btrim(p_patch ->> 'badge'), '')
    else v_house.badge
  end;
  v_city := coalesce(p_patch ->> 'city_id', v_house.city_id);
  if char_length(btrim(v_name)) not between 2 and 80
    or char_length(btrim(v_neighborhood)) not between 2 and 80
    or (
      p_patch ? 'street_address'
      and char_length(v_street) not between 2 and 200
    )
    or (
      p_patch ? 'address_number'
      and char_length(v_number) not between 1 and 30
    )
    or v_postal !~ '^[0-9]{8}$'
    or v_phone !~ '^[0-9]{10,13}$'
    or v_category not in ('escape-room', 'rpg', 'board-game', 'laser-tag', 'immersive')
    or not exists (select 1 from public.cities where id = v_city)
  then
    raise exception 'dados da casa invalidos' using errcode = '22023';
  end if;
  update public.venues
  set name = btrim(v_name),
      neighborhood = btrim(v_neighborhood),
      street_address = v_street,
      address_number = v_number,
      postal_code = v_postal,
      phone = v_phone,
      category = v_category,
      badge = v_badge,
      city_id = v_city
  where id = p_venue_id;
  perform private.admin_audit(
    v_uid, 'update_venue', 'venues', p_venue_id::text, v_before, p_patch
  );
  return public.admin_venue(p_venue_id);
end;
$$;

create or replace function public.admin_set_commission(
  p_venue_id uuid,
  p_commission_bps integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before integer;
begin
  if p_commission_bps is null
    or p_commission_bps < 0
    or p_commission_bps > 3000
  then
    raise exception 'A comissão fica entre 0%% e 30%%.'
      using errcode = '22023';
  end if;
  if p_venue_id is null then
    select commission_bps into v_before
    from public.platform_settings where id = 1;
    perform result.commission_bps
    from public.set_platform_commission(p_commission_bps) as result;
  else
    select coalesce(
      (select commission_bps from public.venue_commissions where venue_id = p_venue_id),
      (select commission_bps from public.platform_settings where id = 1)
    ) into v_before;
    perform result.commission_bps
    from public.set_venue_commission(p_venue_id, p_commission_bps) as result;
  end if;
  perform private.admin_audit(
    v_uid,
    'set_commission',
    'commission',
    coalesce(p_venue_id::text, 'platform'),
    pg_catalog.jsonb_build_object('commission_bps', v_before),
    pg_catalog.jsonb_build_object('commission_bps', p_commission_bps)
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'before_bps', v_before,
    'commission_bps', p_commission_bps
  );
end;
$$;

create or replace function public.admin_list_players(p_query text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
begin
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at desc)
    from (
      select
        p.id,
        p.display_name,
        u.email,
        p.suspended_at is not null as suspended,
        p.created_at
      from public.profiles p
      join auth.users u on u.id = p.id
      where v_blank
        or p.display_name ilike v_like
        or coalesce(u.email, '') ilike v_like
        or coalesce(p.username, '') ilike v_like
      order by p.created_at desc
      limit 40
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_player(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_profile public.profiles%rowtype;
  v_email text;
  v_pending integer := 0;
  v_available integer := 0;
  v_point integer;
begin
  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception 'jogador nao encontrado' using errcode = 'P0002';
  end if;
  select email into v_email from auth.users where id = p_user_id;
  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances(p_user_id);
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  return pg_catalog.jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'email', v_email,
    'phone', v_profile.phone,
    'username', v_profile.username,
    'has_cpf', v_profile.cpf is not null,
    'created_at', v_profile.created_at,
    'suspended', v_profile.suspended_at is not null,
    'suspended_at', v_profile.suspended_at,
    'referral_code', (
      select code from public.referral_codes where owner_user_id = p_user_id
    ),
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'point_value_cents', v_point,
    'open_points_cents', coalesce(v_available, 0) * coalesce(v_point, 1),
    'tier', private.referrer_tier_name(p_user_id),
    'tier_bonus_bps', private.referrer_tier_bonus(p_user_id),
    'active_referrals', private.referrer_active_count(p_user_id),
    'referred_by', (
      select pg_catalog.jsonb_build_object(
        'referrer_kind', a.referrer_kind,
        'referrer_user_id', a.referrer_user_id,
        'referrer_venue_id', a.referrer_venue_id,
        'status', a.status,
        'code', a.code
      )
      from public.referral_attributions a
      where a.subject_user_id = p_user_id
      order by a.created_at desc
      limit 1
    ),
    'referrals_made', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(a) order by a.created_at desc)
      from (
        select subject_kind, subject_user_id, subject_venue_id, status, created_at
        from public.referral_attributions
        where referrer_user_id = p_user_id
        order by created_at desc
        limit 30
      ) a
    ), '[]'::jsonb),
    'reservations', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(r) order by r.starts_at desc)
      from (
        select
          g.id as group_id,
          r.name as room_name,
          v.name as venue_name,
          g.starts_at,
          m.attendance,
          m.payment_status
        from public.group_members m
        join public.groups g on g.id = m.group_id
        join public.rooms r on r.id = g.room_id
        join public.venues v on v.id = g.venue_id
        where m.user_id = p_user_id
        order by g.starts_at desc
        limit 30
      ) r
    ), '[]'::jsonb),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(e) order by e.created_at desc)
      from (
        select kind, program, points, amount_cents, review_status, created_at
        from public.scape_point_entries
        where user_id = p_user_id
        order by created_at desc
        limit 40
      ) e
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_suspend_player(
  p_user_id uuid,
  p_suspended boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before timestamptz;
  v_after timestamptz;
begin
  if p_suspended is null then
    raise exception 'suspensao invalida' using errcode = '22023';
  end if;
  if p_user_id = v_uid and p_suspended then
    raise exception 'o admin nao suspende a propria conta' using errcode = 'P0001';
  end if;
  select suspended_at into v_before
  from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'jogador nao encontrado' using errcode = 'P0002';
  end if;
  v_after := case when p_suspended then pg_catalog.now() else null end;
  update public.profiles set suspended_at = v_after where id = p_user_id;
  perform private.admin_audit(
    v_uid, 'suspend_player', 'profiles', p_user_id::text,
    pg_catalog.jsonb_build_object('suspended_at', v_before),
    pg_catalog.jsonb_build_object('suspended_at', v_after)
  );
  return pg_catalog.jsonb_build_object('user_id', p_user_id, 'suspended', p_suspended);
end;
$$;

create or replace function public.admin_referral_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(g) order by g.since)
    from (
      select
        case
          when i.subject_user_id is not null then 'player'
          else 'venue'
        end as subject_kind,
        i.subject_user_id,
        i.subject_venue_id,
        coalesce(p.display_name, v.name, 'Conta') as label,
        count(*)::integer as entry_count,
        coalesce(sum(i.amount_cents), 0)::integer as amount_cents,
        min(i.created_at) as since
      from (
        select
          e.amount_cents,
          e.created_at,
          case
            when e.program = 'c2b' then null
            else coalesce(c.user_id, e.user_id)
          end as subject_user_id,
          case
            when e.program = 'c2b' then c.venue_id
            else null
          end as subject_venue_id
        from public.scape_point_entries e
        left join public.payment_charges c on c.id = e.source_charge_id
        where e.kind = 'accrual' and e.review_status = 'em_revisao'
        union all
        select
          e.amount_cents,
          e.created_at,
          case when e.program = 'b2c' then c.user_id else null end,
          case
            when e.program = 'b2b' then coalesce(c.venue_id, e.venue_id)
            when e.program = 'b2c' then null
            else e.venue_id
          end
        from public.venue_referral_entries e
        left join public.payment_charges c on c.id = e.source_charge_id
        where e.kind = 'accrual' and e.review_status = 'em_revisao'
      ) i
      left join public.profiles p on p.id = i.subject_user_id
      left join public.venues v on v.id = i.subject_venue_id
      group by i.subject_user_id, i.subject_venue_id, p.display_name, v.name
    ) g
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_decide_referral_account(
  p_subject_user_id uuid,
  p_subject_venue_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_row record;
  v_count integer := 0;
begin
  if p_decision not in ('approve', 'reject') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  if p_subject_user_id is null and p_subject_venue_id is null then
    raise exception 'conta ausente' using errcode = '22023';
  end if;
  if p_subject_user_id is not null and p_subject_venue_id is not null then
    raise exception 'conta ambigua' using errcode = '22023';
  end if;
  for v_row in
    select e.id, 'points'::text as entry_kind
    from public.scape_point_entries e
    left join public.payment_charges c on c.id = e.source_charge_id
    where e.kind = 'accrual'
      and e.review_status = 'em_revisao'
      and (
        (
          p_subject_user_id is not null
          and e.program is distinct from 'c2b'
          and coalesce(c.user_id, e.user_id) = p_subject_user_id
        )
        or (
          p_subject_venue_id is not null
          and e.program = 'c2b'
          and c.venue_id = p_subject_venue_id
        )
      )
    union all
    select e.id, 'venue'::text
    from public.venue_referral_entries e
    left join public.payment_charges c on c.id = e.source_charge_id
    where e.kind = 'accrual'
      and e.review_status = 'em_revisao'
      and (
        (
          p_subject_user_id is not null
          and e.program = 'b2c'
          and c.user_id = p_subject_user_id
        )
        or (
          p_subject_venue_id is not null
          and (
            (e.program = 'b2b' and coalesce(c.venue_id, e.venue_id) = p_subject_venue_id)
            or (e.program not in ('b2c', 'b2b') and e.venue_id = p_subject_venue_id)
          )
        )
      )
  loop
    perform public.admin_decide_referral_review(
      v_row.id, v_row.entry_kind, p_decision
    );
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'revisao nao encontrada' using errcode = 'P0002';
  end if;
  perform private.admin_audit(
    v_uid,
    'decide_referral_account',
    'referral_review',
    coalesce(p_subject_user_id, p_subject_venue_id)::text,
    pg_catalog.jsonb_build_object('entries', v_count),
    pg_catalog.jsonb_build_object('decision', p_decision, 'entries', v_count)
  );
  return pg_catalog.jsonb_build_object(
    'decision', p_decision,
    'entries', v_count
  );
end;
$$;

create or replace function public.admin_reward_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return (
    select pg_catalog.to_jsonb(s) - 'id'
    from public.referral_program_settings s
    where s.id = 1
  );
end;
$$;

create or replace function public.admin_save_reward_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_row public.referral_program_settings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_key text;
  v_item jsonb;
  v_bps integer;
  v_weight integer;
  v_weights integer := 0;
  v_ev numeric := 0;
  v_dist_msg text := 'A distribuição de cashback não vale: cada faixa tem de ficar entre o mínimo e o máximo, o peso tem de ser um inteiro maior que zero, e a média ponderada não pode passar do teto.';
begin
  if p_patch is null
    or pg_catalog.jsonb_typeof(p_patch) <> 'object'
    or p_patch = '{}'::jsonb
  then
    raise exception 'patch invalido' using errcode = '22023';
  end if;
  for v_key in select pg_catalog.jsonb_object_keys(p_patch)
  loop
    if v_key not in (
      'c2c_bps', 'b2c_bps', 'c2b_bps', 'b2b_bps',
      'point_value_cents', 'attribution_days', 'hold_days',
      'cashback_bps', 'first_booking_discount_bps',
      'redeem_min_points', 'redeem_max_bps', 'welcome_points',
      'cashback_min_bps', 'cashback_max_bps', 'cashback_ev_cap_bps',
      'cashback_distribution', 'empty_slot_house_share_bps',
      'tier_silver_active', 'tier_silver_bonus_bps',
      'tier_gold_active', 'tier_gold_bonus_bps', 'tier_active_days',
      'block_self_payer', 'payer_referred_account_cap',
      'same_device_review_threshold'
    ) then
      raise exception 'campo % nao editavel', v_key using errcode = '22023';
    end if;
  end loop;
  select * into v_row
  from public.referral_program_settings
  where id = 1
  for update;
  v_before := pg_catalog.to_jsonb(v_row);
  v_row.c2c_bps := private.admin_int(p_patch, 'c2c_bps', v_row.c2c_bps, 0, 10000);
  v_row.b2c_bps := private.admin_int(p_patch, 'b2c_bps', v_row.b2c_bps, 0, 10000);
  v_row.c2b_bps := private.admin_int(p_patch, 'c2b_bps', v_row.c2b_bps, 0, 10000);
  v_row.b2b_bps := private.admin_int(p_patch, 'b2b_bps', v_row.b2b_bps, 0, 10000);
  v_row.point_value_cents := private.admin_int(
    p_patch, 'point_value_cents', v_row.point_value_cents, 1, 100
  );
  v_row.attribution_days := private.admin_int(
    p_patch, 'attribution_days', v_row.attribution_days, 1, 3650
  );
  v_row.hold_days := private.admin_int(p_patch, 'hold_days', v_row.hold_days, 0, 3650);
  v_row.cashback_bps := private.admin_int(
    p_patch, 'cashback_bps', v_row.cashback_bps, 0, 10000
  );
  v_row.first_booking_discount_bps := private.admin_int(
    p_patch, 'first_booking_discount_bps', v_row.first_booking_discount_bps, 0, 10000
  );
  v_row.redeem_min_points := private.admin_int(
    p_patch, 'redeem_min_points', v_row.redeem_min_points, 0, 100000000
  );
  v_row.redeem_max_bps := private.admin_int(
    p_patch, 'redeem_max_bps', v_row.redeem_max_bps, 0, 10000
  );
  v_row.welcome_points := private.admin_int(
    p_patch, 'welcome_points', v_row.welcome_points, 0, 100000000
  );
  v_row.cashback_min_bps := private.admin_int(
    p_patch, 'cashback_min_bps', v_row.cashback_min_bps, 0, 10000
  );
  v_row.cashback_max_bps := private.admin_int(
    p_patch, 'cashback_max_bps', v_row.cashback_max_bps, 0, 10000
  );
  v_row.cashback_ev_cap_bps := private.admin_int(
    p_patch, 'cashback_ev_cap_bps', v_row.cashback_ev_cap_bps, 0, 10000
  );
  v_row.empty_slot_house_share_bps := private.admin_int(
    p_patch, 'empty_slot_house_share_bps', v_row.empty_slot_house_share_bps, 0, 10000
  );
  v_row.tier_silver_active := private.admin_int(
    p_patch, 'tier_silver_active', v_row.tier_silver_active, 0, 1000000
  );
  v_row.tier_silver_bonus_bps := private.admin_int(
    p_patch, 'tier_silver_bonus_bps', v_row.tier_silver_bonus_bps, 0, 10000
  );
  v_row.tier_gold_active := private.admin_int(
    p_patch, 'tier_gold_active', v_row.tier_gold_active, 0, 1000000
  );
  v_row.tier_gold_bonus_bps := private.admin_int(
    p_patch, 'tier_gold_bonus_bps', v_row.tier_gold_bonus_bps, 0, 10000
  );
  v_row.tier_active_days := private.admin_int(
    p_patch, 'tier_active_days', v_row.tier_active_days, 1, 3650
  );
  v_row.payer_referred_account_cap := private.admin_int(
    p_patch, 'payer_referred_account_cap', v_row.payer_referred_account_cap, 0, 1000
  );
  v_row.same_device_review_threshold := private.admin_int(
    p_patch, 'same_device_review_threshold', v_row.same_device_review_threshold, 0, 1000
  );
  if p_patch ? 'block_self_payer' then
    if pg_catalog.jsonb_typeof(p_patch -> 'block_self_payer') <> 'boolean' then
      raise exception 'trava invalida' using errcode = '22023';
    end if;
    v_row.block_self_payer := (p_patch ->> 'block_self_payer')::boolean;
  end if;
  if v_row.cashback_min_bps > v_row.cashback_max_bps then
    raise exception 'faixa de cashback invalida' using errcode = '22023';
  end if;
  if p_patch ? 'cashback_distribution' then
    v_row.cashback_distribution := p_patch -> 'cashback_distribution';
  end if;
  -- O sorteio descarta faixa fora de [mínimo, máximo] e, se a média
  -- passa do teto, volta para o mínimo fixo. O painel não pode gravar
  -- uma configuração que esse sorteio ignoraria.
  v_weights := 0;
  v_ev := 0;
  if pg_catalog.jsonb_typeof(v_row.cashback_distribution) <> 'array'
    or pg_catalog.jsonb_array_length(v_row.cashback_distribution) < 1
  then
    raise exception '%', v_dist_msg using errcode = '22023';
  end if;
  for v_item in
    select value from pg_catalog.jsonb_array_elements(v_row.cashback_distribution)
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
      or (v_item ->> 'bps') is null
      or (v_item ->> 'weight') is null
      or (v_item ->> 'bps') !~ '^[0-9]+$'
      or (v_item ->> 'weight') !~ '^[0-9]+$'
    then
      raise exception '%', v_dist_msg using errcode = '22023';
    end if;
    v_bps := (v_item ->> 'bps')::integer;
    v_weight := (v_item ->> 'weight')::integer;
    if v_weight <= 0
      or v_bps < v_row.cashback_min_bps
      or v_bps > v_row.cashback_max_bps
    then
      raise exception '%', v_dist_msg using errcode = '22023';
    end if;
    v_weights := v_weights + v_weight;
    v_ev := v_ev + (v_bps::numeric * v_weight);
  end loop;
  if v_weights <= 0
    or v_ev / v_weights > v_row.cashback_ev_cap_bps
  then
    raise exception '%', v_dist_msg using errcode = '22023';
  end if;
  update public.referral_program_settings
  set c2c_bps = v_row.c2c_bps,
      b2c_bps = v_row.b2c_bps,
      c2b_bps = v_row.c2b_bps,
      b2b_bps = v_row.b2b_bps,
      point_value_cents = v_row.point_value_cents,
      attribution_days = v_row.attribution_days,
      hold_days = v_row.hold_days,
      cashback_bps = v_row.cashback_bps,
      first_booking_discount_bps = v_row.first_booking_discount_bps,
      redeem_min_points = v_row.redeem_min_points,
      redeem_max_bps = v_row.redeem_max_bps,
      welcome_points = v_row.welcome_points,
      cashback_min_bps = v_row.cashback_min_bps,
      cashback_max_bps = v_row.cashback_max_bps,
      cashback_ev_cap_bps = v_row.cashback_ev_cap_bps,
      cashback_distribution = v_row.cashback_distribution,
      empty_slot_house_share_bps = v_row.empty_slot_house_share_bps,
      tier_silver_active = v_row.tier_silver_active,
      tier_silver_bonus_bps = v_row.tier_silver_bonus_bps,
      tier_gold_active = v_row.tier_gold_active,
      tier_gold_bonus_bps = v_row.tier_gold_bonus_bps,
      tier_active_days = v_row.tier_active_days,
      block_self_payer = v_row.block_self_payer,
      payer_referred_account_cap = v_row.payer_referred_account_cap,
      same_device_review_threshold = v_row.same_device_review_threshold,
      updated_at = pg_catalog.now()
  where id = 1;
  select pg_catalog.to_jsonb(s) into v_after
  from public.referral_program_settings s where s.id = 1;
  insert into public.reward_settings_changes (actor_id, before_state, after_state)
  values (v_uid, v_before, v_after);
  perform private.admin_audit(
    v_uid, 'save_reward_settings', 'referral_program_settings', '1', v_before, v_after
  );
  return v_after - 'id';
end;
$$;

create or replace function public.admin_reward_history()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at desc)
    from (
      select id, actor_id, before_state, after_state, created_at
      from public.reward_settings_changes
      order by created_at desc
      limit 40
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_earnings(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_venue_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_gross bigint := 0;
  v_redeemed bigint := 0;
  v_cashback bigint := 0;
  v_cashback_platform bigint := 0;
  v_fee bigint := 0;
  v_fee_rows integer := 0;
  v_liability jsonb;
begin
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;
  select coalesce(sum(
    case
      when account = 'platform' and kind = 'commission' and direction = 'credit'
        then amount_cents
      when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
        then -amount_cents
      else 0
    end
  ), 0)::bigint
  into v_gross
  from public.ledger_entries
  where (p_from is null or created_at >= p_from)
    and (p_to is null or created_at < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  select coalesce(sum(subsidy_cents), 0)::bigint
  into v_redeemed
  from public.payment_charges
  where status = 'paid'
    and (p_from is null or coalesce(paid_at, created_at) >= p_from)
    and (p_to is null or coalesce(paid_at, created_at) < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  select coalesce(sum(e.amount_cents), 0)::bigint
  into v_cashback
  from public.scape_point_entries e
  left join public.payment_charges c on c.id = e.source_charge_id
  where e.kind = 'accrual'
    and e.program = 'cashback'
    and e.review_status is distinct from 'rejected'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id);

  select coalesce(sum(d.platform_cents), 0)::bigint
  into v_cashback_platform
  from public.cashback_draws d
  left join public.payment_charges c on c.id = d.payment_charge_id
  where (p_from is null or d.created_at >= p_from)
    and (p_to is null or d.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id);

  select
    count(*) filter (where asaas_fee_cents is not null)::integer,
    coalesce(sum(asaas_fee_cents) filter (where asaas_fee_cents is not null), 0)::bigint
  into v_fee_rows, v_fee
  from public.payment_charges
  where (p_from is null or coalesce(paid_at, created_at) >= p_from)
    and (p_to is null or coalesce(paid_at, created_at) < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  v_liability := public.admin_scape_liability();

  return pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'venue_id', p_venue_id,
    'gross_commission_cents', v_gross,
    'rewards_redeemed_cents', v_redeemed,
    'cashback_issued_cents', v_cashback,
    'cashback_platform_cents', v_cashback_platform,
    'open_points', coalesce((v_liability ->> 'available_points')::integer, 0),
    'open_points_cents', coalesce((v_liability ->> 'available_points')::integer, 0)
      * coalesce((v_liability ->> 'point_value_cents')::integer, 1),
    'pending_points', coalesce((v_liability ->> 'pending_points')::integer, 0),
    'asaas_fee_cents', case when v_fee_rows = 0 then null else v_fee end,
    'asaas_fee_rows', v_fee_rows,
    'by_venue', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.name)
      from (
        select
          v.id as venue_id,
          v.name,
          coalesce(c.gross_cents, 0) as gross_commission_cents,
          coalesce(r.redeemed_cents, 0) as rewards_redeemed_cents,
          coalesce(k.cashback_cents, 0) as cashback_issued_cents,
          coalesce(d.debt_cents, 0) as open_debt_cents
        from public.venues v
        left join (
          select venue_id, sum(
            case
              when account = 'platform' and kind = 'commission' and direction = 'credit'
                then amount_cents
              when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
                then -amount_cents
              else 0
            end
          )::bigint as gross_cents
          from public.ledger_entries
          where (p_from is null or created_at >= p_from)
            and (p_to is null or created_at < p_to)
          group by venue_id
        ) c on c.venue_id = v.id
        left join (
          select venue_id, sum(subsidy_cents)::bigint as redeemed_cents
          from public.payment_charges
          where status = 'paid'
            and (p_from is null or coalesce(paid_at, created_at) >= p_from)
            and (p_to is null or coalesce(paid_at, created_at) < p_to)
          group by venue_id
        ) r on r.venue_id = v.id
        left join (
          select ch.venue_id, sum(e.amount_cents)::bigint as cashback_cents
          from public.scape_point_entries e
          join public.payment_charges ch on ch.id = e.source_charge_id
          where e.kind = 'accrual'
            and e.program = 'cashback'
            and e.review_status is distinct from 'rejected'
            and not exists (
              select 1 from public.scape_point_entries rev
              where rev.relates_to = e.id and rev.kind = 'reversal'
            )
            and (p_from is null or e.created_at >= p_from)
            and (p_to is null or e.created_at < p_to)
          group by ch.venue_id
        ) k on k.venue_id = v.id
        left join (
          select venue_id, sum(open_cents)::bigint as debt_cents
          from (
            select venue_id, (amount_cents - applied_cents) as open_cents
            from public.venue_credit_clawbacks
            where voided_at is null
              and neutralized_at is null
              and applied_cents < amount_cents
            union all
            select venue_id, (amount_cents - applied_cents)
            from public.venue_cashback_debits
            where voided_at is null
              and applied_cents < amount_cents
          ) open_debt
          group by venue_id
        ) d on d.venue_id = v.id
        where (p_venue_id is null or v.id = p_venue_id)
          and (
            c.venue_id is not null
            or r.venue_id is not null
            or k.venue_id is not null
            or d.venue_id is not null
          )
      ) s
    ), '[]'::jsonb),
    'open_components', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.venue_name, s.kind)
      from (
        select
          v.id as venue_id,
          v.name as venue_name,
          'clawback'::text as kind,
          'debt'::text as direction,
          (c.amount_cents - c.applied_cents) as open_cents,
          true as all_or_nothing
        from public.venue_credit_clawbacks c
        join public.venues v on v.id = c.venue_id
        where c.voided_at is null
          and c.neutralized_at is null
          and c.applied_cents < c.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
        union all
        select
          v.id,
          v.name,
          'cashback_debit',
          'debt',
          d.amount_cents - d.applied_cents,
          true
        from public.venue_cashback_debits d
        join public.venues v on v.id = d.venue_id
        where d.voided_at is null
          and d.applied_cents < d.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
        union all
        select
          v.id,
          v.name,
          'venue_credit',
          'credit',
          e.amount_cents - e.applied_cents,
          true
        from public.venue_referral_entries e
        join public.venues v on v.id = e.venue_id
        where e.kind = 'accrual'
          and e.settlement = 'released'
          and e.review_status is distinct from 'em_revisao'
          and e.review_status is distinct from 'rejected'
          and e.applied_cents < e.amount_cents
          and not exists (
            select 1 from public.venue_referral_entries r
            where r.relates_to = e.id and r.kind = 'reversal'
          )
          and (p_venue_id is null or v.id = p_venue_id)
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_highlights()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return pg_catalog.jsonb_build_object(
    'venues', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.featured_rank nulls last, s.name)
      from (
        select id, name, city_id, status, featured_rank
        from public.venues
        where status = 'approved'
        order by featured_rank nulls last, name
        limit 200
      ) s
    ), '[]'::jsonb),
    'rooms', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.featured_rank nulls last, s.name)
      from (
        select r.id, r.name, v.name as venue_name, r.featured_rank
        from public.rooms r
        join public.venues v on v.id = r.venue_id
        where v.status = 'approved'
        order by r.featured_rank nulls last, r.name
        limit 200
      ) s
    ), '[]'::jsonb),
    'news', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.carousel_rank nulls last, s.published_at desc)
      from (
        select n.id, n.title, v.name as venue_name, n.carousel_rank, n.published_at
        from public.news_items n
        join public.venues v on v.id = n.venue_id
        order by n.carousel_rank nulls last, n.published_at desc
        limit 80
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_set_highlight(
  p_kind text,
  p_id uuid,
  p_rank integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before integer;
begin
  if p_kind not in ('venue', 'room', 'news') then
    raise exception 'destaque invalido' using errcode = '22023';
  end if;
  if p_rank is not null and (p_rank < 0 or p_rank > 99) then
    raise exception 'ordem invalida' using errcode = '22023';
  end if;
  if p_kind = 'venue' then
    select featured_rank into v_before from public.venues where id = p_id for update;
    if not found then
      raise exception 'casa nao encontrada' using errcode = 'P0002';
    end if;
    update public.venues set featured_rank = p_rank where id = p_id;
  elsif p_kind = 'room' then
    select featured_rank into v_before from public.rooms where id = p_id for update;
    if not found then
      raise exception 'sala nao encontrada' using errcode = 'P0002';
    end if;
    update public.rooms set featured_rank = p_rank where id = p_id;
  else
    select carousel_rank into v_before from public.news_items where id = p_id for update;
    if not found then
      raise exception 'noticia nao encontrada' using errcode = 'P0002';
    end if;
    update public.news_items set carousel_rank = p_rank where id = p_id;
  end if;
  perform private.admin_audit(
    v_uid, 'set_highlight', p_kind, p_id::text,
    pg_catalog.jsonb_build_object('rank', v_before),
    pg_catalog.jsonb_build_object('rank', p_rank)
  );
  return pg_catalog.jsonb_build_object('kind', p_kind, 'id', p_id, 'rank', p_rank);
end;
$$;

create or replace function public.admin_audit(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at desc)
    from (
      select
        id, actor_id, action, target_table, target_id,
        before_state, after_state, created_at
      from public.admin_audit_log
      order by created_at desc
      limit v_limit
    ) s
  ), '[]'::jsonb);
end;
$$;

do $$
declare
  v_sig text;
begin
  for v_sig in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'admin_whoami',
        'admin_list_venues',
        'admin_venue',
        'admin_review_venue',
        'admin_suspend_venue',
        'admin_update_venue',
        'admin_set_commission',
        'admin_list_players',
        'admin_player',
        'admin_suspend_player',
        'admin_referral_queue',
        'admin_decide_referral_account',
        'admin_reward_settings',
        'admin_save_reward_settings',
        'admin_reward_history',
        'admin_earnings',
        'admin_highlights',
        'admin_set_highlight',
        'admin_audit'
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, service_role',
      v_sig
    );
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;
