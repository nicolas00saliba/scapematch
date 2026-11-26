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

rollback;
