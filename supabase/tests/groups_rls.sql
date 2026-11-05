-- Prova que a leitura de grupos não recursa entre groups e group_members.
-- Roda depois das migrations, como superusuário, e troca de papel no meio.

\set ON_ERROR_STOP on

do $$
declare
  v_groups text;
  v_members text;
  v_count integer;
begin
  select count(*)
    into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname in ('is_group_member', 'group_is_readable')
    and p.prosecdef
    and 'search_path=""' = any (p.proconfig);
  if v_count <> 2 then
    raise exception 'funções de grupo sem security definer ou search_path: %', v_count;
  end if;

  if to_regprocedure('public.is_group_member(uuid)') is not null
    or to_regprocedure('public.group_is_readable(uuid)') is not null
  then
    raise exception 'funções de grupo ainda estão em public';
  end if;

  if not has_function_privilege('anon', 'private.is_group_member(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'private.is_group_member(uuid)', 'execute')
    or not has_function_privilege('anon', 'private.group_is_readable(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'private.group_is_readable(uuid)', 'execute')
  then
    raise exception 'anon ou authenticated não executa as funções de grupo';
  end if;

  select qual
    into v_groups
  from pg_policies
  where schemaname = 'public'
    and tablename = 'groups'
    and policyname = 'groups_select';
  select qual
    into v_members
  from pg_policies
  where schemaname = 'public'
    and tablename = 'group_members'
    and policyname = 'group_members_select';

  if v_groups is null
    or v_groups not like '%is_group_member%'
    or v_groups like '%group_members%'
  then
    raise exception 'groups_select ainda consulta group_members: %', v_groups;
  end if;
  if v_members is null
    or v_members not like '%group_is_readable%'
    or v_members like '%groups%'
  then
    raise exception 'group_members_select ainda consulta groups: %', v_members;
  end if;
  if (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename in ('groups', 'group_members')
      and cmd = 'SELECT'
  ) <> 2 then
    raise exception 'sobrou outra policy de select em groups ou group_members';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c1111111-1111-1111-1111-111111111111', 'dono-rls@example.com', '{"display_name":"Dono RLS"}'),
  ('c2222222-2222-2222-2222-222222222222', 'membro-rls@example.com', '{"display_name":"Membro RLS"}'),
  ('c3333333-3333-3333-3333-333333333333', 'estranho-rls@example.com', '{"display_name":"Estranho RLS"}'),
  ('c4444444-4444-4444-4444-444444444444', 'extra-rls@example.com', '{"display_name":"Extra RLS"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    'ca111111-1111-1111-1111-111111111111',
    'c1111111-1111-1111-1111-111111111111',
    'curitiba',
    'Casa Publica RLS',
    'Centro',
    'Rua das Flores',
    '10',
    '80010000',
    -25.43,
    -49.27,
    5000,
    'cnpj',
    '99888777000181',
    '41988880001',
    'approved'
  ),
  (
    'cb222222-2222-2222-2222-222222222222',
    'c1111111-1111-1111-1111-111111111111',
    'curitiba',
    'Casa Pendente RLS',
    'Batel',
    'Rua Escondida',
    '20',
    '80020000',
    -25.44,
    -49.28,
    4000,
    'cpf',
    '39053344705',
    '41988880002',
    'pending'
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'cc111111-1111-1111-1111-111111111111',
    'ca111111-1111-1111-1111-111111111111',
    'Sala Publica',
    '',
    6,
    2,
    60,
    'medium',
    8000
  ),
  (
    'cc222222-2222-2222-2222-222222222222',
    'cb222222-2222-2222-2222-222222222222',
    'Sala Pendente',
    '',
    6,
    2,
    60,
    'medium',
    8000
  );

insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values
  (
    'cd111111-1111-1111-1111-111111111111',
    'curitiba',
    'ca111111-1111-1111-1111-111111111111',
    'cc111111-1111-1111-1111-111111111111',
    '2026-12-01 18:00:00+00',
    6,
    2,
    8000,
    'c1111111-1111-1111-1111-111111111111'
  ),
  (
    'cd222222-2222-2222-2222-222222222222',
    'curitiba',
    'cb222222-2222-2222-2222-222222222222',
    'cc222222-2222-2222-2222-222222222222',
    '2026-12-01 19:00:00+00',
    6,
    2,
    8000,
    'c1111111-1111-1111-1111-111111111111'
  );

insert into public.group_members (group_id, user_id, display_name, is_creator)
values
  ('cd111111-1111-1111-1111-111111111111', 'c1111111-1111-1111-1111-111111111111', 'Dono RLS', true),
  ('cd111111-1111-1111-1111-111111111111', 'c4444444-4444-4444-4444-444444444444', 'Extra RLS', false),
  ('cd222222-2222-2222-2222-222222222222', 'c1111111-1111-1111-1111-111111111111', 'Dono RLS', true),
  ('cd222222-2222-2222-2222-222222222222', 'c2222222-2222-2222-2222-222222222222', 'Membro RLS', false);

begin;
set local role anon;

do $$
declare
  v_groups integer;
  v_members integer;
  v_filled integer;
begin
  select count(*) into v_groups from public.groups;
  select count(*) into v_members from public.group_members;
  select filled_spots
    into v_filled
  from public.groups_with_counts
  where id = 'cd111111-1111-1111-1111-111111111111';
  if v_groups <> 1 or v_members <> 2 or v_filled <> 2 then
    raise exception 'anon: grupos % membros % preenchidas %', v_groups, v_members, v_filled;
  end if;
  if exists (
    select 1 from public.groups
    where id = 'cd222222-2222-2222-2222-222222222222'
  ) or exists (
    select 1 from public.group_members
    where group_id = 'cd222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'anon leu o grupo da casa pendente';
  end if;
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', 'c2222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_groups integer;
  v_own integer;
  v_hidden_others integer;
  v_public_filled integer;
  v_hidden_filled integer;
begin
  select count(*) into v_groups from public.groups;
  select count(*)
    into v_own
  from public.group_members
  where group_id = 'cd222222-2222-2222-2222-222222222222'
    and user_id = 'c2222222-2222-2222-2222-222222222222';
  select count(*)
    into v_hidden_others
  from public.group_members
  where group_id = 'cd222222-2222-2222-2222-222222222222'
    and user_id <> 'c2222222-2222-2222-2222-222222222222';
  select filled_spots
    into v_public_filled
  from public.groups_with_counts
  where id = 'cd111111-1111-1111-1111-111111111111';
  select filled_spots
    into v_hidden_filled
  from public.groups_with_counts
  where id = 'cd222222-2222-2222-2222-222222222222';
  if v_groups <> 2 or v_own <> 1 or v_hidden_others <> 0
    or v_public_filled <> 2 or v_hidden_filled <> 1
  then
    raise exception
      'membro: grupos % própria % outros % publica % oculta %',
      v_groups, v_own, v_hidden_others, v_public_filled, v_hidden_filled;
  end if;
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', 'c3333333-3333-3333-3333-333333333333', true);
set local role authenticated;

do $$
declare
  v_groups integer;
  v_hidden integer;
begin
  select count(*) into v_groups from public.groups;
  select count(*)
    into v_hidden
  from public.group_members
  where group_id = 'cd222222-2222-2222-2222-222222222222';
  if v_groups <> 1 or v_hidden <> 0 then
    raise exception 'estranho: grupos % membros ocultos %', v_groups, v_hidden;
  end if;
  perform 1
  from public.groups_with_counts
  where id = 'cd111111-1111-1111-1111-111111111111';
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', 'c1111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
declare
  v_filled integer;
  v_members integer;
begin
  select filled_spots
    into v_filled
  from public.groups_with_counts
  where id = 'cd222222-2222-2222-2222-222222222222';
  select count(*)
    into v_members
  from public.group_members
  where group_id = 'cd222222-2222-2222-2222-222222222222';
  if v_filled <> 2 or v_members <> 2 then
    raise exception 'criador da casa pendente: preenchidas % membros %', v_filled, v_members;
  end if;
end $$;

rollback;
