-- Só datas e horários livres. Exclui passado, a janela de 1 h,
-- reservado (grupo ativo) e removido (cancelled_at). Grupo cancelado
-- devolve o horário. O dia é America/Sao_Paulo. Anon lê a casa
-- aprovada e não lê casa pendente nem casa de teste.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'a1e11111-1111-4111-8111-111111111111',
  'dono-agenda@example.com',
  '{"display_name":"Dono Agenda"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, pagbank_account_id
) values
  (
    'a1e41111-1111-4111-8111-111111111111',
    'a1e11111-1111-4111-8111-111111111111',
    'curitiba',
    'Casa Agenda Livre',
    'Centro',
    'Rua do Dia',
    '70',
    '80010070',
    -25.43,
    -49.27,
    5000,
    'cnpj',
    '19000000000701',
    '41900007701',
    'approved',
    'wal_open_schedule_a'
  ),
  (
    'a1e42222-2222-4222-8222-222222222222',
    'a1e11111-1111-4111-8111-111111111111',
    'curitiba',
    'Casa Agenda Pendente',
    'Batel',
    'Rua Fechada',
    '71',
    '80010071',
    -25.44,
    -49.28,
    4000,
    'cnpj',
    '19000000000702',
    '41900007702',
    'pending',
    'wal_open_schedule_b'
  ),
  (
    'a1e43333-3333-4333-8333-333333333333',
    'a1e11111-1111-4111-8111-111111111111',
    'curitiba',
    'Casa Agenda Teste',
    'Centro',
    'Rua Fantasma',
    '72',
    '80010072',
    -25.45,
    -49.29,
    4000,
    'cnpj',
    '19000000000703',
    '41900007703',
    'approved',
    'wal_open_schedule_c'
  );

update public.venues
set is_test = true
where id = 'a1e43333-3333-4333-8333-333333333333';

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'a1e51111-1111-4111-8111-111111111111',
    'a1e41111-1111-4111-8111-111111111111',
    'Sala Alfa',
    '',
    6, 2, 60, 'medium', 9000
  ),
  (
    'a1e52222-2222-4222-8222-222222222222',
    'a1e41111-1111-4111-8111-111111111111',
    'Sala Beta',
    '',
    6, 2, 60, 'medium', 9000
  ),
  (
    'a1e53333-3333-4333-8333-333333333333',
    'a1e42222-2222-4222-8222-222222222222',
    'Sala Pendente',
    '',
    6, 2, 60, 'medium', 9000
  ),
  (
    'a1e54444-4444-4444-8444-444444444444',
    'a1e43333-3333-4333-8333-333333333333',
    'Sala Fantasma',
    '',
    6, 2, 60, 'medium', 9000
  );

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  (
    'a1e61111-1111-4111-8111-111111111111',
    'a1e51111-1111-4111-8111-111111111111',
    timestamptz '2027-06-15 17:00:00+00',
    'partner_grid'
  ),
  (
    'a1e62222-2222-4222-8222-222222222222',
    'a1e52222-2222-4222-8222-222222222222',
    timestamptz '2027-06-15 21:00:00+00',
    'integrated'
  ),
  (
    'a1e63333-3333-4333-8333-333333333333',
    'a1e51111-1111-4111-8111-111111111111',
    timestamptz '2027-06-16 17:00:00+00',
    'partner_grid'
  ),
  (
    'a1e64444-4444-4444-8444-444444444444',
    'a1e51111-1111-4111-8111-111111111111',
    timestamptz '2027-06-17 17:00:00+00',
    'partner_grid'
  ),
  (
    'a1e65555-5555-4555-8555-555555555555',
    'a1e52222-2222-4222-8222-222222222222',
    timestamptz '2027-06-18 17:00:00+00',
    'partner_grid'
  ),
  (
    'a1e66666-6666-4666-8666-666666666666',
    'a1e51111-1111-4111-8111-111111111111',
    pg_catalog.now() - interval '3 hours',
    'partner_grid'
  ),
  (
    'a1e67777-7777-4777-8777-777777777777',
    'a1e51111-1111-4111-8111-111111111111',
    pg_catalog.now() + interval '1 hour',
    'partner_grid'
  ),
  (
    'a1e68888-8888-4888-8888-888888888888',
    'a1e52222-2222-4222-8222-222222222222',
    pg_catalog.now() + interval '61 minutes',
    'partner_grid'
  ),
  (
    'a1e69999-9999-4999-8999-999999999999',
    'a1e51111-1111-4111-8111-111111111111',
    timestamptz '2027-06-15 02:30:00+00',
    'partner_grid'
  ),
  (
    'a1e6aaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'a1e51111-1111-4111-8111-111111111111',
    null,
    'to_be_arranged'
  ),
  (
    'a1e6bbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'a1e53333-3333-4333-8333-333333333333',
    timestamptz '2027-07-01 17:00:00+00',
    'partner_grid'
  ),
  (
    'a1e6cccc-cccc-4ccc-8ccc-cccccccccccc',
    'a1e54444-4444-4444-8444-444444444444',
    timestamptz '2027-07-02 17:00:00+00',
    'partner_grid'
  );

update public.room_sessions
set cancelled_at = pg_catalog.now()
where id = 'a1e64444-4444-4444-8444-444444444444';

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, cancelled_at
) values
  (
    'a1e71111-1111-4111-8111-111111111111',
    'curitiba',
    'a1e41111-1111-4111-8111-111111111111',
    'a1e51111-1111-4111-8111-111111111111',
    'a1e63333-3333-4333-8333-333333333333',
    timestamptz '2027-06-16 17:00:00+00',
    4, 2, 9000,
    'a1e11111-1111-4111-8111-111111111111',
    null
  ),
  (
    'a1e72222-2222-4222-8222-222222222222',
    'curitiba',
    'a1e41111-1111-4111-8111-111111111111',
    'a1e52222-2222-4222-8222-222222222222',
    'a1e65555-5555-4555-8555-555555555555',
    timestamptz '2027-06-18 17:00:00+00',
    4, 2, 9000,
    'a1e11111-1111-4111-8111-111111111111',
    pg_catalog.now()
  );

do $$
declare
  v_days date[];
  v_slots uuid[];
  v_hm text;
  v_day date;
  v_count integer;
begin
  if not has_function_privilege(
    'anon', 'public.venue_open_slots(uuid)', 'execute'
  ) then
    raise exception 'anon não executa venue_open_slots';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.venue_open_days(uuid)', 'execute'
  ) then
    raise exception 'authenticated não executa venue_open_days';
  end if;
  if has_function_privilege(
    'public', 'public.venue_open_slots(uuid)', 'execute'
  ) then
    raise exception 'public ainda executa venue_open_slots';
  end if;

  select coalesce(array_agg(day order by day), '{}')
    into v_days
  from public.venue_open_days('a1e41111-1111-4111-8111-111111111111');

  if not ('2027-06-14' = any (v_days)) then
    raise exception 'faltou o dia 14/06 no fuso de São Paulo, dias %', v_days;
  end if;
  if not ('2027-06-15' = any (v_days)) then
    raise exception 'faltou o dia 15/06, dias %', v_days;
  end if;
  if '2027-06-16' = any (v_days) then
    raise exception 'dia só com reserva entrou na lista %', v_days;
  end if;
  if '2027-06-17' = any (v_days) then
    raise exception 'dia só com horário removido entrou na lista %', v_days;
  end if;
  if not ('2027-06-18' = any (v_days)) then
    raise exception 'grupo cancelado não devolveu o dia %', v_days;
  end if;

  select coalesce(array_agg(session_id order by session_id), '{}')
    into v_slots
  from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
  where day = date '2027-06-15';

  if v_slots <> array[
    'a1e61111-1111-4111-8111-111111111111',
    'a1e62222-2222-4222-8222-222222222222'
  ]::uuid[] then
    raise exception '15/06 não listou só Alfa 14:00 e Beta 18:00: %', v_slots;
  end if;

  select starts_hm, day
    into v_hm, v_day
  from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
  where session_id = 'a1e69999-9999-4999-8999-999999999999';

  if v_day <> date '2027-06-14' or v_hm <> '23:30' then
    raise exception '02:30 UTC virou % % em vez de 14/06 23:30', v_day, v_hm;
  end if;

  if exists (
    select 1
    from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
    where session_id in (
      'a1e63333-3333-4333-8333-333333333333',
      'a1e64444-4444-4444-8444-444444444444',
      'a1e66666-6666-4666-8666-666666666666',
      'a1e67777-7777-4777-8777-777777777777',
      'a1e6aaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    )
  ) then
    raise exception 'reservado, removido, passado, janela de 1 h ou sem hora entrou';
  end if;

  if not exists (
    select 1
    from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
    where session_id = 'a1e65555-5555-4555-8555-555555555555'
  ) then
    raise exception 'grupo cancelado não devolveu o horário';
  end if;

  if not exists (
    select 1
    from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
    where session_id = 'a1e68888-8888-4888-8888-888888888888'
  ) then
    raise exception '61 minutos à frente ficou de fora';
  end if;

  select count(*) into v_count
  from public.venue_open_days('a1e41111-1111-4111-8111-111111111111') d
  where d.day <> all (
    select s.day
    from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111') s
  );
  if v_count <> 0 then
    raise exception 'venue_open_days divergiu dos horários';
  end if;
end $$;

set role anon;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.venue_open_slots('a1e41111-1111-4111-8111-111111111111')
  where session_id = 'a1e61111-1111-4111-8111-111111111111';
  if v_count <> 1 then
    raise exception 'anon não leu o horário livre da casa aprovada';
  end if;

  select count(*) into v_count
  from public.venue_open_slots('a1e42222-2222-4222-8222-222222222222');
  if v_count <> 0 then
    raise exception 'anon leu horário de casa pendente';
  end if;

  select count(*) into v_count
  from public.venue_open_days('a1e43333-3333-4333-8333-333333333333');
  if v_count <> 0 then
    raise exception 'anon leu dia de casa de teste';
  end if;
end $$;

reset role;
