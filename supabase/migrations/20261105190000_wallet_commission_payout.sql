-- Carteira real, comissão auditada e casa sem subconta.
-- Também tira o EXECUTE de authenticated nas funções private de
-- duplicata/reivindicação. Os wrappers públicos passam a SECURITY
-- DEFINER aqui mesmo: o PR #61 faz o mesmo ALTER. Repetir é
-- idempotente, e o REVOKE não pode rodar enquanto o wrapper for INVOKER.
-- Nada aqui é aplicado no banco remoto.

-- Cartão desativado some da lista e não cobra de novo.
alter table public.saved_cards
  add column if not exists deactivated_at timestamptz;

create or replace function public.my_saved_cards()
returns table (
  id uuid,
  last4 text,
  brand text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.last4, c.brand, c.created_at
  from public.saved_cards c
  where c.user_id = (select auth.uid())
    and c.deactivated_at is null
  order by c.created_at desc;
$$;

revoke all on function public.my_saved_cards() from public, anon;
grant execute on function public.my_saved_cards() to authenticated;

create or replace function public.deactivate_my_saved_card(p_card_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_updated integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  update public.saved_cards
  set deactivated_at = pg_catalog.now()
  where id = p_card_id
    and user_id = v_uid
    and deactivated_at is null;
  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

revoke all on function public.deactivate_my_saved_card(uuid)
  from public, anon;
grant execute on function public.deactivate_my_saved_card(uuid)
  to authenticated;

create or replace function private.load_owned_card(
  p_user_id uuid,
  p_customer_id text,
  p_card_id uuid
) returns table (
  id uuid,
  token text,
  last4 text,
  brand text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select
    c.id,
    extensions.pgp_sym_decrypt(c.credit_card_token, private.card_token_key()),
    c.last4,
    c.brand
  from public.saved_cards c
  where c.id = p_card_id
    and c.user_id = p_user_id
    and c.asaas_customer_id = p_customer_id
    and c.deactivated_at is null;
end;
$$;

revoke all on function private.load_owned_card(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function private.load_owned_card(uuid, text, uuid)
  to service_role;

-- O teto de 5 conta só cartão ativo. Desativar libera uma vaga.
create or replace function private.claim_card_tokenize_attempt(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts bigint;
  v_cards bigint;
begin
  if p_user_id is null then
    return false;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('card_tokenize'),
    pg_catalog.hashtext(p_user_id::text)
  );
  delete from public.card_tokenize_attempts
  where user_id = p_user_id
    and created_at <= pg_catalog.now() - interval '1 hour';
  insert into public.card_tokenize_attempts (user_id)
  values (p_user_id);
  select count(*) into v_attempts
  from public.card_tokenize_attempts
  where user_id = p_user_id;
  select count(*) into v_cards
  from public.saved_cards
  where user_id = p_user_id
    and deactivated_at is null;
  return v_attempts <= 5 and v_cards < 5;
end;
$$;

revoke all on function private.claim_card_tokenize_attempt(uuid)
  from public, anon, authenticated;
grant execute on function private.claim_card_tokenize_attempt(uuid)
  to service_role;

-- O #61 move saved_cards_limit para private. Atualiza o corpo onde ela estiver.
do $limit$
declare
  v_schema text := case
    when to_regprocedure('private.saved_cards_limit()') is not null then 'private'
    else 'public'
  end;
  v_sql text;
begin
  v_sql := format($fn$
    create or replace function %I.saved_cards_limit()
    returns trigger
    language plpgsql
    security definer
    set search_path = ''
    as $body$
    declare
      v_count bigint;
    begin
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext('card_tokenize'),
        pg_catalog.hashtext(new.user_id::text)
      );
      select count(*) into v_count
      from public.saved_cards
      where user_id = new.user_id
        and deactivated_at is null;
      if v_count >= 5 then
        raise exception 'limite de cartões';
      end if;
      return new;
    end;
    $body$;
  $fn$, v_schema);
  execute v_sql;
  execute format(
    'revoke all on function %I.saved_cards_limit() from public, anon, authenticated',
    v_schema
  );
  drop trigger if exists saved_cards_limit on public.saved_cards;
  execute format(
    'create trigger saved_cards_limit before insert on public.saved_cards for each row execute function %I.saved_cards_limit()',
    v_schema
  );
end
$limit$;

-- Cobranças do próprio jogador. INVOKER: o RLS de payment_charges,
-- groups e rooms continua valendo. A sala some se a policy esconder.
create or replace function public.my_payments()
returns table (
  id uuid,
  amount_cents integer,
  room_name text,
  charged_at timestamptz,
  status text,
  refunded boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    c.id,
    c.amount_cents,
    r.name,
    c.created_at,
    c.status,
    (c.status = 'refunded' or c.refunded_at is not null)
  from public.payment_charges c
  left join public.groups g on g.id = c.group_id
  left join public.rooms r on r.id = g.room_id
  where c.user_id = (select auth.uid())
  order by c.created_at desc;
$$;

revoke all on function public.my_payments() from public, anon;
grant execute on function public.my_payments() to authenticated;

-- Comissão: 0 a 30%. Quem mudou e quando ficam na linha e no histórico.
do $$
declare
  v_name text;
begin
  for v_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.platform_settings'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%commission_bps%'
  loop
    execute format(
      'alter table public.platform_settings drop constraint %I',
      v_name
    );
  end loop;
end $$;

alter table public.platform_settings
  add constraint platform_settings_commission_bps_range
  check (commission_bps between 0 and 3000);

alter table public.platform_settings
  add column if not exists updated_by uuid references auth.users (id),
  add column if not exists updated_at timestamptz;

create table public.venue_commissions (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  commission_bps integer not null,
  updated_by uuid not null references auth.users (id),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint venue_commissions_bps_range check (commission_bps between 0 and 3000)
);

create table public.commission_changes (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id),
  venue_id uuid references public.venues (id) on delete set null,
  before_bps integer not null,
  after_bps integer not null,
  created_at timestamptz not null default pg_catalog.now(),
  constraint commission_changes_before_range check (before_bps between 0 and 10000),
  constraint commission_changes_after_range check (after_bps between 0 and 3000)
);

alter table public.venue_commissions enable row level security;
alter table public.commission_changes enable row level security;

revoke all on table public.venue_commissions from public, anon, authenticated;
revoke all on table public.commission_changes from public, anon, authenticated;

create or replace function public.set_platform_commission(p_commission_bps integer)
returns table (
  commission_bps integer,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_before integer;
  v_at timestamptz := pg_catalog.now();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_commission_bps is null
    or p_commission_bps < 0
    or p_commission_bps > 3000
  then
    raise exception 'comissão fora de 0 a 30%%' using errcode = '22023';
  end if;
  select s.commission_bps into v_before
  from public.platform_settings s
  where s.id = 1
  for update;
  if v_before is null then
    raise exception 'configuração ausente';
  end if;
  update public.platform_settings s
  set commission_bps = p_commission_bps,
      updated_by = v_uid,
      updated_at = v_at
  where s.id = 1;
  insert into public.commission_changes (
    actor_id, venue_id, before_bps, after_bps, created_at
  ) values (
    v_uid, null, v_before, p_commission_bps, v_at
  );
  return query
  select p_commission_bps, v_uid, v_at;
end;
$$;

create or replace function public.set_venue_commission(
  p_venue_id uuid,
  p_commission_bps integer
)
returns table (
  venue_id uuid,
  commission_bps integer,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_before integer;
  v_at timestamptz := pg_catalog.now();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_venue_id is null or not exists (
    select 1 from public.venues v where v.id = p_venue_id
  ) then
    raise exception 'unknown venue' using errcode = 'P0002';
  end if;
  if p_commission_bps is null
    or p_commission_bps < 0
    or p_commission_bps > 3000
  then
    raise exception 'comissão fora de 0 a 30%%' using errcode = '22023';
  end if;
  select coalesce(
    (select c.commission_bps from public.venue_commissions c where c.venue_id = p_venue_id),
    (select s.commission_bps from public.platform_settings s where s.id = 1)
  ) into v_before;
  insert into public.venue_commissions (
    venue_id, commission_bps, updated_by, updated_at
  ) values (
    p_venue_id, p_commission_bps, v_uid, v_at
  )
  on conflict on constraint venue_commissions_pkey do update
  set commission_bps = excluded.commission_bps,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;
  insert into public.commission_changes (
    actor_id, venue_id, before_bps, after_bps, created_at
  ) values (
    v_uid, p_venue_id, v_before, p_commission_bps, v_at
  );
  return query
  select p_venue_id, p_commission_bps, v_uid, v_at;
end;
$$;

create or replace function public.commission_board()
returns table (
  venue_id uuid,
  venue_name text,
  commission_bps integer,
  is_override boolean,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  return query
  select
    null::uuid,
    'ScapeMatch'::text,
    s.commission_bps,
    false,
    s.updated_by,
    s.updated_at
  from public.platform_settings s
  where s.id = 1;
  return query
  select
    v.id,
    v.name,
    coalesce(c.commission_bps, s.commission_bps),
    c.venue_id is not null,
    c.updated_by,
    c.updated_at
  from public.venues v
  cross join public.platform_settings s
  left join public.venue_commissions c on c.venue_id = v.id
  where s.id = 1
  order by v.name;
end;
$$;

create or replace function public.commission_bps_for_venue(p_venue_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select c.commission_bps
      from public.venue_commissions c
      where c.venue_id = p_venue_id
    ),
    (
      select s.commission_bps
      from public.platform_settings s
      where s.id = 1
    )
  );
$$;

revoke all on function public.set_platform_commission(integer) from public, anon;
revoke all on function public.set_venue_commission(uuid, integer) from public, anon;
revoke all on function public.commission_board() from public, anon;
revoke all on function public.commission_bps_for_venue(uuid)
  from public, anon, authenticated;
grant execute on function public.set_platform_commission(integer) to authenticated;
grant execute on function public.set_venue_commission(uuid, integer) to authenticated;
grant execute on function public.commission_board() to authenticated;
grant execute on function public.commission_bps_for_venue(uuid) to service_role;

-- A vitrine mostra se a casa recebe, sem entregar o walletId.
alter table public.venues
  add column if not exists receives_payments boolean
  generated always as (
    asaas_wallet_id is not null and btrim(asaas_wallet_id) <> ''
  ) stored;

grant select (receives_payments) on table public.venues to anon, authenticated;

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
  receives_payments
from public.venues;

revoke all on table public.venues_vitrine from public, anon, authenticated;
grant select on table public.venues_vitrine to anon, authenticated, service_role;

-- Grupo novo só em casa aprovada com subconta. Sem JWT (teste e seed)
-- o insert segue, para não quebrar fixture antiga.
create or replace function private.groups_require_payout_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet text;
  v_status text;
begin
  if auth.uid() is null then
    return new;
  end if;
  select v.status, v.asaas_wallet_id
    into v_status, v_wallet
  from public.venues v
  where v.id = new.venue_id;
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

drop trigger if exists groups_require_payout_account on public.groups;
create trigger groups_require_payout_account
  before insert on public.groups
  for each row execute function private.groups_require_payout_account();

-- Wrappers do Parceiro. O #61 também os marca DEFINER. Sem isso,
-- o REVOKE abaixo derruba o Parceiro enquanto o wrapper for INVOKER.
alter function public.check_venue_duplicates(text, text, text, text, text)
  security definer;
alter function public.request_venue_claim(uuid, text, uuid)
  security definer;
alter function public.review_venue(uuid, text, uuid)
  security definer;
alter function public.review_venue_claim(uuid, text)
  security definer;

revoke execute on function private.check_venue_duplicates(text, text, text, text, text)
  from authenticated;
revoke execute on function private.request_venue_claim(uuid, text, uuid)
  from authenticated;
revoke execute on function private.review_venue(uuid, text, uuid)
  from authenticated;
revoke execute on function private.review_venue_claim(uuid, text)
  from authenticated;
