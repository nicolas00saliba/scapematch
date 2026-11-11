-- A migration só troca o default intocado. Override de casa e taxa
-- gravada pelo Admin ficam. Roda dentro de uma transação e desfaz.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_default text;
begin
  select pg_get_expr(d.adbin, d.adrelid)
    into v_default
  from pg_attrdef d
  join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
  join pg_class c on c.oid = d.adrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'platform_settings'
    and a.attname = 'commission_bps';
  if v_default is distinct from '2500' then
    raise exception 'default da comissão é %', coalesce(v_default, '(nulo)');
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'c2511111-1111-4111-8111-111111111111',
  'comissao-25@example.com',
  '{"display_name":"Comissão"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'c2511111-1111-4111-8111-111111111112',
  'c2511111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa Com Taxa',
  'Centro',
  'Rua da Taxa',
  '25',
  '80020000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '25111111000125',
  '41988880025',
  'approved'
);

insert into public.venue_commissions (venue_id, commission_bps, updated_by)
values (
  'c2511111-1111-4111-8111-111111111112',
  1000,
  'c2511111-1111-4111-8111-111111111111'
);

-- Semente antiga, sem auditoria: vira 25%. A casa com taxa própria não muda.
delete from public.commission_changes where venue_id is null;
update public.platform_settings
set commission_bps = 1000,
    updated_by = null,
    updated_at = null
where id = 1;

update public.platform_settings s
set commission_bps = 2500
where s.id = 1
  and s.commission_bps = 1000
  and s.updated_by is null
  and s.updated_at is null
  and not exists (
    select 1
    from public.commission_changes c
    where c.venue_id is null
  );

do $$
declare
  v_platform integer;
  v_house integer;
  v_fallback integer;
begin
  select commission_bps into v_platform
  from public.platform_settings
  where id = 1;
  select commission_bps into v_house
  from public.venue_commissions
  where venue_id = 'c2511111-1111-4111-8111-111111111112';
  if v_platform <> 2500 then
    raise exception 'semente não foi para 25%%: %', v_platform;
  end if;
  if v_house <> 1000 then
    raise exception 'override de 10%% foi reescrito: %', v_house;
  end if;
end $$;

set local role service_role;
do $$
declare
  v_house integer;
  v_fallback integer;
begin
  select public.commission_bps_for_venue('c2511111-1111-4111-8111-111111111112')
    into v_house;
  select public.commission_bps_for_venue('c2511111-1111-4111-8111-111111111199')
    into v_fallback;
  if v_house <> 1000 or v_fallback <> 2500 then
    raise exception 'fallback leu % e override %', v_fallback, v_house;
  end if;
end $$;
reset role;

-- Taxa da plataforma gravada pelo Admin, ainda em 10%, não é semente.
insert into public.commission_changes (
  actor_id, venue_id, before_bps, after_bps
) values (
  'c2511111-1111-4111-8111-111111111111',
  null,
  2500,
  1000
);
update public.platform_settings
set commission_bps = 1000,
    updated_by = 'c2511111-1111-4111-8111-111111111111',
    updated_at = pg_catalog.now()
where id = 1;

update public.platform_settings s
set commission_bps = 2500
where s.id = 1
  and s.commission_bps = 1000
  and s.updated_by is null
  and s.updated_at is null
  and not exists (
    select 1
    from public.commission_changes c
    where c.venue_id is null
  );

do $$
declare
  v_platform integer;
begin
  select commission_bps into v_platform
  from public.platform_settings
  where id = 1;
  if v_platform <> 1000 then
    raise exception 'taxa do Admin foi reescrita: %', v_platform;
  end if;
end $$;

rollback;
