-- Dono em aal1 ainda remove horário e cancela grupo da própria casa.
-- Admin aal2 faz o mesmo numa casa que não é dele. Admin aal1 nessa
-- casa recebe mfa obrigatorio. Usuário qualquer recebe not owner.
-- O job duplicates-sql sobe postgres:16 sem a extensão pgtap, então
-- estes casos entram no harness SQL que o CI já executa.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'c0111111-1111-4111-8111-111111111111',
    'dono-aal2@example.com',
    '{"display_name":"Dono Aal"}'
  ),
  (
    'c0222222-2222-4222-8222-222222222222',
    'admin-aal2@example.com',
    '{"display_name":"Admin Aal"}'
  ),
  (
    'c0333333-3333-4333-8333-333333333333',
    'qualquer-aal2@example.com',
    '{"display_name":"Qualquer Aal"}'
  );

insert into public.admins (user_id)
values ('c0222222-2222-4222-8222-222222222222');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, asaas_wallet_id
) values (
  'c0411111-1111-4111-8111-111111111111',
  'c0111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa do Aal',
  'Centro',
  'Rua do Fator',
  '42',
  '80010042',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '19000000000193',
  '41900001113',
  'approved',
  'wal_aal2_venue'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'c0511111-1111-4111-8111-111111111111',
  'c0411111-1111-4111-8111-111111111111',
  'Sala do Aal',
  '',
  6,
  2,
  60,
  'medium',
  9000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  (
    'c0611111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-11 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0622222-2222-4222-8222-222222222222',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-12 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0633333-3333-4333-8333-333333333333',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-13 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0644444-4444-4444-8444-444444444444',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-14 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0655555-5555-4555-8555-555555555555',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-15 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0666666-6666-4666-8666-666666666666',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-16 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0677777-7777-4777-8777-777777777777',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-17 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0688888-8888-4888-8888-888888888888',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-18 18:00:00+00',
    'partner_grid'
  ),
  (
    'c0699999-9999-4999-8999-999999999999',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-19 18:00:00+00',
    'partner_grid'
  ),
  (
    'c06aaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-20 18:00:00+00',
    'partner_grid'
  ),
  (
    'c06bbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-21 18:00:00+00',
    'partner_grid'
  ),
  (
    'c06ccccc-cccc-4ccc-8ccc-cccccccccccc',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-22 18:00:00+00',
    'partner_grid'
  );

update public.room_sessions
  set cancelled_at = pg_catalog.now()
where id = 'c0699999-9999-4999-8999-999999999999';

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    'c0711111-1111-4111-8111-111111111111',
    'curitiba',
    'c0411111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    'c0655555-5555-4555-8555-555555555555',
    '2027-12-15 18:00:00+00',
    4,
    2,
    9000,
    'c0333333-3333-4333-8333-333333333333'
  ),
  (
    'c0722222-2222-4222-8222-222222222222',
    'curitiba',
    'c0411111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    'c0666666-6666-4666-8666-666666666666',
    '2027-12-16 18:00:00+00',
    4,
    2,
    9000,
    'c0333333-3333-4333-8333-333333333333'
  ),
  (
    'c0733333-3333-4333-8333-333333333333',
    'curitiba',
    'c0411111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    'c0677777-7777-4777-8777-777777777777',
    '2027-12-17 18:00:00+00',
    4,
    2,
    9000,
    'c0333333-3333-4333-8333-333333333333'
  ),
  (
    'c0744444-4444-4444-8444-444444444444',
    'curitiba',
    'c0411111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    'c0688888-8888-4888-8888-888888888888',
    '2027-12-18 18:00:00+00',
    4,
    2,
    9000,
    'c0333333-3333-4333-8333-333333333333'
  ),
  (
    'c0755555-5555-4555-8555-555555555555',
    'curitiba',
    'c0411111-1111-4111-8111-111111111111',
    'c0511111-1111-4111-8111-111111111111',
    'c06ccccc-cccc-4ccc-8ccc-cccccccccccc',
    '2027-12-22 18:00:00+00',
    4,
    2,
    9000,
    'c0333333-3333-4333-8333-333333333333'
  );

do $$
begin
  if has_function_privilege('anon', 'private.admin_require()', 'execute')
    or has_function_privilege(
      'authenticated', 'private.admin_require()', 'execute'
    )
  then
    raise exception 'admin_require voltou a ser executavel';
  end if;
  if not has_function_privilege('anon', 'private.is_admin_aal2()', 'execute')
    or not has_function_privilege(
      'authenticated', 'private.is_admin_aal2()', 'execute'
    )
  then
    raise exception 'policy sem execute em is_admin_aal2';
  end if;
end $$;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
select public.remove_room_session('c0611111-1111-4111-8111-111111111111');
select public.house_cancel_group(
  'c0711111-1111-4111-8111-111111111111',
  'Cancelada pelo dono'
);
reset role;
do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c0611111-1111-4111-8111-111111111111'
  ) is null then
    raise exception 'dono aal1 nao removeu o horario';
  end if;
  if (
    select cancelled_at
    from public.groups
    where id = 'c0711111-1111-4111-8111-111111111111'
  ) is null then
    raise exception 'dono aal1 nao cancelou o grupo';
  end if;
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c0655555-5555-4555-8555-555555555555'
  ) is null then
    raise exception 'dono aal1 nao desativou a sessao do grupo';
  end if;
end $$;
commit;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.remove_room_session('c0622222-2222-4222-8222-222222222222');
select public.house_cancel_group(
  'c0722222-2222-4222-8222-222222222222',
  'Cancelada pelo admin'
);
reset role;
do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c0622222-2222-4222-8222-222222222222'
  ) is null then
    raise exception 'admin aal2 nao removeu horario de outra casa';
  end if;
  if (
    select cancelled_at
    from public.groups
    where id = 'c0722222-2222-4222-8222-222222222222'
  ) is null then
    raise exception 'admin aal2 nao cancelou grupo de outra casa';
  end if;
end $$;
commit;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.remove_room_session('c0633333-3333-4333-8333-333333333333');
  raise exception 'admin aal1 removeu horario de outra casa';
exception
  when insufficient_privilege then
    if sqlerrm <> 'mfa obrigatorio' then
      raise;
    end if;
end $$;
do $$
begin
  perform public.house_cancel_group('c0733333-3333-4333-8333-333333333333');
  raise exception 'admin aal1 cancelou grupo de outra casa';
exception
  when insufficient_privilege then
    if sqlerrm <> 'mfa obrigatorio' then
      raise;
    end if;
end $$;
reset role;
do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c0633333-3333-4333-8333-333333333333'
  ) is not null then
    raise exception 'admin aal1 gravou cancelled_at no horario';
  end if;
  if (
    select cancelled_at
    from public.groups
    where id = 'c0733333-3333-4333-8333-333333333333'
  ) is not null then
    raise exception 'admin aal1 gravou cancelled_at no grupo';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0333333-3333-4333-8333-333333333333',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
begin
  perform public.remove_room_session('c0644444-4444-4444-8444-444444444444');
  raise exception 'usuario qualquer removeu horario';
exception
  when insufficient_privilege then
    if sqlerrm <> 'not owner' then
      raise;
    end if;
end $$;
do $$
begin
  perform public.house_cancel_group('c0744444-4444-4444-8444-444444444444');
  raise exception 'usuario qualquer cancelou grupo';
exception
  when insufficient_privilege then
    if sqlerrm <> 'not owner' then
      raise;
    end if;
end $$;
reset role;
do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c0644444-4444-4444-8444-444444444444'
  ) is not null
    or (
      select cancelled_at
      from public.groups
      where id = 'c0744444-4444-4444-8444-444444444444'
    ) is not null
  then
    raise exception 'usuario qualquer alterou casa alheia';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if not exists (
    select 1
    from public.room_sessions
    where id = 'c0699999-9999-4999-8999-999999999999'
  ) then
    raise exception 'dono aal1 deixou de ler horario cancelado';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
begin
  if not exists (
    select 1
    from public.room_sessions
    where id = 'c0699999-9999-4999-8999-999999999999'
  ) then
    raise exception 'admin aal2 nao leu horario cancelado de outra casa';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if exists (
    select 1
    from public.room_sessions
    where id = 'c0699999-9999-4999-8999-999999999999'
  ) then
    raise exception 'admin aal1 leu horario cancelado de outra casa';
  end if;
  if not exists (
    select 1
    from public.room_sessions
    where id = 'c06aaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) then
    raise exception 'admin aal1 deixou de ler horario aberto';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0333333-3333-4333-8333-333333333333',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if exists (
    select 1
    from public.room_sessions
    where id = 'c0699999-9999-4999-8999-999999999999'
  ) then
    raise exception 'usuario qualquer leu horario cancelado';
  end if;
  if not exists (
    select 1
    from public.room_sessions
    where id = 'c06aaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) then
    raise exception 'usuario qualquer deixou de ler horario aberto';
  end if;
end $$;
do $$
begin
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (
    'c06ddddd-dddd-4ddd-8ddd-dddddddddddd',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-23 18:00:00+00',
    'partner_grid'
  );
  raise exception 'usuario qualquer inseriu horario';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'c06eeee1-eeee-4eee-8eee-eeeeeeeeeee1',
  'c0511111-1111-4111-8111-111111111111',
  '2027-12-24 18:00:00+00',
  'partner_grid'
);
reset role;
do $$
begin
  if not exists (
    select 1
    from public.room_sessions
    where id = 'c06eeee1-eeee-4eee-8eee-eeeeeeeeeee1'
  ) then
    raise exception 'dono aal1 nao inseriu horario';
  end if;
end $$;
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'c06eeee2-eeee-4eee-8eee-eeeeeeeeeee2',
  'c0511111-1111-4111-8111-111111111111',
  '2027-12-25 18:00:00+00',
  'partner_grid'
);
rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'c0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (
    'c06eeee3-eeee-4eee-8eee-eeeeeeeeeee3',
    'c0511111-1111-4111-8111-111111111111',
    '2027-12-26 18:00:00+00',
    'partner_grid'
  );
  raise exception 'admin aal1 inseriu horario em outra casa';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
insert into public.admins (user_id)
values ('c0111111-1111-4111-8111-111111111111');
select set_config(
  'request.jwt.claim.sub',
  'c0111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
select public.remove_room_session('c06bbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select public.house_cancel_group('c0755555-5555-4555-8555-555555555555');
reset role;
do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'c06bbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ) is null
    or (
      select cancelled_at
      from public.groups
      where id = 'c0755555-5555-4555-8555-555555555555'
    ) is null
  then
    raise exception 'dono admin em aal1 perdeu a propria casa';
  end if;
end $$;
rollback;
