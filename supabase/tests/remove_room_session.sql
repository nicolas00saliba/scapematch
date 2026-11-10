-- Dono desativa o horário. Outra casa não. Reserva pendente, paga ou
-- cobrança em andamento seguram a linha. Horário desativado não entra
-- em create_group nem em create_group_with_party, não aceita entrada
-- e some da leitura do jogador.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'f1111111-1111-4111-8111-111111111111',
    'dono-remove@example.com',
    '{"display_name":"Dono Remove"}'
  ),
  (
    'f2222222-2222-4222-8222-222222222222',
    'outra-remove@example.com',
    '{"display_name":"Outra Casa"}'
  ),
  (
    'f3333333-3333-4333-8333-333333333333',
    'jogador-remove@example.com',
    '{"display_name":"Jogador Remove"}'
  );

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, asaas_wallet_id
) values
  (
    'f4111111-1111-4111-8111-111111111111',
    'f1111111-1111-4111-8111-111111111111',
    'curitiba',
    'Casa Remove Horario',
    'Centro',
    'Rua do Chip',
    '40',
    '80010040',
    -25.43,
    -49.27,
    5000,
    'cnpj',
    '19000000000191',
    '41900001111',
    'approved',
    'wal_remove_slot_a'
  ),
  (
    'f4222222-2222-4222-8222-222222222222',
    'f2222222-2222-4222-8222-222222222222',
    'curitiba',
    'Casa Nao Remove',
    'Batel',
    'Rua do Outro',
    '41',
    '80010041',
    -25.44,
    -49.28,
    4000,
    'cnpj',
    '19000000000192',
    '41900001112',
    'approved',
    'wal_remove_slot_b'
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'f5111111-1111-4111-8111-111111111111',
    'f4111111-1111-4111-8111-111111111111',
    'Sala do Chip',
    '',
    6,
    2,
    60,
    'medium',
    9000
  ),
  (
    'f5222222-2222-4222-8222-222222222222',
    'f4222222-2222-4222-8222-222222222222',
    'Sala da Outra',
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
    'f6111111-1111-4111-8111-111111111111',
    'f5111111-1111-4111-8111-111111111111',
    '2027-12-01 18:00:00+00',
    'partner_grid'
  ),
  (
    'f6222222-2222-4222-8222-222222222222',
    'f5111111-1111-4111-8111-111111111111',
    '2027-12-02 18:00:00+00',
    'partner_grid'
  ),
  (
    'f6333333-3333-4333-8333-333333333333',
    'f5111111-1111-4111-8111-111111111111',
    '2027-12-03 18:00:00+00',
    'partner_grid'
  ),
  (
    'f6444444-4444-4444-8444-444444444444',
    'f5111111-1111-4111-8111-111111111111',
    '2027-12-04 18:00:00+00',
    'partner_grid'
  ),
  (
    'f6555555-5555-4555-8555-555555555555',
    'f5111111-1111-4111-8111-111111111111',
    '2027-12-05 18:00:00+00',
    'partner_grid'
  );

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    'f7111111-1111-4111-8111-111111111111',
    'curitiba',
    'f4111111-1111-4111-8111-111111111111',
    'f5111111-1111-4111-8111-111111111111',
    'f6222222-2222-4222-8222-222222222222',
    '2027-12-02 18:00:00+00',
    4,
    2,
    9000,
    'f3333333-3333-4333-8333-333333333333'
  ),
  (
    'f7222222-2222-4222-8222-222222222222',
    'curitiba',
    'f4111111-1111-4111-8111-111111111111',
    'f5111111-1111-4111-8111-111111111111',
    'f6333333-3333-4333-8333-333333333333',
    '2027-12-03 18:00:00+00',
    4,
    2,
    9000,
    'f3333333-3333-4333-8333-333333333333'
  ),
  (
    'f7333333-3333-4333-8333-333333333333',
    'curitiba',
    'f4111111-1111-4111-8111-111111111111',
    'f5111111-1111-4111-8111-111111111111',
    'f6444444-4444-4444-8444-444444444444',
    '2027-12-04 18:00:00+00',
    4,
    2,
    9000,
    'f3333333-3333-4333-8333-333333333333'
  );

insert into public.group_members (
  group_id, user_id, display_name, is_creator, attendance, payment_status
) values
  (
    'f7111111-1111-4111-8111-111111111111',
    'f3333333-3333-4333-8333-333333333333',
    'Jogador Remove',
    true,
    'joined',
    'pending'
  ),
  (
    'f7222222-2222-4222-8222-222222222222',
    'f3333333-3333-4333-8333-333333333333',
    'Jogador Remove',
    true,
    'confirmed',
    'paid'
  ),
  (
    'f7333333-3333-4333-8333-333333333333',
    'f3333333-3333-4333-8333-333333333333',
    'Jogador Remove',
    true,
    'cancelled',
    'released'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps
) values (
  'f8111111-1111-4111-8111-111111111111',
  'f7333333-3333-4333-8333-333333333333',
  'f3333333-3333-4333-8333-333333333333',
  'f4111111-1111-4111-8111-111111111111',
  9000,
  'PIX',
  'pending',
  'pay_remove_slot',
  'idem-remove-slot-pending',
  1000
);

begin;
select set_config(
  'request.jwt.claim.sub',
  'f2222222-2222-4222-8222-222222222222',
  true
);
set local role authenticated;

do $$
begin
  perform public.remove_room_session('f6111111-1111-4111-8111-111111111111');
  raise exception 'outra casa removeu o horário';
exception
  when insufficient_privilege then
    if sqlerrm <> 'not owner' then
      raise;
    end if;
end $$;

rollback;

do $$
begin
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'f6111111-1111-4111-8111-111111111111'
  ) is not null then
    raise exception 'a outra casa gravou cancelled_at';
  end if;
end $$;

begin;
select set_config(
  'request.jwt.claim.sub',
  'f1111111-1111-4111-8111-111111111111',
  true
);
set local role authenticated;

do $$
declare
  v_id text;
begin
  foreach v_id in array array[
    'f6222222-2222-4222-8222-222222222222',
    'f6333333-3333-4333-8333-333333333333',
    'f6444444-4444-4444-8444-444444444444'
  ]
  loop
    begin
      perform public.remove_room_session(v_id::uuid);
      raise exception 'removeu horário com reserva %', v_id;
    exception
      when raise_exception then
        if sqlerrm <> 'Esse horário já tem reserva' then
          raise;
        end if;
    end;
  end loop;
end $$;

select public.remove_room_session('f6111111-1111-4111-8111-111111111111');

reset role;
commit;

begin;
select set_config(
  'request.jwt.claim.sub',
  'f1111111-1111-4111-8111-111111111111',
  true
);
set local role authenticated;

do $$
begin
  delete from public.room_sessions
  where id = 'f6555555-5555-4555-8555-555555555555';
  raise exception 'delete direto passou';
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  update public.room_sessions
    set cancelled_at = pg_catalog.now()
  where id = 'f6555555-5555-4555-8555-555555555555';
  raise exception 'update direto passou';
exception
  when insufficient_privilege then
    null;
end $$;

rollback;

do $$
begin
  delete from public.room_sessions
  where id = 'f6555555-5555-4555-8555-555555555555';
  raise exception 'superuser apagou o horário';
exception
  when insufficient_privilege then
    if sqlerrm <> 'use remove_room_session' then
      raise;
    end if;
end $$;

do $$
declare
  v_at timestamptz;
begin
  select cancelled_at
    into v_at
  from public.room_sessions
  where id = 'f6111111-1111-4111-8111-111111111111';
  if v_at is null then
    raise exception 'o dono não desativou o horário';
  end if;
  if not exists (
    select 1
    from public.room_sessions
    where id = 'f6111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'a linha do horário foi apagada';
  end if;
  if (
    select cancelled_at
    from public.room_sessions
    where id = 'f6555555-5555-4555-8555-555555555555'
  ) is not null then
    raise exception 'update direto desativou o horário';
  end if;
end $$;

begin;
select set_config(
  'request.jwt.claim.sub',
  'f3333333-3333-4333-8333-333333333333',
  true
);
set local role authenticated;

do $$
begin
  perform public.create_group(
    'f6111111-1111-4111-8111-111111111111',
    4,
    ''
  );
  raise exception 'jogador reservou horário removido';
exception
  when others then
    if sqlstate <> 'PT404' then
      raise;
    end if;
end $$;

do $$
begin
  if exists (
    select 1
    from public.room_sessions
    where id = 'f6111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'jogador ainda lê o horário removido';
  end if;
  if not exists (
    select 1
    from public.room_sessions
    where id = 'f6555555-5555-4555-8555-555555555555'
  ) then
    raise exception 'jogador deixou de ler horário aberto';
  end if;
end $$;

rollback;

begin;
set local role anon;

do $$
begin
  perform public.remove_room_session('f6555555-5555-4555-8555-555555555555');
  raise exception 'anon removeu horário';
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  if exists (
    select 1
    from public.room_sessions
    where id = 'f6111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'anon ainda lê o horário removido';
  end if;
end $$;

rollback;

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'f5999999-9999-4999-8999-999999999999',
  'f4111111-1111-4111-8111-111111111111',
  'Sala Cascade',
  '',
  4,
  2,
  60,
  'easy',
  8000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'f6999999-9999-4999-8999-999999999999',
  'f5999999-9999-4999-8999-999999999999',
  '2027-12-06 18:00:00+00',
  'partner_grid'
);

delete from public.rooms
where id = 'f5999999-9999-4999-8999-999999999999';

do $$
begin
  if exists (
    select 1
    from public.room_sessions
    where id = 'f6999999-9999-4999-8999-999999999999'
  ) then
    raise exception 'apagar a sala não levou o horário junto';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'f3444444-4444-4444-8444-444444444444',
    'amigo-remove@example.com',
    '{"display_name":"Amigo Remove"}'
  ),
  (
    'f3555555-5555-4555-8555-555555555555',
    'outro-remove@example.com',
    '{"display_name":"Outro Remove"}'
  );

insert into public.crews (id, name, created_by)
values (
  'f9000000-0000-4000-8000-000000000001',
  'Turma do Chip',
  'f3333333-3333-4333-8333-333333333333'
);

insert into public.crew_members (crew_id, user_id, status)
values
  (
    'f9000000-0000-4000-8000-000000000001',
    'f3333333-3333-4333-8333-333333333333',
    'accepted'
  ),
  (
    'f9000000-0000-4000-8000-000000000001',
    'f3444444-4444-4444-8444-444444444444',
    'accepted'
  ),
  (
    'f9000000-0000-4000-8000-000000000001',
    'f3555555-5555-4555-8555-555555555555',
    'accepted'
  );

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'f6666666-6666-4666-8666-666666666666',
  'f5111111-1111-4111-8111-111111111111',
  '2027-12-07 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'f7444444-4444-4444-8444-444444444444',
  'curitiba',
  'f4111111-1111-4111-8111-111111111111',
  'f5111111-1111-4111-8111-111111111111',
  'f6666666-6666-4666-8666-666666666666',
  '2027-12-07 18:00:00+00',
  4,
  2,
  9000,
  'f3333333-3333-4333-8333-333333333333'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, attendance, payment_status
) values (
  'f7444444-4444-4444-8444-444444444444',
  'f3333333-3333-4333-8333-333333333333',
  'Jogador Remove',
  true,
  'joined',
  'pending'
);

update public.room_sessions
  set cancelled_at = pg_catalog.now()
where id = 'f6666666-6666-4666-8666-666666666666';

begin;
select set_config(
  'request.jwt.claim.sub',
  'f3333333-3333-4333-8333-333333333333',
  true
);
set local role authenticated;

do $$
begin
  perform public.create_group_with_party(
    'f6111111-1111-4111-8111-111111111111',
    1,
    '',
    array['f3444444-4444-4444-8444-444444444444']::uuid[]
  );
  raise exception 'jogador criou grupo com amigos no horário removido';
exception
  when others then
    if sqlstate <> 'PT404' or sqlerrm <> 'unknown session' then
      raise;
    end if;
end $$;

do $$
begin
  if exists (
    select 1
    from public.groups
    where session_id = 'f6111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'horário removido ganhou grupo com amigos';
  end if;
  if exists (
    select 1
    from public.group_members
    where user_id = 'f3444444-4444-4444-8444-444444444444'
  ) then
    raise exception 'amigo ficou pendente no horário removido';
  end if;
end $$;

rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  'f3555555-5555-4555-8555-555555555555',
  true
);
set local role authenticated;

do $$
begin
  perform public.join_group('f7444444-4444-4444-8444-444444444444');
  raise exception 'jogador entrou no grupo da sessão desativada';
exception
  when others then
    if sqlstate <> 'PT404' or sqlerrm <> 'unknown session' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.join_group_with_party(
    'f7444444-4444-4444-8444-444444444444',
    array['f3444444-4444-4444-8444-444444444444']::uuid[]
  );
  raise exception 'turma entrou no grupo da sessão desativada';
exception
  when others then
    if sqlstate <> 'PT404' or sqlerrm <> 'unknown session' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.join_waitlist('f7444444-4444-4444-8444-444444444444');
  raise exception 'jogador entrou na fila da sessão desativada';
exception
  when others then
    if sqlstate <> 'PT404' or sqlerrm <> 'unknown session' then
      raise;
    end if;
end $$;

do $$
begin
  if (
    select count(*)
    from public.group_members
    where group_id = 'f7444444-4444-4444-8444-444444444444'
  ) <> 1 then
    raise exception 'sessão desativada ganhou membro';
  end if;
  if exists (
    select 1
    from public.waitlist
    where group_id = 'f7444444-4444-4444-8444-444444444444'
  ) then
    raise exception 'sessão desativada ganhou fila';
  end if;
end $$;

rollback;
