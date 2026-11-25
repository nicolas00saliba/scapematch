-- Admin de casas e pontos. Anon e sessão sem aal2 não passam.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('2a111111-1111-4111-8111-111111111111', 'people-admin@example.com', '{"display_name":"Admin Casa"}'),
  ('2a222222-2222-4222-8222-222222222222', 'people-player@example.com', '{"display_name":"Ana Casa"}');

insert into public.admins (user_id)
values ('2a111111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    '2b111111-1111-4111-8111-111111111111',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Origem', 'Centro', 'Rua A', '1',
    '80020010', -25.43, -49.27, 4000, 'cnpj', '19000000000804', '4191000804',
    'approved'
  ),
  (
    '2b222222-2222-4222-8222-222222222222',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Destino', 'Batel', 'Rua B', '2',
    '80020020', -25.43, -49.27, 4000, 'cnpj', '19000000000815', '4191000815',
    'approved'
  ),
  (
    '2b333333-3333-4333-8333-333333333333',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Reprovada', 'Centro', 'Rua C', '3',
    '80020030', -25.43, -49.27, 4000, 'cnpj', '19000000000826', '4191000826',
    'rejected'
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  '2c111111-1111-4111-8111-111111111111',
  '2b111111-1111-4111-8111-111111111111',
  'Sala Origem', '', 4, 2, 60, 'medium', 9000
);

insert into public.news_items (id, venue_id, title, summary, category)
values (
  '2d111111-1111-4111-8111-111111111111',
  '2b111111-1111-4111-8111-111111111111',
  'Aviso', 'Sala nova da origem', 'new_room'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    '2b444444-4444-4444-8444-444444444444',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Equipe', 'Centro', 'Rua D', '4',
    '80020040', -25.43, -49.27, 4000, 'cnpj', '19000000000837', '4191000837',
    'approved'
  ),
  (
    '2b555555-5555-4555-8555-555555555555',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Acesso', 'Centro', 'Rua E', '5',
    '80020050', -25.43, -49.27, 4000, 'cnpj', '19000000000859', '4191000859',
    'approved'
  ),
  (
    '2b666666-6666-4666-8666-666666666666',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Saldo', 'Centro', 'Rua F', '6',
    '80020060', -25.43, -49.27, 4000, 'cnpj', '19000000000860', '4191000860',
    'approved'
  ),
  (
    '2b777777-7777-4777-8777-777777777777',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Cobranca', 'Centro', 'Rua G', '7',
    '80020070', -25.43, -49.27, 4000, 'cnpj', '19000000000871', '4191000871',
    'approved'
  ),
  (
    '2b888888-8888-4888-8888-888888888888',
    '2a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Repasse', 'Centro', 'Rua H', '8',
    '80020080', -25.43, -49.27, 4000, 'cnpj', '19000000000882', '4191000882',
    'approved'
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  ('2c444444-4444-4444-8444-444444444444', '2b444444-4444-4444-8444-444444444444', 'Sala Equipe', '', 4, 2, 60, 'medium', 9000),
  ('2c555555-5555-4555-8555-555555555555', '2b555555-5555-4555-8555-555555555555', 'Sala Acesso', '', 4, 2, 60, 'medium', 9000),
  ('2c666666-6666-4666-8666-666666666666', '2b666666-6666-4666-8666-666666666666', 'Sala Saldo', '', 4, 2, 60, 'medium', 9000),
  ('2c777777-7777-4777-8777-777777777777', '2b777777-7777-4777-8777-777777777777', 'Sala Cobranca', '', 4, 2, 60, 'medium', 9000),
  ('2c888888-8888-4888-8888-888888888888', '2b888888-8888-4888-8888-888888888888', 'Sala Repasse', '', 4, 2, 60, 'medium', 9000);

insert into public.venue_staff (venue_id, user_id, role, status)
values (
  '2b444444-4444-4444-8444-444444444444',
  '2a222222-2222-4222-8222-222222222222',
  'staff', 'pending'
);

insert into public.venue_pagbank_tokens (venue_id, access_token)
values ('2b555555-5555-4555-8555-555555555555', '\x00'::bytea);

insert into public.ledger_entries (venue_id, account, direction, kind, amount_cents)
values (
  '2b666666-6666-4666-8666-666666666666', 'house', 'credit', 'house_net', 100
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  '2d777777-7777-4777-8777-777777777777',
  '2c777777-7777-4777-8777-777777777777',
  '2027-12-07 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  '2e777777-7777-4777-8777-777777777777', 'curitiba',
  '2b777777-7777-4777-8777-777777777777',
  '2c777777-7777-4777-8777-777777777777',
  '2d777777-7777-4777-8777-777777777777',
  '2027-12-07 18:00:00+00', 4, 2, 9000,
  '2a222222-2222-4222-8222-222222222222'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, commission_bps
) values (
  '2c277777-7777-4777-8777-777777777777',
  '2e777777-7777-4777-8777-777777777777',
  '2a222222-2222-4222-8222-222222222222',
  '2b777777-7777-4777-8777-777777777777',
  9000, 'PIX', 'paid', 'idem-people-cobranca', 2500
);

insert into public.venue_withdrawals (
  venue_id, amount_cents, status, source, period_key, external_reference
) values (
  '2b888888-8888-4888-8888-888888888888',
  100, 'pending', 'manual', 'manual-people-888', 'people-wd-888'
);

insert into public.venue_commissions (venue_id, commission_bps, updated_by)
values (
  '2b111111-1111-4111-8111-111111111111',
  1500,
  '2a111111-1111-4111-8111-111111111111'
);

do $$
declare
  v_name text;
begin
  foreach v_name in array array[
    'public.admin_reopen_venue(uuid)',
    'public.admin_set_account_test(text,uuid,boolean)',
    'public.admin_clear_venue_commission(uuid,text)',
    'public.admin_merge_venues(uuid,uuid,text)',
    'public.admin_adjust_points(uuid,integer,text,text,text)',
    'public.admin_player_ledger(uuid)'
  ]
  loop
    if not exists (
      select 1 from pg_proc p
      where p.oid = v_name::regprocedure
        and p.prosecdef
        and 'search_path=""' = any (p.proconfig)
    ) then
      raise exception '% sem definer ou search_path vazio', v_name;
    end if;
    if has_function_privilege('anon', v_name, 'execute')
      or not has_function_privilege('authenticated', v_name, 'execute')
    then
      raise exception 'grant de % saiu do combinado', v_name;
    end if;
  end loop;
  if position(
    'pg_catalog.pg_class' in pg_get_functiondef(
      'public.admin_merge_venues(uuid,uuid,text)'::regprocedure
    )
  ) > 0
  or position(
    '''news_items''' in pg_get_functiondef(
      'public.admin_merge_venues(uuid,uuid,text)'::regprocedure
    )
  ) = 0
  then
    raise exception 'mescla sem allowlist fechada';
  end if;
  if position(
    'for update' in pg_get_functiondef(
      'public.admin_adjust_points(uuid,integer,text,text,text)'::regprocedure
    )
  ) = 0 then
    raise exception 'debito sem lock de linha';
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', '2a222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role anon;
do $$
begin
  perform public.admin_reopen_venue('2b333333-3333-4333-8333-333333333333');
  raise exception 'anon reabriu casa';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '2a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_adjust_points(
    '2a222222-2222-4222-8222-222222222222', 10, 'credit', 'acerto', 'PONTOS'
  );
  raise exception 'admin sem aal2 ajustou pontos';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '2a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_points jsonb;
  v_merge jsonb;
begin
  perform public.admin_reopen_venue('2b333333-3333-4333-8333-333333333333');
  perform public.admin_set_account_test(
    'player', '2a222222-2222-4222-8222-222222222222', true
  );
  perform public.admin_clear_venue_commission(
    '2b111111-1111-4111-8111-111111111111', 'OFICIAL'
  );
  begin
    perform public.admin_adjust_points(
      '2a222222-2222-4222-8222-222222222222', 5, 'debit', 'demais', 'PONTOS'
    );
    raise exception 'debito sem saldo passou';
  exception
    when sqlstate 'P0001' then
      null;
  end;
  v_points := public.admin_adjust_points(
    '2a222222-2222-4222-8222-222222222222', 12, 'credit', 'cortesia', 'PONTOS'
  );
  if (v_points ->> 'available_points')::integer <> 12 then
    raise exception 'credito: %', v_points;
  end if;
  v_points := public.admin_adjust_points(
    '2a222222-2222-4222-8222-222222222222', 7, 'debit', 'uso', 'PONTOS'
  );
  if (v_points ->> 'available_points')::integer <> 5 then
    raise exception 'debito com lock: %', v_points;
  end if;
  begin
    perform public.admin_adjust_points(
      '2a222222-2222-4222-8222-222222222222', 6, 'debit', 'estouro', 'PONTOS'
    );
    raise exception 'debito deixou o saldo negativo';
  exception
    when sqlstate 'P0001' then
      null;
  end;
  v_points := public.admin_adjust_points(
    '2a222222-2222-4222-8222-222222222222', 7, 'credit', 'reposicao', 'PONTOS'
  );
  if (v_points ->> 'available_points')::integer <> 12 then
    raise exception 'saldo depois do estouro: %', v_points;
  end if;
  begin
    perform public.admin_merge_venues(
      '2b444444-4444-4444-8444-444444444444',
      '2b222222-2222-4222-8222-222222222222',
      'MESCLAR'
    );
    raise exception 'mescla com equipe passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'casa com equipe' then
        raise;
      end if;
  end;
  begin
    perform public.admin_merge_venues(
      '2b555555-5555-4555-8555-555555555555',
      '2b222222-2222-4222-8222-222222222222',
      'MESCLAR'
    );
    raise exception 'mescla com acesso passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'casa com acesso' then
        raise;
      end if;
  end;
  begin
    perform public.admin_merge_venues(
      '2b666666-6666-4666-8666-666666666666',
      '2b222222-2222-4222-8222-222222222222',
      'MESCLAR'
    );
    raise exception 'mescla com saldo passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'casa com saldo' then
        raise;
      end if;
  end;
  begin
    perform public.admin_merge_venues(
      '2b777777-7777-4777-8777-777777777777',
      '2b222222-2222-4222-8222-222222222222',
      'MESCLAR'
    );
    raise exception 'mescla com cobranca passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'casa com cobranca' then
        raise;
      end if;
  end;
  begin
    perform public.admin_merge_venues(
      '2b888888-8888-4888-8888-888888888888',
      '2b222222-2222-4222-8222-222222222222',
      'MESCLAR'
    );
    raise exception 'mescla com repasse passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'casa com repasse' then
        raise;
      end if;
  end;
  v_merge := public.admin_merge_venues(
    '2b111111-1111-4111-8111-111111111111',
    '2b222222-2222-4222-8222-222222222222',
    'MESCLAR'
  );
  if v_merge ->> 'status' <> 'merged' then
    raise exception 'mescla: %', v_merge;
  end if;
end $$;
reset role;
do $$
begin
  if (select status from public.venues where id = '2b333333-3333-4333-8333-333333333333')
    is distinct from 'pending'
  then
    raise exception 'reprovada nao voltou para pendente';
  end if;
  if not (select is_test from public.profiles where id = '2a222222-2222-4222-8222-222222222222')
  then
    raise exception 'conta de teste nao marcou';
  end if;
  if exists (
    select 1 from public.venue_commissions
    where venue_id = '2b111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'comissao da casa nao saiu';
  end if;
  if (
    select available_points from private.scape_balances('2a222222-2222-4222-8222-222222222222')
  ) <> 12 then
    raise exception 'saldo de pontos nao bate';
  end if;
  if not exists (
    select 1 from public.scape_point_entries
    where user_id = '2a222222-2222-4222-8222-222222222222'
      and kind = 'admin_credit'
      and note = 'cortesia'
  ) then
    raise exception 'livro nao guardou o motivo';
  end if;
  if (select venue_id from public.rooms where id = '2c111111-1111-4111-8111-111111111111')
    is distinct from '2b222222-2222-4222-8222-222222222222'
    or (select venue_id from public.news_items where id = '2d111111-1111-4111-8111-111111111111')
      is distinct from '2b222222-2222-4222-8222-222222222222'
    or (select status from public.venues where id = '2b111111-1111-4111-8111-111111111111')
      is distinct from 'merged'
  then
    raise exception 'sala nao foi para a casa destino';
  end if;
  if (select venue_id from public.rooms where id = '2c444444-4444-4444-8444-444444444444')
      is distinct from '2b444444-4444-4444-8444-444444444444'
    or (select venue_id from public.rooms where id = '2c555555-5555-4555-8555-555555555555')
      is distinct from '2b555555-5555-4555-8555-555555555555'
    or (select venue_id from public.rooms where id = '2c666666-6666-4666-8666-666666666666')
      is distinct from '2b666666-6666-4666-8666-666666666666'
    or (select venue_id from public.rooms where id = '2c777777-7777-4777-8777-777777777777')
      is distinct from '2b777777-7777-4777-8777-777777777777'
    or (select venue_id from public.rooms where id = '2c888888-8888-4888-8888-888888888888')
      is distinct from '2b888888-8888-4888-8888-888888888888'
    or (select status from public.venues where id = '2b444444-4444-4444-8444-444444444444')
      is distinct from 'approved'
  then
    raise exception 'mescla recusada moveu a casa';
  end if;
  if (
    select available_points from private.scape_balances('2a222222-2222-4222-8222-222222222222')
  ) < 0 then
    raise exception 'saldo de pontos ficou negativo';
  end if;
  if (public.admin_scape_liability() ->> 'available_points')::integer < 12
    or (public.admin_scape_liability() ->> 'unused_points')::integer < 12
  then
    raise exception 'passivo nao viu o credito manual';
  end if;
  if not exists (
    select 1 from public.admin_audit_log
    where actor_id = '2a111111-1111-4111-8111-111111111111'
      and action in ('reopen_venue', 'adjust_points', 'merge_venues')
    group by actor_id
    having count(distinct action) = 3
  ) then
    raise exception 'auditoria das pessoas incompleta';
  end if;
end $$;
rollback;
