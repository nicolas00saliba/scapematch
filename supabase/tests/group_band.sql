-- Faixa mín–máx. Não cobra provedor. Roda depois das migrations, no Postgres local.
-- A migração iguala o mínimo antigo ao alvo Z. Este arquivo prova o
-- comportamento novo e repete essa conversão numa linha de teste.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c5555555-5555-5555-5555-555555555555', 'faixa-5@example.com', '{"display_name":"Faixa Cinco"}'),
  ('c6666666-6666-6666-6666-666666666666', 'faixa-6@example.com', '{"display_name":"Faixa Seis"}'),
  ('c7777777-7777-7777-7777-777777777777', 'faixa-7@example.com', '{"display_name":"Faixa Sete"}'),
  ('c8888888-8888-8888-8888-888888888888', 'faixa-8@example.com', '{"display_name":"Faixa Oito"}')
on conflict (id) do nothing;

update public.venues
set asaas_wallet_id = 'wal_teste_faixa'
where id = 'ca111111-1111-1111-1111-111111111111'
  and (asaas_wallet_id is null or btrim(asaas_wallet_id) = '');

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  (
    'ce555555-5555-5555-5555-555555555555',
    'cc111111-1111-1111-1111-111111111111',
    '2027-08-01 18:00:00+00',
    'partner_grid'
  ),
  (
    'ce666666-6666-6666-6666-666666666666',
    'cc111111-1111-1111-1111-111111111111',
    '2027-08-02 18:00:00+00',
    'partner_grid'
  );

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'groups_with_counts'
      and column_name = 'confirmed_at'
  ) then
    raise exception 'groups_with_counts sem confirmed_at';
  end if;
  if has_function_privilege(
    'authenticated', 'private.mark_group_bounds(uuid)', 'execute'
  ) or has_function_privilege(
    'anon', 'private.mark_group_bounds(uuid)', 'execute'
  ) then
    raise exception 'mark_group_bounds ficou executável pela API';
  end if;
end $$;

create temp table band_group (id uuid);
grant all on band_group to authenticated;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;
insert into band_group
select public.create_group(
  'ce555555-5555-5555-5555-555555555555',
  6,
  '',
  4
);
reset role;

do $$
declare
  v_group uuid;
  v_min integer;
  v_max integer;
  v_confirmed timestamptz;
  v_closed timestamptz;
begin
  select id into v_group from band_group;
  select minimum_spots, total_spots, confirmed_at, closed_at
    into v_min, v_max, v_confirmed, v_closed
  from public.groups
  where id = v_group;
  if v_min <> 4 or v_max <> 6 or v_confirmed is not null or v_closed is not null then
    raise exception 'criação da faixa: min % max % confirmed % closed %',
      v_min, v_max, v_confirmed, v_closed;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c3333333-3333-3333-3333-333333333333', true);
set local role authenticated;
select public.join_group(id) from band_group;
reset role;
select set_config('request.jwt.claim.sub', 'c4444444-4444-4444-4444-444444444444', true);
set local role authenticated;
select public.join_group(id) from band_group;
reset role;

do $$
declare
  v_group uuid;
begin
  select id into v_group from band_group;
  if (select confirmed_at from public.groups where id = v_group) is not null
    or (select closed_at from public.groups where id = v_group) is not null
  then
    raise exception 'confirmou antes do mínimo';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c5555555-5555-5555-5555-555555555555', true);
set local role authenticated;
select public.join_group(id) from band_group;
reset role;

do $$
declare
  v_group uuid;
  v_confirmed timestamptz;
  v_closed timestamptz;
  v_filled integer;
begin
  select id into v_group from band_group;
  select confirmed_at, closed_at into v_confirmed, v_closed
  from public.groups where id = v_group;
  select filled_spots into v_filled
  from public.groups_with_counts where id = v_group;
  if v_filled <> 4 or v_confirmed is null or v_closed is not null then
    raise exception 'mínimo não confirmou aberto: filled % confirmed % closed %',
      v_filled, v_confirmed, v_closed;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c6666666-6666-6666-6666-666666666666', true);
set local role authenticated;
select public.join_group(id) from band_group;
reset role;

do $$
declare
  v_group uuid;
begin
  select id into v_group from band_group;
  if (select closed_at from public.groups where id = v_group) is not null
    or (select confirmed_at from public.groups where id = v_group) is null
  then
    raise exception 'a quinta pessoa deveria entrar com o grupo confirmado e aberto';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c7777777-7777-7777-7777-777777777777', true);
set local role authenticated;
select public.join_group(id) from band_group;
reset role;

do $$
declare
  v_group uuid;
begin
  select id into v_group from band_group;
  if (select closed_at from public.groups where id = v_group) is null
    or (select total_spots from public.groups where id = v_group) <> 6
  then
    raise exception 'o máximo não lotou';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c8888888-8888-8888-8888-888888888888', true);
set local role authenticated;
do $$
declare
  v_group uuid;
begin
  select id into v_group from band_group;
  begin
    perform public.join_group(v_group);
    raise exception 'entrou acima do máximo';
  exception
    when raise_exception then
      if sqlerrm not like '%group full%' then
        raise;
      end if;
  end;
end $$;
reset role;

do $$
declare
  v_group uuid;
begin
  select id into v_group from band_group;
  begin
    perform public.close_group_with_fewer(v_group);
    raise exception 'fechou antes do máximo';
  exception
    when raise_exception then
      if sqlerrm not like '%stays open%' then
        raise;
      end if;
  end;
end $$;

-- Prazo vencido com gente abaixo do mínimo: não confirma.
select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;
create temp table band_late (id uuid);
grant all on band_late to authenticated;
insert into band_late
select public.create_group(
  'ce666666-6666-6666-6666-666666666666',
  6,
  '',
  4
);
reset role;
update public.groups
set closes_at = timestamptz '2020-01-01 00:00:00+00'
where id = (select id from band_late);
do $$
declare
  v_group uuid;
  v_filled integer;
begin
  select id into v_group from band_late;
  select filled_spots into v_filled
  from public.groups_with_counts where id = v_group;
  if v_filled >= 4
    or (select confirmed_at from public.groups where id = v_group) is not null
    or (select closed_at from public.groups where id = v_group) is not null
    or (select closes_at from public.groups where id = v_group) > now()
  then
    raise exception 'prazo sem mínimo não ficou na condição de liberar';
  end if;
end $$;

-- Alvo Z vira mín = Z e máx = Z. Não reabre vaga.
insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by, closed_at
) values (
  'cd555555-5555-5555-5555-555555555555',
  'curitiba',
  'ca111111-1111-1111-1111-111111111111',
  'cc111111-1111-1111-1111-111111111111',
  '2027-09-01 18:00:00+00',
  6,
  2,
  8000,
  'c2222222-2222-2222-2222-222222222222',
  '2026-11-01 12:00:00+00'
);
update public.groups
set minimum_spots = total_spots
where id = 'cd555555-5555-5555-5555-555555555555'
  and minimum_spots is distinct from total_spots;
update public.groups
set confirmed_at = closed_at
where id = 'cd555555-5555-5555-5555-555555555555'
  and closed_at is not null
  and confirmed_at is null;
do $$
declare
  v_min integer;
  v_max integer;
  v_confirmed timestamptz;
  v_closed timestamptz;
begin
  select minimum_spots, total_spots, confirmed_at, closed_at
    into v_min, v_max, v_confirmed, v_closed
  from public.groups
  where id = 'cd555555-5555-5555-5555-555555555555';
  if v_min <> 6 or v_max <> 6 or v_confirmed is distinct from v_closed then
    raise exception 'conversão do alvo Z não ficou mín = máx = Z';
  end if;
end $$;

commit;
