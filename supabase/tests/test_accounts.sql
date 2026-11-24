-- Contas fantasmas: casa de teste some para anon e jogador comum,
-- aparece para conta de teste, nasce de teste quando o dono é de teste
-- e o dono não tira a marca. supabase/migrations/20261124190000_test_accounts.sql

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f0111111-1111-4111-8111-111111111111', 'casa-fantasma@example.com', '{"display_name":"Casa Fantasma"}'),
  ('f0222222-2222-4222-8222-222222222222', 'jogador-fantasma@example.com', '{"display_name":"Jogador Fantasma"}'),
  ('f0333333-3333-4333-8333-333333333333', 'jogador-real@example.com', '{"display_name":"Jogador Real"}');

update public.profiles set is_test = true
where id in ('f0111111-1111-4111-8111-111111111111', 'f0222222-2222-4222-8222-222222222222');

-- Dono de teste cria a casa pelo app.
begin;
select set_config('request.jwt.claim.sub', 'f0111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone
) values (
  'f0411111-1111-4111-8111-111111111111',
  'f0111111-1111-4111-8111-111111111111',
  'curitiba', 'Casa Fantasma 1', 'Centro', 'Rua do Teste', '1',
  '80010001', -25.43, -49.27, 5000, 'cnpj', '19000000000194', '41900001114'
);
reset role;
commit;

do $$
begin
  if not (select is_test from public.venues where id = 'f0411111-1111-4111-8111-111111111111') then
    raise exception 'casa de dono de teste não nasceu de teste';
  end if;
end $$;

-- Aprovação (como o admin faria) e uma sala.
update public.venues set status = 'approved'
where id = 'f0411111-1111-4111-8111-111111111111';

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'f0511111-1111-4111-8111-111111111111',
  'f0411111-1111-4111-8111-111111111111',
  'Sala Fantasma', '', 6, 2, 60, 'medium', 500
);

-- O dono não tira a marca.
begin;
select set_config('request.jwt.claim.sub', 'f0111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
update public.venues set is_test = false
where id = 'f0411111-1111-4111-8111-111111111111';
reset role;
commit;

do $$
begin
  if not (select is_test from public.venues where id = 'f0411111-1111-4111-8111-111111111111') then
    raise exception 'dono conseguiu tirar a marca de teste';
  end if;
end $$;

-- Anon não vê.
begin;
set local role anon;
do $$
begin
  if exists (select 1 from public.venues where id = 'f0411111-1111-4111-8111-111111111111')
    or exists (select 1 from public.venues_vitrine where id = 'f0411111-1111-4111-8111-111111111111')
    or exists (select 1 from public.rooms where id = 'f0511111-1111-4111-8111-111111111111')
  then
    raise exception 'anon vê casa de teste';
  end if;
end $$;
reset role;
commit;

-- Jogador comum não vê e não marca o próprio perfil.
begin;
select set_config('request.jwt.claim.sub', 'f0333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if exists (select 1 from public.venues where id = 'f0411111-1111-4111-8111-111111111111')
    or exists (select 1 from public.venues_vitrine where id = 'f0411111-1111-4111-8111-111111111111')
    or exists (select 1 from public.rooms where id = 'f0511111-1111-4111-8111-111111111111')
  then
    raise exception 'jogador comum vê casa de teste';
  end if;
  begin
    update public.profiles set is_test = true
    where id = 'f0333333-3333-4333-8333-333333333333';
    raise exception 'jogador comum gravou is_test';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;
commit;

-- Jogador de teste vê.
begin;
select set_config('request.jwt.claim.sub', 'f0222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if not exists (select 1 from public.venues_vitrine where id = 'f0411111-1111-4111-8111-111111111111')
    or not exists (select 1 from public.rooms where id = 'f0511111-1111-4111-8111-111111111111')
  then
    raise exception 'jogador de teste não vê casa de teste';
  end if;
end $$;
reset role;
commit;

do $$
begin
  if pg_get_functiondef('public.review_rankings(text, text, text, text)'::regprocedure)
    not like '%not venue.is_test%'
  then
    raise exception 'review_rankings ainda conta casa de teste';
  end if;
  if exists (select 1 from public.venues where is_test and owner_id is null) then
    raise exception 'casa de teste sem dono';
  end if;
end $$;

-- Limpa para os testes seguintes.
delete from public.rooms where id = 'f0511111-1111-4111-8111-111111111111';
delete from public.venues where id = 'f0411111-1111-4111-8111-111111111111';
delete from auth.users where id in (
  'f0111111-1111-4111-8111-111111111111',
  'f0222222-2222-4222-8222-222222222222',
  'f0333333-3333-4333-8333-333333333333'
);
