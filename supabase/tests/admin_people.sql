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
    or (select status from public.venues where id = '2b111111-1111-4111-8111-111111111111')
      is distinct from 'merged'
  then
    raise exception 'sala nao foi para a casa destino';
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
