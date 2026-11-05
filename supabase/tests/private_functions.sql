-- As funções de policy saíram de public. O anon continua lendo o que é
-- público e não chama o nome antigo, que é o caminho de /rest/v1/rpc.
-- Quem está logado ainda cria um grupo e entra nele.

\set ON_ERROR_STOP on

do $$
declare
  v_name text;
  v_helper text;
begin
  foreach v_name in array array[
    'is_admin()',
    'owns_venue(uuid)',
    'venue_is_visible(uuid)',
    'room_photo_object_allowed(text)',
    'is_group_member(uuid)',
    'group_is_readable(uuid)'
  ]
  loop
    if to_regprocedure('public.' || v_name) is not null then
      raise exception 'ainda exposta em public: %', v_name;
    end if;
    if to_regprocedure('private.' || v_name) is null then
      raise exception 'não foi para private: %', v_name;
    end if;
    if not has_function_privilege('anon', 'private.' || v_name, 'execute')
      or not has_function_privilege('authenticated', 'private.' || v_name, 'execute')
    then
      raise exception 'policy sem execute: %', v_name;
    end if;
  end loop;

  if to_regprocedure('public.venue_link_status(uuid)') is not null
    or to_regprocedure('private.venue_link_status(uuid)') is null
    or has_function_privilege('anon', 'private.venue_link_status(uuid)', 'execute')
    or has_function_privilege(
      'authenticated', 'private.venue_link_status(uuid)', 'execute'
    )
  then
    raise exception 'venue_link_status ainda é executável pela API';
  end if;

  foreach v_helper in array array[
    'handle_new_user()',
    'profiles_guard()',
    'venues_guard()',
    'venues_normalize()',
    'venue_claims_guard()',
    'group_filled_spots(uuid)',
    'profile_display_name(uuid)',
    'user_has_overlap(uuid, timestamptz, integer, uuid)',
    'users_are_friends(uuid, uuid)',
    'post_app_notice(uuid, text, text, text, uuid, text)',
    'offer_waitlist(uuid)',
    'saved_cards_guard()',
    'saved_cards_limit()'
  ]
  loop
    if to_regprocedure('public.' || v_helper) is not null
      or to_regprocedure('private.' || v_helper) is null
      or has_function_privilege('anon', 'private.' || v_helper, 'execute')
      or has_function_privilege('authenticated', 'private.' || v_helper, 'execute')
    then
      raise exception 'auxiliar ainda exposta: %', v_helper;
    end if;
  end loop;

  if coalesce(current_setting('pgrst.db_schemas', true), 'public')
    like '%private%'
  then
    raise exception 'o schema private entrou na API';
  end if;

  if has_schema_privilege('anon', 'private', 'usage')
    or has_schema_privilege('public', 'private', 'usage')
  then
    raise exception 'anon ou public ainda tem usage no schema private';
  end if;
  if has_schema_privilege('authenticated', 'private', 'usage')
    or not has_schema_privilege('service_role', 'private', 'usage')
  then
    raise exception 'usage de private não ficou só no service_role';
  end if;
end $$;

insert into public.room_photos (room_id, storage_path)
values
  (
    'cc111111-1111-1111-1111-111111111111',
    'ca111111-1111-1111-1111-111111111111/capa.jpg'
  ),
  (
    'cc222222-2222-2222-2222-222222222222',
    'cb222222-2222-2222-2222-222222222222/capa.jpg'
  );

insert into storage.objects (bucket_id, name)
values
  ('room-photos', 'ca111111-1111-1111-1111-111111111111/capa.jpg'),
  ('room-photos', 'cb222222-2222-2222-2222-222222222222/capa.jpg');

begin;
set local role anon;

do $$
begin
  begin
    perform public.is_admin();
    raise exception 'anon chamou public.is_admin';
  exception
    when undefined_function then
      null;
  end;
  begin
    perform public.owns_venue('ca111111-1111-1111-1111-111111111111');
    raise exception 'anon chamou public.owns_venue';
  exception
    when undefined_function then
      null;
  end;
  begin
    perform public.venue_is_visible('ca111111-1111-1111-1111-111111111111');
    raise exception 'anon chamou public.venue_is_visible';
  exception
    when undefined_function then
      null;
  end;
  begin
    perform public.room_photo_object_allowed('x');
    raise exception 'anon chamou public.room_photo_object_allowed';
  exception
    when undefined_function then
      null;
  end;
  begin
    perform public.is_group_member('cd111111-1111-1111-1111-111111111111');
    raise exception 'anon chamou public.is_group_member';
  exception
    when undefined_function then
      null;
  end;
  begin
    perform public.group_is_readable('cd111111-1111-1111-1111-111111111111');
    raise exception 'anon chamou public.group_is_readable';
  exception
    when undefined_function then
      null;
  end;

  begin
    perform private.is_admin();
    raise exception 'anon chamou private.is_admin pelo nome';
  exception
    when insufficient_privilege then
      null;
  end;
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
  if not exists (
    select 1 from storage.objects
    where name = 'ca111111-1111-1111-1111-111111111111/capa.jpg'
  ) or exists (
    select 1 from storage.objects
    where name = 'cb222222-2222-2222-2222-222222222222/capa.jpg'
  ) then
    raise exception 'anon não leu só o arquivo público';
  end if;
end $$;

rollback;

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ce111111-1111-1111-1111-111111111111',
  'cc111111-1111-1111-1111-111111111111',
  '2027-03-15 18:00:00+00',
  'partner_grid'
);

update public.venues
set asaas_wallet_id = 'wal_teste_grupos'
where id = 'ca111111-1111-1111-1111-111111111111'
  and asaas_wallet_id is null;

create temp table created_group (id uuid);
grant all on created_group to authenticated;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c2222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;
insert into created_group
select public.create_group(
  'ce111111-1111-1111-1111-111111111111',
  4,
  ''
);

reset role;
select set_config(
  'request.jwt.claim.sub',
  'c3333333-3333-3333-3333-333333333333',
  true
);
set local role authenticated;
select public.join_group(id) from created_group;

reset role;

do $$
declare
  v_members integer;
  v_filled integer;
begin
  select count(*)
    into v_members
  from public.group_members m
  join created_group c on c.id = m.group_id
  where m.attendance <> 'cancelled';
  select filled_spots
    into v_filled
  from public.groups_with_counts g
  join created_group c on c.id = g.id;
  if v_members <> 2 or v_filled <> 2 then
    raise exception 'criar/entrar: membros % preenchidas %', v_members, v_filled;
  end if;
end $$;

commit;
