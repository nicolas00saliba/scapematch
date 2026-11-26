-- Catálogo IBGE: ids antigos intactos e os demais municípios disponíveis.
-- Roda numa transação e desfaz. Não fala com o projeto remoto.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_count integer;
  v_dupes integer;
begin
  select count(*) into v_count from public.cities;
  if v_count <> 5571 then
    raise exception 'esperava 5571 municípios, veio %', v_count;
  end if;

  if not exists (
    select 1
    from public.cities
    where id = 'curitiba'
      and ibge_code = '4106902'
      and name = 'Curitiba'
      and state_code = 'PR'
  ) then
    raise exception 'id legado curitiba perdido';
  end if;

  if not exists (
    select 1 from public.cities
    where id = 'sao-paulo' and ibge_code = '3550308'
  ) then
    raise exception 'id legado sao-paulo perdido';
  end if;

  if not exists (
    select 1 from public.cities
    where id = 'rio-de-janeiro' and ibge_code = '3304557'
  ) then
    raise exception 'id legado rio-de-janeiro perdido';
  end if;

  if not exists (
    select 1 from public.cities
    where id = 'belo-horizonte' and ibge_code = '3106200'
  ) then
    raise exception 'id legado belo-horizonte perdido';
  end if;

  if not exists (
    select 1 from public.cities
    where id = 'porto-alegre' and ibge_code = '4314902'
  ) then
    raise exception 'id legado porto-alegre perdido';
  end if;

  if not exists (
    select 1
    from public.cities
    where id = 'campinas-sp'
      and ibge_code = '3509502'
      and country_code = 'BR'
  ) then
    raise exception 'campinas-sp não entrou no catálogo';
  end if;

  if not exists (
    select 1
    from public.cities
    where id = 'boa-esperanca-do-norte-mt'
      and ibge_code = '5101837'
  ) then
    raise exception 'município novo do IBGE ausente';
  end if;

  select count(*)
    into v_dupes
  from (
    select ibge_code
    from public.cities
    group by ibge_code
    having count(*) > 1
  ) d;
  if v_dupes > 0 then
    raise exception 'ibge_code repetido em % linhas', v_dupes;
  end if;
end $$;

-- Só aparece a cidade com casa aprovada e não suspensa, e a view respeita a RLS.
-- Os testes de corrida anteriores deixam linhas gravadas; por isso a conferência
-- é por cidade (londrina-pr e campinas-sp), nunca pela contagem total.
do $$
declare
  v_owner uuid := 'c3610000-0000-4000-8000-0000000000b1';
  v_venue uuid := 'c3620000-0000-4000-8000-000000000001';
  v_seen boolean;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_owner, 'cidades-dono@example.com', '{"display_name":"Dono"}');

  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values
    (v_venue, v_owner, 'londrina-pr', 'Casa Aprovada',
     'Centro', 'Rua A', '1', '86010000', -23.30, -51.17, 5000, 'cnpj',
     '61234567000389', '4330002611', 'approved'),
    ('c3620000-0000-4000-8000-000000000002', v_owner, 'campinas-sp', 'Casa Pendente',
     'Centro', 'Rua B', '2', '13010000', -22.9, -47.06, 5000, 'cnpj',
     '71234567000380', '1930002611', 'pending');

  select exists (select 1 from public.cities_with_active_venues where id = 'londrina-pr')
    into v_seen;
  if not v_seen then
    raise exception 'cidade com casa aprovada não apareceu';
  end if;
  select exists (select 1 from public.cities_with_active_venues where id = 'campinas-sp')
    into v_seen;
  if v_seen then
    raise exception 'casa pendente abriu a cidade';
  end if;

  update public.venues set suspended_at = pg_catalog.now() where id = v_venue;
  select exists (select 1 from public.cities_with_active_venues where id = 'londrina-pr')
    into v_seen;
  if v_seen then
    raise exception 'casa suspensa não pode abrir a cidade';
  end if;
  update public.venues set suspended_at = null where id = v_venue;
end $$;

set local role anon;

do $$
declare
  v_seen boolean;
  v_other integer;
begin
  select exists (select 1 from public.cities_with_active_venues where id = 'londrina-pr')
    into v_seen;
  if not v_seen then
    raise exception 'anon não viu a cidade com casa aprovada';
  end if;
  select count(*) into v_other
  from public.cities_with_active_venues where id = 'campinas-sp';
  if v_other <> 0 then
    raise exception 'anon viu cidade só com casa pendente';
  end if;
end $$;

reset role;

rollback;
