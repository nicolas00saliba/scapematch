-- Ranking de tempo: flag desligada, sessão real, ordem, auditoria e check-in.
-- Roda numa transação e desfaz. Não fala com o projeto remoto.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_missing text;
begin
  if not exists (
    select 1
    from public.room_time_settings
    where id = 1 and enabled = false
  ) then
    raise exception 'flag não nasce desligada';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'rooms'
      and column_name = 'duration_minutes'
  ) then
    raise exception 'a sala não tem duração';
  end if;

  select string_agg(rel.relname, ', ')
    into v_missing
  from pg_class rel
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname in (
      'room_time_settings',
      'venue_time_ranking',
      'room_time_entries',
      'room_time_members',
      'room_time_audit'
    )
    and not rel.relrowsecurity;
  if v_missing is not null then
    raise exception 'RLS desligado em %', v_missing;
  end if;

  if has_table_privilege('anon', 'public.room_time_entries', 'select')
    or has_table_privilege('authenticated', 'public.room_time_entries', 'insert')
    or has_table_privilege('anon', 'public.room_time_members', 'select')
    or has_table_privilege('authenticated', 'public.room_time_audit', 'select')
    or has_table_privilege('anon', 'public.room_time_settings', 'select')
  then
    raise exception 'tabela de ranking ficou aberta';
  end if;

  if not has_function_privilege(
    'anon',
    'public.room_time_ranking(uuid, integer)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.record_room_time(uuid, integer, boolean, text, jsonb)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.record_room_time(uuid, integer, boolean, text, jsonb)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.my_room_times()',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.admin_save_room_time_settings(boolean)',
    'execute'
  ) then
    raise exception 'execute do ranking saiu do combinado';
  end if;

  if exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname in (
        'record_room_time',
        'edit_room_time',
        'remove_room_time',
        'room_time_ranking',
        'my_room_times',
        'partner_room_times',
        'set_group_team_name',
        'group_team_name',
        'set_venue_time_ranking',
        'venue_time_ranking',
        'room_time_ranking_enabled',
        'admin_room_time_settings',
        'admin_save_room_time_settings',
        'admin_room_time_recent',
        'admin_room_time_audit'
      )
      and (
        not proc.prosecdef
        or not ('search_path=""' = any (proc.proconfig))
      )
  ) then
    raise exception 'função de ranking sem security definer ou search_path vazio';
  end if;

  if pg_get_function_result('public.room_time_ranking(uuid, integer)'::regprocedure)
      ilike '%user_id%'
    or pg_get_function_result('public.room_time_ranking(uuid, integer)'::regprocedure)
      ilike '%email%'
  then
    raise exception 'ranking público devolve identidade';
  end if;

  if pg_get_functiondef('private.ranking_ready_players(uuid)'::regprocedure)
      not like '%session_checkins%'
  then
    raise exception 'faltou o gancho do check-in da casa';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'tempo-admin@example.com', '{"display_name":"Admin Tempo"}'),
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 'tempo-owner@example.com', '{"display_name":"Dona Casa"}'),
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'tempo-staff@example.com', '{"display_name":"Equipe Casa"}'),
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'tempo-ana@example.com', '{"display_name":"Ana Souza"}'),
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', 'tempo-bruno@example.com', '{"display_name":"Bruno Lima"}'),
  ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', 'tempo-fora@example.com', '{"display_name":"Fora da Sala"}');

insert into public.admins (user_id)
values ('d1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    'curitiba',
    'Ninja Escape',
    'Centro',
    'Rua do Tempo',
    '10',
    '80010000',
    -25.43,
    -49.27,
    8000,
    'cnpj',
    '26121212000148',
    '41926121201',
    'approved'
  ),
  (
    'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
    'curitiba',
    'Casa Pendente',
    'Centro',
    'Rua do Tempo',
    '20',
    '80010000',
    -25.44,
    -49.28,
    8000,
    'cnpj',
    '26121212000162',
    '41926121202',
    'pending'
  );

insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'O Cofre',
    6, 2, 60, 'medium', 12000
  ),
  (
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc2',
    'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'Sala Pendente',
    6, 2, 60, 'medium', 12000
  ),
  (
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc3',
    'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'O Labirinto',
    6, 2, 60, 'medium', 12000
  );

insert into public.venue_staff (venue_id, user_id, role, status, accepted_at)
values (
  'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
  'staff',
  'accepted',
  pg_catalog.now() - interval '30 days'
);

insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '5 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd2',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '4 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd3',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '3 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd4',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() + interval '2 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd5',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '6 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd6',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '7 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd7',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '8 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd8',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '9 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  ),
  (
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd9',
    'curitiba', 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'd1cccccc-cccc-4ccc-8ccc-ccccccccccc2',
    pg_catalog.now() - interval '2 days',
    4, 2, 12000, 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
  );

update public.groups
set cancelled_at = pg_catalog.now() - interval '5 days'
where id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd5';

insert into public.group_members (
  group_id, user_id, display_name, payment_status, joined_at
) values
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '5 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', 'Bruno Lima', 'paid', pg_catalog.now() - interval '5 days' + interval '1 minute'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd2', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '4 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd3', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '3 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd4', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now()),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd5', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '6 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd6', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'pending', pg_catalog.now() - interval '7 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd7', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '8 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd8', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '9 days'),
  ('d1dddddd-dddd-4ddd-8ddd-ddddddddddd9', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid', pg_catalog.now() - interval '2 days');

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 2400, true, null, null
  );
  raise exception 'flag desligada aceitou tempo';
exception
  when sqlstate '22023' then
    if sqlerrm not like '%desligado%' then
      raise;
    end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.admin_save_room_time_settings(true);
  raise exception 'admin sem aal2 ligou a flag';
exception
  when sqlstate '42501' then
    if sqlerrm not like '%mfa%' then
      raise;
    end if;
end $$;

reset role;

select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.admin_save_room_time_settings(true);
reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 2400, true, null, null
  );
  raise exception 'jogador lançou tempo';
exception
  when sqlstate '42501' then
    null;
end $$;

select public.set_group_team_name(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1',
  'Os Ninjas'
);

do $$
begin
  perform public.set_group_team_name(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd2',
    'porra'
  );
  raise exception 'palavrão entrou no nome';
exception
  when sqlstate '22023' then
    if sqlerrm not like '%outro nome%' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.set_group_team_name(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd2',
    'Nome grande demais para caber no ranking da sala'
  );
  raise exception 'nome longo entrou';
exception
  when sqlstate '22023' then
    if sqlerrm not like '%40%' then
      raise;
    end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', true);
set local role authenticated;

do $$
begin
  perform public.group_team_name('d1dddddd-dddd-4ddd-8ddd-ddddddddddd1');
  raise exception 'estranho leu o nome do grupo';
exception
  when sqlstate '42501' then
    null;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd4', 1000, true, null, null
  );
  raise exception 'sessão futura aceitou tempo';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%não começou%' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd5', 1000, true, null, null
  );
  raise exception 'grupo cancelado aceitou tempo';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%cancelado%' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd6', 1000, true, null, null
  );
  raise exception 'sem reserva paga aceitou tempo';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%reserva paga%' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 4000, true, null, null
  );
  raise exception 'tempo maior que a sala entrou';
exception
  when sqlstate '22023' then
    null;
end $$;

select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 2400, true, null, null
);

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1', 2000, true, null, null
  );
  raise exception 'segundo lançamento passou';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%já tem tempo%' then
      raise;
    end if;
end $$;

select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd2', 2700, true, 'Equipe Leste', null
);

select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd3', 3000, true, null, null
);

select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd7', 3600, false, 'Quase', null
);

reset role;

do $$
declare
  v_name text;
  v_medal text;
  v_remaining integer;
  v_members text[];
  v_count integer;
begin
  select entry.group_name into v_name
  from public.room_time_entries entry
  where entry.group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1';
  if v_name <> 'Os Ninjas' then
    raise exception 'não usou o nome do grupo: %', v_name;
  end if;

  select entry.group_name into v_name
  from public.room_time_entries entry
  where entry.group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd3';
  if v_name <> 'Grupo' then
    raise exception 'faltou o nome padrão: %', v_name;
  end if;

  if (
    select entry.duration_seconds - entry.elapsed_seconds
    from public.room_time_entries entry
    where entry.group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd1'
  ) <> 1200 then
    raise exception 'restavam não é a duração menos o tempo';
  end if;

  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10);
  if v_count <> 3 then
    raise exception 'ranking contou quem não escapou ou a mais: %', v_count;
  end if;

  select medal, remaining_seconds, members
    into v_medal, v_remaining, v_members
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10)
  where rank_place = 1;
  if v_medal <> 'ouro' or v_remaining <> 1200 or v_members <> '{}'::text[] then
    raise exception 'ouro, restante ou nomes públicos saíram errados';
  end if;

  select medal into v_medal
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10)
  where rank_place = 2;
  if v_medal <> 'prata' then
    raise exception 'prata não ficou em segundo';
  end if;

  select medal into v_medal
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10)
  where rank_place = 3;
  if v_medal <> 'bronze' then
    raise exception 'bronze não ficou em terceiro';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
select public.set_venue_time_ranking(
  'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  true,
  true
);
reset role;

do $$
declare
  v_members text[];
begin
  select members into v_members
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10)
  where rank_place = 1;
  if v_members <> array['Ana', 'Bruno']::text[] then
    raise exception 'integrantes não são o primeiro nome: %', v_members;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
set local role authenticated;

do $$
declare
  v_escaped integer;
  v_open integer;
  v_position integer;
begin
  select count(*) into v_escaped
  from public.my_room_times()
  where escaped;
  select count(*) into v_open
  from public.my_room_times()
  where not escaped;
  select rank_place into v_position
  from public.my_room_times()
  where group_name = 'Os Ninjas';
  if v_escaped <> 3 or v_open <> 1 or v_position <> 1 then
    raise exception 'histórico da Ana saiu errado: % % %', v_escaped, v_open, v_position;
  end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', true);
set local role authenticated;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.my_room_times();
  if v_count <> 0 then
    raise exception 'estranho viu tempo alheio';
  end if;
end $$;

reset role;

create temporary table ranking_ids as
select group_id, id as entry_id
from public.room_time_entries;
grant select on ranking_ids to authenticated;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_count integer;
begin
  select entry_id into v_id
  from ranking_ids
  where group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd2';
  perform public.edit_room_time(v_id, 2000, true, 'Leste', null);
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10)
  where rank_place = 1 and group_name = 'Leste' and elapsed_seconds = 2000;
  if v_count <> 1 then
    raise exception 'edição da equipe não reordenou';
  end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;

do $$
declare
  v_id uuid;
  v_actions text;
begin
  select entry_id into v_id
  from ranking_ids
  where group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd3';
  perform public.remove_room_time(v_id);
  select string_agg(audit.action, ',' order by audit.created_at)
    into v_actions
  from public.admin_room_time_audit(v_id) audit;
  if v_actions not like '%record%' or v_actions not like '%remove%' then
    raise exception 'auditoria incompleta: %', v_actions;
  end if;
end $$;

reset role;

do $$
declare
  v_id uuid;
begin
  select entry_id into v_id
  from ranking_ids
  where group_id = 'd1dddddd-dddd-4ddd-8ddd-ddddddddddd3';
  if not exists (
    select 1
    from public.admin_audit_log log
    where log.target_table = 'room_time_entries'
      and log.target_id = v_id::text
      and log.action = 'remove'
  ) then
    raise exception 'admin não auditou a remoção';
  end if;
end $$;

do $$
declare
  v_count integer;
  v_position integer;
begin
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 100);
  if v_count <> 2 then
    raise exception 'remoção não saiu do ranking: %', v_count;
  end if;

  perform set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
  set local role authenticated;
  select rank_place into v_position
  from public.my_room_times()
  where group_name = 'Grupo';
  if v_position is not null then
    raise exception 'tempo removido ficou no histórico';
  end if;
  reset role;
end $$;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
select public.set_venue_time_ranking(
  'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  false,
  true
);
reset role;

do $$
declare
  v_count integer;
  v_partner integer;
begin
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10);
  if v_count <> 0 then
    raise exception 'casa ocultou o ranking e ele continuou público';
  end if;

  perform set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
  set local role authenticated;
  select count(*) into v_partner
  from public.partner_room_times('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_partner <> 3 then
    raise exception 'a casa perdeu o ranking completo: %', v_partner;
  end if;
  reset role;
end $$;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
select public.set_venue_time_ranking(
  'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  true,
  false
);
reset role;

select set_config('request.jwt.claim.sub', '', true);
update public.venues
set suspended_at = pg_catalog.now()
where id = 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';

do $$
declare
  v_count integer;
  v_position integer;
begin
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10);
  if v_count <> 0 then
    raise exception 'casa suspensa ficou no ranking';
  end if;
  perform set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
  set local role authenticated;
  select rank_place into v_position
  from public.my_room_times()
  where group_name = 'Os Ninjas';
  if v_position is not null then
    raise exception 'posição contou casa suspensa';
  end if;
  reset role;
end $$;

select set_config('request.jwt.claim.sub', '', true);
update public.venues
set suspended_at = null
where id = 'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd9', 1500, true, 'Pendente', null
);
reset role;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc2', 10);
  if v_count <> 0 then
    raise exception 'casa pendente entrou no ranking público';
  end if;
end $$;

do $$
declare
  i integer;
  v_group uuid;
  v_count integer;
  v_slow integer;
begin
  for i in 1..11 loop
    perform set_config('request.jwt.claim.sub', '', true);
    v_group := pg_catalog.gen_random_uuid();
    insert into public.groups (
      id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
      price_cents, created_by
    ) values (
      v_group,
      'curitiba',
      'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'd1cccccc-cccc-4ccc-8ccc-ccccccccccc3',
      pg_catalog.now() - (i || ' hours')::interval - interval '20 days',
      4, 2, 12000,
      'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5'
    );
    insert into public.group_members (
      group_id, user_id, display_name, payment_status
    ) values (
      v_group,
      'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5',
      'Bruno Lima',
      'paid'
    );
    perform set_config(
      'request.jwt.claim.sub',
      'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
      true
    );
    perform set_config('request.jwt.claim.aal', 'aal1', true);
    perform public.record_room_time(v_group, 100 + i, true, 'Lote ' || i, null);
  end loop;

  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc3', 50);
  if v_count <> 10 then
    raise exception 'top 10 não segurou o limite: %', v_count;
  end if;
  select elapsed_seconds into v_slow
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc3', 10)
  order by rank_place desc
  limit 1;
  if v_slow <> 110 then
    raise exception 'o décimo tempo não é o esperado: %', v_slow;
  end if;
end $$;

create table public.session_checkins (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  marked_by uuid not null references auth.users (id),
  marked_at timestamptz not null default pg_catalog.now(),
  unique (group_id, user_id)
);

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;

do $$
begin
  perform public.record_room_time(
    'd1dddddd-dddd-4ddd-8ddd-ddddddddddd8', 1800, true, 'Sem carimbo', null
  );
  raise exception 'sem check-in da casa aceitou tempo';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%comparecimento%' then
      raise;
    end if;
end $$;

reset role;

insert into public.session_checkins (
  venue_id, group_id, user_id, room_id, marked_by
) values (
  'd1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd8',
  'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',
  'd1cccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
);

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
select public.record_room_time(
  'd1dddddd-dddd-4ddd-8ddd-ddddddddddd8', 1800, true, 'Com carimbo', null
);
reset role;

set local role authenticated;

do $$
begin
  perform 1 from public.room_time_entries;
  raise exception 'tabela aberta para authenticated';
exception
  when insufficient_privilege then
    null;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.admin_save_room_time_settings(false);
reset role;

do $$
declare
  v_count integer;
begin
  if public.room_time_ranking_enabled() then
    raise exception 'flag não voltou a desligar';
  end if;
  select count(*) into v_count
  from public.room_time_ranking('d1cccccc-cccc-4ccc-8ccc-ccccccccccc1', 10);
  if v_count <> 0 then
    raise exception 'flag desligada ainda publica ranking';
  end if;
end $$;

rollback;
