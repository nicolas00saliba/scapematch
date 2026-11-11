-- Avaliações: flag desligada, elegibilidade, antifraude, agregados e ranking.
-- Roda numa transação e desfaz. Não fala com o projeto remoto.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_missing text;
begin
  if exists (
    select 1
    from public.cities
    where country_code <> 'BR'
      or country_name <> 'Brasil'
  ) then
    raise exception 'cidade sem país Brasil';
  end if;

  if not exists (
    select 1
    from public.review_settings
    where id = 1
      and enabled = false
      and bayesian_m = 10
      and ranking_min = 10
  ) then
    raise exception 'flag não nasce desligada com m e mínimo 10';
  end if;

  select string_agg(rel.relname, ', ')
    into v_missing
  from pg_class rel
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname in (
      'review_settings',
      'venue_staff',
      'room_reviews',
      'review_replies',
      'review_reports',
      'review_moderation_events',
      'room_rating_rollups'
    )
    and not rel.relrowsecurity;
  if v_missing is not null then
    raise exception 'RLS desligado em %', v_missing;
  end if;

  if has_table_privilege('anon', 'public.room_reviews', 'select')
    or has_table_privilege('authenticated', 'public.room_reviews', 'insert')
    or has_table_privilege('anon', 'public.review_settings', 'select')
    or has_table_privilege('authenticated', 'public.venue_staff', 'select')
    or has_table_privilege('anon', 'public.review_reports', 'select')
  then
    raise exception 'tabela de avaliação ficou aberta';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.submit_room_review(uuid, integer, integer, integer, integer, integer, integer, text)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.submit_room_review(uuid, integer, integer, integer, integer, integer, integer, text)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.admin_hide_review(uuid, text)',
    'execute'
  ) then
    raise exception 'execute das avaliações saiu do combinado';
  end if;

  if exists (
    select 1
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.proname in (
        'submit_room_review',
        'reply_room_review',
        'report_room_review',
        'room_review_comments',
        'room_rating',
        'venue_rating',
        'venue_review_insights',
        'review_rankings',
        'admin_review_settings',
        'admin_save_review_settings',
        'admin_hide_review',
        'admin_review_audit',
        'reviews_enabled'
      )
      and (
        not proc.prosecdef
        or not ('search_path=""' = any (proc.proconfig))
      )
  ) then
    raise exception 'função de avaliação sem security definer ou search_path vazio';
  end if;

  if pg_get_function_result('public.room_review_comments(uuid)'::regprocedure)
    ilike '%author%'
    or pg_get_function_result('public.room_review_comments(uuid)'::regprocedure)
      ilike '%story%'
  then
    raise exception 'comentário público devolve identidade ou nota por categoria';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', 'review-admin@example.com', '{"display_name":"Admin Avalia"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 'review-owner@example.com', '{"display_name":"Dona Casa"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'review-staff@example.com', '{"display_name":"Equipe Casa"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'review-player@example.com', '{"display_name":"Ana Souza"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', 'review-cpf@example.com', '{"display_name":"Gemeo Cpf"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', 'review-phone@example.com', '{"display_name":"Gemeo Fone"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7', 'review-card@example.com', '{"display_name":"Gemeo Cartao"}'),
  ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8', 'review-report@example.com', '{"display_name":"Denuncia"}');

insert into public.admins (user_id)
values ('c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1');

update public.profiles
set cpf = '52998224725'
where id = 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';

update public.profiles
set cpf = '52998224725'
where id = 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5';

update public.profiles
set phone = '41988880099'
where id = 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6';

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
  'curitiba',
  'Casa da Avaliação',
  'Centro',
  'Rua da Nota',
  '10',
  '80010000',
  -25.43,
  -49.27,
  8000,
  'cnpj',
  '74859632000160',
  '41988880099',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'Sala Cinco',
    6, 2, 60, 'medium', 12000
  ),
  (
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc2',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'Sala Um',
    6, 2, 60, 'medium', 12000
  );

insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values
  (
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    'curitiba',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '3 days',
    8, 2, 12000,
    'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
  ),
  (
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd2',
    'curitiba',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() + interval '2 days',
    4, 2, 12000,
    'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
  ),
  (
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd3',
    'curitiba',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc1',
    pg_catalog.now() - interval '4 days',
    12, 2, 12000,
    'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
  ),
  (
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd4',
    'curitiba',
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
    'c0cccccc-cccc-4ccc-8ccc-ccccccccccc2',
    pg_catalog.now() - interval '4 days',
    12, 2, 12000,
    'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'
  );

insert into public.group_members (group_id, user_id, display_name, payment_status)
values
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', 'Dona Casa', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Equipe Casa', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', 'Gemeo Cpf', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', 'Gemeo Fone', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd1', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7', 'Gemeo Cartao', 'paid'),
  ('c0dddddd-dddd-4ddd-8ddd-ddddddddddd2', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Ana Souza', 'paid');

insert into public.venue_staff (venue_id, user_id, role)
values (
  'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
  'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',
  'staff'
);

update public.profiles
set asaas_customer_id = 'cus_review_dona'
where id = 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';

update public.profiles
set asaas_customer_id = 'cus_review_gemeo'
where id = 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7';

select private.insert_saved_card(
  'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
  'cus_review_dona',
  'tok_review_same',
  '4242',
  'visa'
);

select private.insert_saved_card(
  'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7',
  'cus_review_gemeo',
  'tok_review_same',
  '4242',
  'visa'
);

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 4, 4, 4, 'muito boa'
  );
  raise exception 'flag desligada aceitou avaliação';
exception
  when sqlstate '22023' then
    if sqlerrm not like '%desligadas%' then
      raise;
    end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.admin_save_review_settings('{"enabled": true}'::jsonb);
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
select public.admin_save_review_settings('{"enabled": true}'::jsonb);
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd2',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'sessão futura aceitou avaliação';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%termina%' then
      raise;
    end if;
end $$;

do $$
declare
  v_id uuid;
begin
  v_id := public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 4, 4, 4,
    'A história prende.'
  );
  if v_id is null then
    raise exception 'avaliação paga não gravou';
  end if;
end $$;

do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    1, 1, 1, 1, 1, 1, ''
  );
  raise exception 'segunda avaliação da mesma sessão passou';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%já avaliou%' then
      raise;
    end if;
end $$;

reset role;

select set_config(
  'app.review_id',
  (select id::text from public.room_reviews limit 1),
  true
);

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'dona avaliou a própria casa';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%própria casa%' then
      raise;
    end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', true);
set local role authenticated;
do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'staff avaliou a própria casa';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%própria casa%' then
      raise;
    end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', true);
set local role authenticated;
do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'mesmo CPF avaliou';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%não pode avaliar%' then
      raise;
    end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', true);
set local role authenticated;
do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'mesmo telefone avaliou';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%não pode avaliar%' then
      raise;
    end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7', true);
set local role authenticated;
do $$
begin
  perform public.submit_room_review(
    'c0dddddd-dddd-4ddd-8ddd-ddddddddddd1',
    5, 5, 5, 5, 5, 5, ''
  );
  raise exception 'mesmo cartão avaliou';
exception
  when sqlstate 'P0001' then
    if sqlerrm not like '%não pode avaliar%' then
      raise;
    end if;
end $$;
reset role;

do $$
declare
  v_name text;
  v_count integer;
begin
  select first_name, count(*) over ()
    into v_name, v_count
  from public.room_review_comments('c0cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_count is distinct from 1 or v_name is distinct from 'Ana' then
    raise exception 'comentário público veio como % (% linhas)', v_name, v_count;
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8', true);
set local role authenticated;
do $$
begin
  perform public.reply_room_review(
    current_setting('app.review_id')::uuid,
    'obrigado'
  );
  raise exception 'jogador respondeu pela casa';
exception
  when sqlstate '42501' then
    null;
end $$;

select public.report_room_review(
  current_setting('app.review_id')::uuid,
  'texto ofensivo'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;
select public.reply_room_review(
  current_setting('app.review_id')::uuid,
  'Obrigado pelo retorno.'
);
reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;

do $$
begin
  perform public.admin_hide_review(
    current_setting('app.review_id')::uuid,
    '   '
  );
  raise exception 'ocultou sem motivo';
exception
  when sqlstate '22023' then
    null;
end $$;

select public.admin_hide_review(
  current_setting('app.review_id')::uuid,
  'Ofensa à equipe'
);

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.room_review_comments('c0cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_count is distinct from 0 then
    raise exception 'comentário oculto continuou público';
  end if;
  if public.admin_review_audit()::text not like '%Ofensa à equipe%' then
    raise exception 'fila de auditoria não devolveu o motivo';
  end if;
end $$;

reset role;

do $$
declare
  v_events integer;
begin
  select count(*) into v_events
  from public.review_moderation_events
  where action = 'hide'
    and reason = 'Ofensa à equipe';
  if v_events is distinct from 1 then
    raise exception 'auditoria da ocultação não gravou';
  end if;
end $$;

do $$
declare
  i integer;
  v_user uuid;
  v_group uuid;
  v_room integer;
begin
  for i in 1..20 loop
    v_user := ('c0eeeeee-eeee-4eee-8eee-' || lpad(i::text, 12, '0'))::uuid;
    v_room := case when i <= 10 then 1 else 2 end;
    v_group := case
      when i <= 10 then 'c0dddddd-dddd-4ddd-8ddd-ddddddddddd3'::uuid
      else 'c0dddddd-dddd-4ddd-8ddd-ddddddddddd4'::uuid
    end;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      v_user,
      'rank-' || i || '@example.com',
      jsonb_build_object('display_name', 'Jogador ' || i)
    );
    insert into public.group_members (group_id, user_id, display_name, payment_status)
    values (v_group, v_user, 'Jogador ' || i, 'paid');
    perform set_config('request.jwt.claim.sub', v_user::text, true);
    perform set_config('request.jwt.claim.aal', 'aal1', true);
    execute 'set local role authenticated';
    if v_room = 1 then
      perform public.submit_room_review(v_group, 5, 5, 5, 5, 5, 5, '');
    else
      perform public.submit_room_review(v_group, 1, 1, 1, 1, 1, 1, '');
    end if;
    execute 'reset role';
  end loop;
end $$;

do $$
declare
  v_top numeric;
  v_second numeric;
  v_house numeric;
  v_publish boolean;
  v_count integer;
begin
  select bayesian into v_top
  from public.review_rankings('room', 'city', 'curitiba', null)
  where "rank" = 1;
  select bayesian into v_second
  from public.review_rankings('room', 'world', null, null)
  where "rank" = 2;
  if abs(v_top - 4) > 0.0001 or abs(v_second - 2) > 0.0001 then
    raise exception 'bayesiana de sala saiu % e %', v_top, v_second;
  end if;

  select bayesian, review_count
    into v_house, v_count
  from public.review_rankings('venue', 'country', null, 'BR')
  where "rank" = 1;
  if v_count <> 20 or abs(v_house - 3) > 0.0001 then
    raise exception 'casa ponderada saiu % com %', v_house, v_count;
  end if;

  select publish, review_count
    into v_publish, v_count
  from public.room_rating('c0cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_publish is not true or v_count <> 10 then
    raise exception 'JSON-LD da sala não liberou no mínimo';
  end if;

  if (
    select count(*)
    from public.review_rankings('room', 'city', 'sao-paulo', null)
  ) <> 0 then
    raise exception 'ranking de outra cidade trouxe sala';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', true);
set local role authenticated;

do $$
declare
  v_insights jsonb;
begin
  v_insights := public.venue_review_insights(
    'c0bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  );
  if v_insights ? 'author_id'
    or v_insights::text like '%author_id%'
    or (v_insights -> 'comments' -> 0) ? 'story'
  then
    raise exception 'insight expôs identidade ou nota por categoria';
  end if;
  if (v_insights ->> 'review_count')::integer <> 20 then
    raise exception 'insight não contou as 20 notas';
  end if;
  if (v_insights -> 'categories' ->> 'story')::numeric <> 3 then
    raise exception 'média de história saiu %', v_insights -> 'categories' ->> 'story';
  end if;
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.admin_save_review_settings('{"ranking_min": 11}'::jsonb);
reset role;

do $$
declare
  v_rows integer;
  v_publish boolean;
begin
  select count(*) into v_rows from public.review_rankings('room', 'world', null, null);
  if v_rows <> 0 then
    raise exception 'ranking ignorou o mínimo';
  end if;
  select publish into v_publish
  from public.room_rating('c0cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_publish is not false then
    raise exception 'publish ficou verdadeiro abaixo do mínimo';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'c0aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.admin_save_review_settings('{"enabled": false}'::jsonb);
reset role;

do $$
declare
  v_rows integer;
begin
  select count(*) into v_rows
  from public.room_rating('c0cccccc-cccc-4ccc-8ccc-ccccccccccc1');
  if v_rows <> 0 then
    raise exception 'flag desligada ainda publica nota';
  end if;
  set local role anon;
  select count(*) into v_rows from public.room_rating_rollups;
  if v_rows <> 0 then
    raise exception 'anon leu agregado com a flag desligada';
  end if;
  reset role;
end $$;

rollback;
