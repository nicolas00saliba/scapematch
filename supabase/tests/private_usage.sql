-- authenticated não entra no schema private. Os quatro wrappers do
-- Parceiro continuam no RPC de public, como security definer, e negam
-- quem não é dono ou admin. anon segue lendo o que é público. Cartão
-- não abre para authenticated.

\set ON_ERROR_STOP on

do $$
declare
  v_name text;
  v_left text;
begin
  if has_schema_privilege('authenticated', 'private', 'usage')
    or has_schema_privilege('anon', 'private', 'usage')
    or has_schema_privilege('public', 'private', 'usage')
    or not has_schema_privilege('service_role', 'private', 'usage')
  then
    raise exception 'usage de private não ficou só no service_role';
  end if;

  foreach v_name in array array[
    'check_venue_duplicates(text, text, text, text, text)',
    'request_venue_claim(uuid, text, uuid)',
    'review_venue(uuid, text, uuid)',
    'review_venue_claim(uuid, text)'
  ]
  loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.oid = to_regprocedure('public.' || v_name)
        and p.prosecdef
        and 'search_path=""' = any (p.proconfig)
    ) then
      raise exception 'wrapper sem security definer ou search_path vazio: %', v_name;
    end if;
    if not has_function_privilege('authenticated', 'public.' || v_name, 'execute')
      or has_function_privilege('anon', 'public.' || v_name, 'execute')
    then
      raise exception 'execute do wrapper mudou: %', v_name;
    end if;
  end loop;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('accept_waitlist', 'set_my_username')
      and p.prosecdef
  ) or exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('profiles_guard', 'users_are_friends')
      and p.prosecdef
  ) or not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('venues_guard', 'venue_claims_guard')
      and p.prosecdef
    having count(*) = 2
  ) then
    raise exception 'security das funções do inventário mudou';
  end if;

  select string_agg(n.nspname || '.' || p.proname, ', ')
    into v_left
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosecdef
    and not ('search_path=""' = any (coalesce(p.proconfig, array[]::text[])));
  if v_left is not null then
    raise exception 'security definer ainda sem search_path vazio: %', v_left;
  end if;

  if has_function_privilege(
      'authenticated', 'public.claim_card_tokenize_attempt(uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated', 'private.claim_card_tokenize_attempt(uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated',
      'public.insert_saved_card(uuid, text, text, text, text, uuid)',
      'execute'
    )
    or has_function_privilege(
      'authenticated',
      'private.insert_saved_card(uuid, text, text, text, text, uuid)',
      'execute'
    )
    or has_function_privilege(
      'authenticated', 'public.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated', 'private.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege('authenticated', 'private.card_token_key()', 'execute')
  then
    raise exception 'authenticated executa função de cartão';
  end if;
end $$;

begin;
select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;

do $$
declare
  v_claim uuid;
begin
  begin
    perform private.check_venue_duplicates(
      '12.345.678/0001-95', 'Ninja', 'curitiba', '80010000', '120'
    );
    raise exception 'authenticated entrou em private.check_venue_duplicates';
  exception
    when insufficient_privilege then
      null;
  end;

  if not exists (
    select 1
    from public.check_venue_duplicates(
      '12.345.678/0001-95', 'Ninja', 'curitiba', '80010000', '120'
    )
    where conflict_type = 'documento'
  ) then
    raise exception 'quem não tem casa não viu o documento repetido';
  end if;

  select public.request_venue_claim(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Quero esta casa.',
    null
  ) into v_claim;
  if v_claim is null then
    raise exception 'reivindicação do parceiro não foi criada';
  end if;

  begin
    perform public.review_venue(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'approved',
      null
    );
    raise exception 'quem não é admin aprovou a casa';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    perform count(*) from public.crews;
    perform count(*) from public.venues where status = 'approved';
  exception
    when insufficient_privilege then
      raise exception 'policy passou a exigir usage em private' using errcode = '42501';
  end;
end $$;

rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
set local role authenticated;

do $$
begin
  if exists (
    select 1
    from public.check_venue_duplicates(
      '12.345.678/0001-95', 'Outra', 'curitiba', '01310000', '999'
    )
    where conflict_type = 'documento'
  ) then
    raise exception 'dono com casa ativa enumerou documento';
  end if;
  begin
    perform public.request_venue_claim(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'A casa já é minha',
      null
    );
    raise exception 'dona reivindicou a própria casa';
  exception
    when sqlstate 'P0002' then
      null;
  end;
  update public.venues
    set neighborhood = 'Centro Novo', status = 'rejected'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
end $$;

reset role;

do $$
begin
  if not exists (
    select 1
    from public.venues
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and neighborhood = 'Centro Novo'
      and status = 'approved'
  ) then
    raise exception 'dono não gravou o bairro, ou mudou o status';
  end if;
end $$;

select set_config(
  'request.jwt.claim.sub',
  '33333333-3333-3333-3333-333333333333',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;

do $$
declare
  v_reviewed text;
begin
  select reviewed.status
    into v_reviewed
  from public.review_venue(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'approved',
    null
  ) as reviewed;
  if v_reviewed <> 'approved' then
    raise exception 'admin não aprovou a casa pendente';
  end if;
  update public.venues
    set status = 'rejected'
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
end $$;

reset role;

do $$
begin
  if not exists (
    select 1
    from public.venues
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      and status = 'rejected'
  ) then
    raise exception 'admin não mudou o status pela tabela';
  end if;
end $$;

rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c3333333-3333-3333-3333-333333333333',
  true
);
set local role authenticated;

do $$
declare
  v_name text;
begin
  select public.set_my_username('estranho_rls') into v_name;
  if v_name <> 'estranho_rls' then
    raise exception 'username não voltou: %', v_name;
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
update public.profiles
  set asaas_customer_id = 'cus_teste'
  where id = 'c3333333-3333-3333-3333-333333333333';

select set_config(
  'request.jwt.claim.sub',
  'c3333333-3333-3333-3333-333333333333',
  true
);
set local role authenticated;
update public.profiles
  set display_name = 'Nome Novo', asaas_customer_id = 'cus_hack'
  where id = 'c3333333-3333-3333-3333-333333333333';
reset role;

do $$
begin
  if not exists (
    select 1
    from public.profiles
    where id = 'c3333333-3333-3333-3333-333333333333'
      and username = 'estranho_rls'
      and display_name = 'Nome Novo'
      and asaas_customer_id = 'cus_teste'
  ) then
    raise exception 'profiles_guard ou set_my_username mudou o perfil errado';
  end if;
end $$;

insert into public.friendships (requester_id, addressee_id, status)
values (
  'c2222222-2222-2222-2222-222222222222',
  'c3333333-3333-3333-3333-333333333333',
  'accepted'
);

select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;

do $$
declare
  v_crew uuid;
begin
  select public.create_crew(
    'Turma teste',
    '',
    array['c3333333-3333-3333-3333-333333333333']::uuid[]
  ) into v_crew;
  if v_crew is null then
    raise exception 'create_crew não viu a amizade';
  end if;
end $$;

reset role;

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ce888888-8888-8888-8888-888888888888',
  'cc111111-1111-1111-1111-111111111111',
  '2028-06-01 18:00:00+00',
  'partner_grid'
);

create temp table opened_group (id uuid);
grant all on opened_group to authenticated;

select set_config(
  'request.jwt.claim.sub',
  'c4444444-4444-4444-4444-444444444444',
  true
);
set local role authenticated;
insert into opened_group
select public.create_group(
  'ce888888-8888-8888-8888-888888888888',
  4,
  ''
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;
select public.join_waitlist(id) from opened_group;
select public.accept_waitlist(id) from opened_group;

reset role;

do $$
declare
  v_members integer;
begin
  select count(*)
    into v_members
  from public.group_members m
  join opened_group g on g.id = m.group_id
  where m.attendance <> 'cancelled';
  if v_members <> 2 then
    raise exception 'accept_waitlist não sentou a pessoa: %', v_members;
  end if;
end $$;

rollback;

begin;
set local role anon;

do $$
begin
  if not exists (
    select 1 from public.venues
    where id = 'ca111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.venues
    where id = 'cb222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'anon não leu só a casa aprovada';
  end if;
  if not exists (
    select 1 from public.rooms
    where id = 'cc111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.rooms
    where id = 'cc222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'anon não leu só a sala da casa aprovada';
  end if;
  if not exists (
    select 1 from public.groups_with_counts
    where id = 'cd111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.groups_with_counts
    where id = 'cd222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'anon não leu só o grupo público';
  end if;
  if not exists (
    select 1 from public.room_photos
    where room_id = 'cc111111-1111-1111-1111-111111111111'
  ) or exists (
    select 1 from public.room_photos
    where room_id = 'cc222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'anon não leu só a foto da sala pública';
  end if;
end $$;

rollback;
