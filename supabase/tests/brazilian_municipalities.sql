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
do $$
declare
  v_owner uuid := 'c3610000-0000-4000-8000-0000000000b1';
  v_names text;
  v_count integer;
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_owner, 'cidades-dono@example.com', '{"display_name":"Dono"}');

  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values
    ('c3620000-0000-4000-8000-000000000001', v_owner, 'curitiba', 'Casa Aprovada',
     'Centro', 'Rua A', '1', '80010020', -25.43, -49.27, 5000, 'cnpj',
     '61234567000389', '4130002611', 'approved'),
    ('c3620000-0000-4000-8000-000000000002', v_owner, 'campinas-sp', 'Casa Pendente',
     'Centro', 'Rua B', '2', '13010000', -22.9, -47.06, 5000, 'cnpj',
     '71234567000380', '1930002611', 'pending');

  select count(*) into v_count from public.cities_with_active_venues;
  if v_count <> 1 then
    raise exception 'esperava 1 cidade com casa ativa, veio %', v_count;
  end if;

  update public.venues
  set suspended_at = now()
  where id = 'c3620000-0000-4000-8000-000000000001';
  select count(*) into v_count from public.cities_with_active_venues;
  if v_count <> 0 then
    raise exception 'casa suspensa não pode abrir a cidade';
  end if;
  update public.venues
  set suspended_at = null
  where id = 'c3620000-0000-4000-8000-000000000001';

  set local role anon;
  select string_agg(id, ',') into v_names from public.cities_with_active_venues;
  reset role;
  if v_names is distinct from 'curitiba' then
    raise exception 'anon deveria ver só curitiba, viu %', v_names;
  end if;

  set local role anon;
  begin
    perform 1 from public.cities_with_active_venues where id = 'campinas-sp';
    select count(*) into v_count
    from public.cities_with_active_venues where id = 'campinas-sp';
  exception when others then
    reset role;
    raise;
  end;
  reset role;
  if v_count <> 0 then
    raise exception 'casa pendente não abre cidade para o anon';
  end if;
end $$;

rollback;
