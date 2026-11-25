-- Ganhos sem casa/conta de teste, recompensa sem soma dupla, histórico de regra
-- e a config de parcelas. Anon e sessão sem aal2 não passam.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('3a111111-1111-4111-8111-111111111111', 'report-admin@example.com', '{"display_name":"Admin Relatorio"}'),
  ('3a222222-2222-4222-8222-222222222222', 'report-player@example.com', '{"display_name":"Relatorio Jogador"}'),
  ('3a333333-3333-4333-8333-333333333333', 'report-test@example.com', '{"display_name":"Relatorio Teste"}');

insert into public.admins (user_id)
values ('3a111111-1111-4111-8111-111111111111');

update public.profiles
set is_test = true
where id = '3a333333-3333-4333-8333-333333333333';

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, is_test
) values
  (
    '3b111111-1111-4111-8111-111111111111',
    '3a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Relatorio', 'Centro', 'Rua do Relatorio', '1',
    '80030010', -25.43, -49.27, 4000, 'cnpj', '19000000000910', '4191000910',
    'approved', false
  ),
  (
    '3b222222-2222-4222-8222-222222222222',
    '3a333333-3333-4333-8333-333333333333',
    'curitiba', 'Casa Relatorio Teste', 'Centro', 'Rua do Ensaio', '2',
    '80030020', -25.43, -49.27, 4000, 'cnpj', '19000000000921', '4191000921',
    'approved', true
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    '3c111111-1111-4111-8111-111111111111',
    '3b111111-1111-4111-8111-111111111111',
    'Sala Relatorio', '', 4, 2, 60, 'medium', 10000
  ),
  (
    '3c222222-2222-4222-8222-222222222222',
    '3b222222-2222-4222-8222-222222222222',
    'Sala Ensaio', '', 4, 2, 60, 'medium', 10000
  );

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  ('3d111111-1111-4111-8111-111111111111', '3c111111-1111-4111-8111-111111111111', '2027-12-20 18:00:00+00', 'partner_grid'),
  ('3d222222-2222-4222-8222-222222222222', '3c222222-2222-4222-8222-222222222222', '2027-12-20 19:00:00+00', 'partner_grid'),
  ('3d333333-3333-4333-8333-333333333333', '3c111111-1111-4111-8111-111111111111', '2027-12-20 20:00:00+00', 'partner_grid');

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    '3e111111-1111-4111-8111-111111111111', 'curitiba',
    '3b111111-1111-4111-8111-111111111111',
    '3c111111-1111-4111-8111-111111111111',
    '3d111111-1111-4111-8111-111111111111',
    '2027-12-20 18:00:00+00', 4, 2, 10000,
    '3a222222-2222-4222-8222-222222222222'
  ),
  (
    '3e222222-2222-4222-8222-222222222222', 'curitiba',
    '3b111111-1111-4111-8111-111111111111',
    '3c111111-1111-4111-8111-111111111111',
    '3d333333-3333-4333-8333-333333333333',
    '2027-12-20 20:00:00+00', 4, 2, 10000,
    '3a333333-3333-4333-8333-333333333333'
  ),
  (
    '3e333333-3333-4333-8333-333333333333', 'curitiba',
    '3b222222-2222-4222-8222-222222222222',
    '3c222222-2222-4222-8222-222222222222',
    '3d222222-2222-4222-8222-222222222222',
    '2027-12-20 19:00:00+00', 4, 2, 10000,
    '3a333333-3333-4333-8333-333333333333'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
  charged_amount_cents, buyer_interest_cents, first_booking_discount_cents,
  subsidy_cents, points_redeemed, house_fixed_cents, billing_type, status,
  idempotency_key, provider_ref, commission_bps
) values
  (
    '3f111111-1111-4111-8111-111111111111',
    '3e111111-1111-4111-8111-111111111111',
    '3a222222-2222-4222-8222-222222222222',
    '3b111111-1111-4111-8111-111111111111',
    10000, 10100, 10000, 0, 0, 100, 100, 8000,
    'PIX', 'paid', 'idem-relatorio-real', 'pay_relatorio_real', 2500
  ),
  (
    '3f222222-2222-4222-8222-222222222222',
    '3e222222-2222-4222-8222-222222222222',
    '3a333333-3333-4333-8333-333333333333',
    '3b111111-1111-4111-8111-111111111111',
    10000, 10050, 10000, 0, 0, 50, 50, 8000,
    'PIX', 'paid', 'idem-relatorio-conta', 'pay_relatorio_conta', 2500
  ),
  (
    '3f333333-3333-4333-8333-333333333333',
    '3e333333-3333-4333-8333-333333333333',
    '3a333333-3333-4333-8333-333333333333',
    '3b222222-2222-4222-8222-222222222222',
    10000, 10400, 10000, 0, 0, 400, 400, 8000,
    'PIX', 'paid', 'idem-relatorio-casa', 'pay_relatorio_casa', 2500
  );

insert into public.ledger_entries (
  venue_id, user_id, account, direction, kind, amount_cents
) values
  (
    '3b111111-1111-4111-8111-111111111111',
    '3a222222-2222-4222-8222-222222222222',
    'platform', 'credit', 'commission', 3000
  ),
  (
    '3b222222-2222-4222-8222-222222222222',
    '3a333333-3333-4333-8333-333333333333',
    'platform', 'credit', 'commission', 9000
  );

do $$
begin
  if exists (
    select 1 from public.venues
    where name = 'Casa Teste ScapeMatch' and is_test = false
  ) then
    raise exception 'Casa Teste ScapeMatch ficou sem a marca';
  end if;
end $$;

do $$
declare
  v_name text;
begin
  foreach v_name in array array[
    'public.admin_earnings_report(timestamptz,timestamptz,uuid,boolean)',
    'public.admin_search_players(text,boolean,integer,integer)',
    'public.admin_search_audit(text,text,timestamptz,timestamptz,integer,integer)',
    'public.admin_commission_history(uuid,integer,integer)',
    'public.admin_rule_history(text,integer,integer)',
    'public.admin_checkout_settings()',
    'public.admin_save_checkout(text,integer,integer,integer,integer)'
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
      or has_function_privilege('public', v_name, 'execute')
      or not has_function_privilege('authenticated', v_name, 'execute')
    then
      raise exception 'grant de % saiu do combinado', v_name;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.rule_change_log', 'select')
    or has_table_privilege('authenticated', 'public.rule_change_log', 'select')
    or has_table_privilege('anon', 'public.admin_checkout_config', 'select')
    or has_table_privilege('authenticated', 'public.admin_checkout_config', 'select')
  then
    raise exception 'tabela de regra aberta';
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', '3a222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role anon;
do $$
begin
  perform public.admin_search_players();
  raise exception 'anon listou jogador';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '3a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_save_checkout('CONFIG', 3, 199, 49, 299);
  raise exception 'aal1 gravou config';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
update public.platform_settings
set pix_receipt_fee_cents = 321
where id = 1;
select set_config('request.jwt.claim.sub', '3a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_point bigint;
  v_plain jsonb;
  v_wide jsonb;
  v_hidden jsonb;
  v_players jsonb;
  v_page jsonb;
  v_rules jsonb;
  v_saved jsonb;
  v_audit jsonb;
begin
  v_plain := public.admin_earnings(
    null, null, '3b111111-1111-4111-8111-111111111111'
  );
  if (v_plain ->> 'gross_commission_cents')::bigint <> 3000
    or (v_plain ->> 'rewards_subsidy_cents')::bigint <> 100
    or (v_plain ->> 'rewards_points_cents')::bigint < 100
    or (v_plain ->> 'rewards_points_cents')::bigint % 100 <> 0
    or (v_plain ->> 'rewards_redeemed_cents')::bigint
      <> greatest(
        (v_plain ->> 'rewards_subsidy_cents')::bigint,
        (v_plain ->> 'rewards_points_cents')::bigint
      )
  then
    raise exception 'ganhos misturou teste ou somou recompensa: %', v_plain;
  end if;
  v_point := (v_plain ->> 'rewards_points_cents')::bigint / 100;

  v_hidden := public.admin_earnings(
    null, null, '3b222222-2222-4222-8222-222222222222'
  );
  if (v_hidden ->> 'gross_commission_cents')::bigint <> 0
    or (v_hidden ->> 'rewards_redeemed_cents')::bigint <> 0
  then
    raise exception 'casa de teste entrou no padrao: %', v_hidden;
  end if;

  v_wide := public.admin_earnings_report(
    null, null, '3b222222-2222-4222-8222-222222222222', true
  );
  if (v_wide ->> 'gross_commission_cents')::bigint <> 9000
    or (v_wide ->> 'rewards_redeemed_cents')::bigint
      <> greatest(400, 400 * v_point)
  then
    raise exception 'filtro de teste nao mostrou a casa: %', v_wide;
  end if;

  v_wide := public.admin_earnings_report(
    null, null, '3b111111-1111-4111-8111-111111111111', true
  );
  if (v_wide ->> 'rewards_redeemed_cents')::bigint
    <> greatest(100, 100 * v_point) + greatest(50, 50 * v_point)
  then
    raise exception 'conta de teste nao voltou com o filtro: %', v_wide;
  end if;

  v_players := public.admin_search_players('Relatorio Teste', false, 10, 0);
  if (v_players ->> 'total')::integer <> 0 then
    raise exception 'busca padrao mostrou conta de teste: %', v_players;
  end if;
  v_players := public.admin_search_players('Relatorio Jogador', false, 1, 0);
  v_page := public.admin_search_players('Relatorio Jogador', false, 1, 1);
  if (v_players ->> 'total')::integer <> 1
    or jsonb_array_length(v_players -> 'rows') <> 1
    or (v_page ->> 'total')::integer <> 1
    or jsonb_array_length(v_page -> 'rows') <> 0
  then
    raise exception 'pagina de jogador: % / %', v_players, v_page;
  end if;

  v_rules := public.admin_rule_history('platform_settings', 20, 0);
  if not exists (
    select 1
    from jsonb_array_elements(v_rules -> 'rows') item
    where (item ->> 'after_state')::jsonb ->> 'pix_receipt_fee_cents' = '321'
      and item ->> 'actor_id' is null
  ) then
    raise exception 'SQL direto nao entrou no historico: %', v_rules;
  end if;
  v_rules := public.admin_rule_history('admin_checkout_config', 20, 0);
  if not exists (
    select 1
    from jsonb_array_elements(v_rules -> 'rows') item
    where item ->> 'operation' = 'INSERT'
      and item ->> 'actor_id' is null
  ) then
    raise exception 'migration da config nao ficou no historico: %', v_rules;
  end if;

  begin
    perform public.admin_save_checkout('nao', 3, 199, 49, 299);
    raise exception 'config sem a palavra';
  exception
    when sqlstate '22023' then
      null;
  end;

  v_saved := public.admin_save_checkout('CONFIG', 3, 199, 49, 299);
  if (v_saved ->> 'max_interest_free_installments')::integer <> 3
    or (public.admin_checkout_settings() ->> 'charge_function_reads_config')::boolean
  then
    raise exception 'config: %', v_saved;
  end if;
  v_audit := public.admin_search_audit('save_checkout', 'Admin Relatorio', null, null, 10, 0);
  if (v_audit ->> 'total')::integer < 1 then
    raise exception 'auditoria da config: %', v_audit;
  end if;
end $$;
rollback;
