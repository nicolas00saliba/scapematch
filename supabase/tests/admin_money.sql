-- Admin de dinheiro. Anon e sessão sem aal2 não passam.
-- Liberar custódia só zera a tentativa, e só depois do horário.
-- Reembolso parcial não entra na fila. A menos de 2h do início, também não.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('1a111111-1111-4111-8111-111111111111', 'money-admin@example.com', '{"display_name":"Admin Dinheiro"}'),
  ('1a222222-2222-4222-8222-222222222222', 'money-player@example.com', '{"display_name":"Ana Dinheiro"}'),
  ('1a333333-3333-4333-8333-333333333333', 'money-test@example.com', '{"display_name":"Conta Teste"}'),
  ('1a444444-4444-4444-8444-444444444444', 'money-bia@example.com', '{"display_name":"Bia Horario"}');

insert into public.admins (user_id)
values ('1a111111-1111-4111-8111-111111111111');

update public.profiles
set is_test = true
where id = '1a333333-3333-4333-8333-333333333333';

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, is_test
) values
  (
    '1b111111-1111-4111-8111-111111111111',
    '1a222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Dinheiro', 'Centro', 'Rua do Caixa', '8',
    '80010010', -25.43, -49.27, 4000, 'cnpj', '19000000000782', '4191000782',
    'approved', false
  ),
  (
    '1b222222-2222-4222-8222-222222222222',
    '1a333333-3333-4333-8333-333333333333',
    'curitiba', 'Casa Teste Dinheiro', 'Centro', 'Rua do Ensaio', '9',
    '80010020', -25.43, -49.27, 4000, 'cnpj', '19000000000793', '4191000793',
    'approved', true
  ),
  (
    '1b333333-3333-4333-8333-333333333333',
    '1a444444-4444-4444-8444-444444444444',
    'curitiba', 'Casa Horario', 'Centro', 'Rua do Relogio', '10',
    '80010030', -25.43, -49.27, 4000, 'cnpj', '19000000000848', '4191000848',
    'approved', false
  );

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    '1c111111-1111-4111-8111-111111111111',
    '1b111111-1111-4111-8111-111111111111',
    'Sala do Caixa', '', 6, 2, 60, 'medium', 10000
  ),
  (
    '1c222222-2222-4222-8222-222222222222',
    '1b222222-2222-4222-8222-222222222222',
    'Sala de Ensaio', '', 6, 2, 60, 'medium', 10000
  ),
  (
    '1c333333-3333-4333-8333-333333333333',
    '1b333333-3333-4333-8333-333333333333',
    'Sala do Relogio', '', 6, 2, 60, 'medium', 10000
  );

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  ('1d111111-1111-4111-8111-111111111111', '1c111111-1111-4111-8111-111111111111', '2027-12-10 18:00:00+00', 'partner_grid'),
  ('1d222222-2222-4222-8222-222222222222', '1c222222-2222-4222-8222-222222222222', '2027-12-10 19:00:00+00', 'partner_grid'),
  ('1d333333-3333-4333-8333-333333333333', '1c333333-3333-4333-8333-333333333333', pg_catalog.now() - interval '1 day', 'partner_grid'),
  ('1d444444-4444-4444-8444-444444444444', '1c333333-3333-4333-8333-333333333333', pg_catalog.now() + interval '30 minutes', 'partner_grid');

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    '1e111111-1111-4111-8111-111111111111', 'curitiba',
    '1b111111-1111-4111-8111-111111111111',
    '1c111111-1111-4111-8111-111111111111',
    '1d111111-1111-4111-8111-111111111111',
    '2027-12-10 18:00:00+00', 6, 2, 10000,
    '1a222222-2222-4222-8222-222222222222'
  ),
  (
    '1e222222-2222-4222-8222-222222222222', 'curitiba',
    '1b222222-2222-4222-8222-222222222222',
    '1c222222-2222-4222-8222-222222222222',
    '1d222222-2222-4222-8222-222222222222',
    '2027-12-10 19:00:00+00', 6, 2, 10000,
    '1a333333-3333-4333-8333-333333333333'
  ),
  (
    '1e333333-3333-4333-8333-333333333333', 'curitiba',
    '1b333333-3333-4333-8333-333333333333',
    '1c333333-3333-4333-8333-333333333333',
    '1d333333-3333-4333-8333-333333333333',
    pg_catalog.now() - interval '1 day', 6, 2, 10000,
    '1a444444-4444-4444-8444-444444444444'
  ),
  (
    '1e444444-4444-4444-8444-444444444444', 'curitiba',
    '1b333333-3333-4333-8333-333333333333',
    '1c333333-3333-4333-8333-333333333333',
    '1d444444-4444-4444-8444-444444444444',
    pg_catalog.now() + interval '30 minutes', 6, 2, 10000,
    '1a444444-4444-4444-8444-444444444444'
  );

update public.groups
set closed_at = timestamptz '2027-12-10 18:10:00+00',
    confirmed_at = timestamptz '2027-12-10 18:10:00+00'
where id = '1e111111-1111-4111-8111-111111111111';

update public.groups
set closed_at = pg_catalog.now() - interval '1 day',
    confirmed_at = pg_catalog.now() - interval '1 day'
where id = '1e333333-3333-4333-8333-333333333333';

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  (
    '1f111111-1111-4111-8111-111111111111',
    '1e111111-1111-4111-8111-111111111111',
    '1a222222-2222-4222-8222-222222222222',
    'Ana Dinheiro', true, 'paid'
  ),
  (
    '1f222222-2222-4222-8222-222222222222',
    '1e222222-2222-4222-8222-222222222222',
    '1a333333-3333-4333-8333-333333333333',
    'Conta Teste', true, 'paid'
  ),
  (
    '1f333333-3333-4333-8333-333333333333',
    '1e333333-3333-4333-8333-333333333333',
    '1a444444-4444-4444-8444-444444444444',
    'Bia Horario', true, 'paid'
  ),
  (
    '1f444444-4444-4444-8444-444444444444',
    '1e444444-4444-4444-8444-444444444444',
    '1a444444-4444-4444-8444-444444444444',
    'Bia Horario', true, 'paid'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
  charged_amount_cents, buyer_interest_cents, first_booking_discount_cents,
  subsidy_cents, points_redeemed, house_fixed_cents, billing_type, status,
  idempotency_key, provider_ref, provider_split_id, commission_bps,
  custody_release_attempts, custody_release_failed_at
) values
  (
    '1c311111-1111-4111-8111-111111111111',
    '1e111111-1111-4111-8111-111111111111',
    '1a222222-2222-4222-8222-222222222222',
    '1b111111-1111-4111-8111-111111111111',
    10000, 10600, 12000, 2000, 500, 100, 100, 8000,
    'CREDIT_CARD', 'paid',
    'idem-dinheiro-ana', 'pay_dinheiro', 'spl_dinheiro', 2500,
    8, timestamptz '2027-12-10 19:00:00+00'
  ),
  (
    '1c322222-2222-4222-8222-222222222222',
    '1e222222-2222-4222-8222-222222222222',
    '1a333333-3333-4333-8333-333333333333',
    '1b222222-2222-4222-8222-222222222222',
    10000, null, 10000, 0, 0, 0, 0, 8000,
    'PIX', 'paid',
    'idem-dinheiro-teste', 'pay_teste', 'spl_teste', 2500,
    0, null
  ),
  (
    '1c333333-3333-4333-8333-333333333333',
    '1e333333-3333-4333-8333-333333333333',
    '1a444444-4444-4444-8444-444444444444',
    '1b333333-3333-4333-8333-333333333333',
    10000, null, 10000, 0, 0, 0, 0, 8000,
    'PIX', 'paid',
    'idem-dinheiro-passada', 'pay_passada', 'spl_passada', 2500,
    4, pg_catalog.now() - interval '2 hours'
  ),
  (
    '1c344444-4444-4444-8444-444444444444',
    '1e444444-4444-4444-8444-444444444444',
    '1a444444-4444-4444-8444-444444444444',
    '1b333333-3333-4333-8333-333333333333',
    10000, null, 10000, 0, 0, 0, 0, 8000,
    'PIX', 'paid',
    'idem-dinheiro-perto', 'pay_perto', 'spl_perto', 2500,
    0, null
  );

insert into public.platform_cac_transfers (
  id, payment_charge_id, venue_id, amount_cents, assumed_cents,
  status, attempts, last_error, failed_at
) values (
  '1c411111-1111-4111-8111-111111111111',
  '1c311111-1111-4111-8111-111111111111',
  '1b111111-1111-4111-8111-111111111111',
  1000, 1000, 'failed', 8, 'saldo', timestamptz '2027-12-10 20:00:00+00'
);

do $$
declare
  v_name text;
begin
  foreach v_name in array array[
    'public.admin_search_charges(text,uuid,text,boolean,integer,integer)',
    'public.admin_search_refund_queue(text,text,boolean,integer,integer)',
    'public.admin_refund_charge(uuid,text,integer)',
    'public.admin_reopen_custody(uuid,text)',
    'public.admin_reopen_cac(uuid,text)',
    'public.admin_cac_transfers_flag()'
  ]
  loop
    if not exists (
      select 1
      from pg_proc p
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
end $$;

begin;
select set_config('request.jwt.claim.sub', '1a222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role anon;
do $$
begin
  perform public.admin_search_charges();
  raise exception 'anon listou cobranca';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '1a222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
begin
  perform public.admin_reopen_custody(
    '1c311111-1111-4111-8111-111111111111', 'LIBERAR'
  );
  raise exception 'jogador liberou custodia';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '1a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_refund_charge(
    '1c311111-1111-4111-8111-111111111111', 'REEMBOLSAR'
  );
  raise exception 'admin sem aal2 estornou';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '1a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_page jsonb;
  v_detail jsonb;
  v_flag jsonb;
  v_open jsonb;
begin
  v_page := public.admin_search_charges('Dinheiro', null, 'paid', false, 40, 0);
  if (v_page ->> 'total')::integer <> 1
    or v_page -> 'rows' -> 0 ->> 'player_name' <> 'Ana Dinheiro'
    or v_page -> 'rows' -> 0 ->> 'custody' <> 'falha'
    or (v_page -> 'rows' -> 0 ->> 'buyer_interest_cents')::integer <> 2000
    or (v_page -> 'rows' -> 0 ->> 'house_fixed_cents')::integer <> 8000
  then
    raise exception 'busca de cobranca: %', v_page;
  end if;
  if (public.admin_search_charges(null, null, null, true, 40, 0) ->> 'total')::integer < 2
  then
    raise exception 'filtro de teste nao mostrou a casa';
  end if;

  v_detail := public.admin_charge('1c311111-1111-4111-8111-111111111111');
  if v_detail ->> 'room_name' <> 'Sala do Caixa'
    or (v_detail ->> 'first_booking_discount_cents')::integer <> 500
    or (v_detail ->> 'points_redeemed')::integer <> 100
    or (v_detail ->> 'full_refund_cents')::integer <> 12000
    or v_detail ->> 'group_closed' <> 'true'
  then
    raise exception 'detalhe da cobranca: %', v_detail;
  end if;

  v_flag := public.admin_cac_transfers_flag();
  if v_flag ->> 'name' <> 'PAGBANK_CAC_TRANSFERS'
    or v_flag ->> 'readable' <> 'false'
    or v_flag -> 'enabled' <> 'null'::jsonb
  then
    raise exception 'flag do CAC: %', v_flag;
  end if;

  begin
    perform public.admin_refund_charge(
      '1c311111-1111-4111-8111-111111111111', 'REEMBOLSAR', 100
    );
    raise exception 'parcial passou';
  exception
    when sqlstate '22023' then
      if sqlerrm not like '%parcial%' then
        raise;
      end if;
  end;

  begin
    perform public.admin_reopen_custody(
      '1c311111-1111-4111-8111-111111111111', 'LIBERAR'
    );
    raise exception 'custodia saiu antes da sessao';
  exception
    when sqlstate 'P0001' then
      if sqlerrm not like '%custodia antes do horario%' then
        raise;
      end if;
  end;

  v_open := public.admin_reopen_custody(
    '1c333333-3333-4333-8333-333333333333', 'LIBERAR'
  );
  if v_open ->> 'group_ready' <> 'true'
    or (v_open ->> 'attempts')::integer <> 0
  then
    raise exception 'reabrir custodia: %', v_open;
  end if;
end $$;
reset role;
do $$
begin
  if exists (
    select 1 from public.payment_charges
    where id = '1c311111-1111-4111-8111-111111111111'
      and (
        custody_released_at is not null
        or custody_release_attempts <> 8
        or custody_release_failed_at is null
      )
  ) then
    raise exception 'custodia futura foi mexida';
  end if;
  if exists (
    select 1 from public.payment_charges
    where id = '1c333333-3333-4333-8333-333333333333'
      and (
        custody_released_at is not null
        or custody_release_attempts <> 0
        or custody_release_failed_at is not null
      )
  ) then
    raise exception 'custodia da sessao passada nao reabriu';
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '1a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_refund jsonb;
  v_cac jsonb;
  v_queue jsonb;
begin
  begin
    perform public.admin_refund_charge(
      '1c311111-1111-4111-8111-111111111111', 'NAO'
    );
    raise exception 'confirmacao fraca passou';
  exception
    when sqlstate '22023' then
      null;
  end;

  begin
    perform public.admin_refund_charge(
      '1c344444-4444-4444-8444-444444444444', 'REEMBOLSAR'
    );
    raise exception 'reembolso perto do inicio passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm not like '%menos de 2h%' then
        raise;
      end if;
  end;

  v_refund := public.admin_refund_charge(
    '1c311111-1111-4111-8111-111111111111', 'REEMBOLSAR'
  );
  perform public.admin_refund_charge(
    '1c311111-1111-4111-8111-111111111111', 'REEMBOLSAR'
  );
  if v_refund ->> 'queued' <> 'true'
    or (v_refund ->> 'amount_cents')::integer <> 12000
  then
    raise exception 'estorno: %', v_refund;
  end if;

  v_cac := public.admin_reopen_cac(
    '1c311111-1111-4111-8111-111111111111', 'REPROCESSAR'
  );
  if v_cac ->> 'status' <> 'pending'
    or (v_cac ->> 'attempts')::integer <> 0
  then
    raise exception 'reprocessar CAC: %', v_cac;
  end if;

  v_queue := public.admin_search_refund_queue('Ana Dinheiro', 'queued', false, 40, 0);
  if (v_queue ->> 'total')::integer <> 1
    or v_queue -> 'rows' -> 0 ->> 'action' <> 'refund'
    or v_queue -> 'rows' -> 0 ->> 'player_name' <> 'Ana Dinheiro'
  then
    raise exception 'fila: %', v_queue;
  end if;
end $$;
reset role;
do $$
begin
  if exists (
    select 1 from public.group_members
    where id = '1f111111-1111-4111-8111-111111111111'
      and attendance = 'cancelled'
  ) then
    raise exception 'estorno do painel tirou a pessoa do grupo';
  end if;
  if not exists (
    select 1 from public.member_refund_queue
    where charge_id = '1c311111-1111-4111-8111-111111111111'
      and action = 'refund'
      and status = 'queued'
  ) then
    raise exception 'fila nao recebeu o estorno integral';
  end if;
  if exists (
    select 1 from public.member_refund_queue
    where charge_id = '1c344444-4444-4444-8444-444444444444'
  ) then
    raise exception 'reembolso perto do inicio entrou na fila';
  end if;
  if (
    select count(*) from public.admin_audit_log
    where action = 'refund_charge'
      and target_id = '1c311111-1111-4111-8111-111111111111'
  ) <> 1 then
    raise exception 'segundo reembolso gravou outra auditoria';
  end if;
  if not exists (
    select 1 from public.platform_cac_transfers
    where payment_charge_id = '1c311111-1111-4111-8111-111111111111'
      and status = 'pending'
      and attempts = 0
      and last_error is null
  ) then
    raise exception 'CAC nao voltou para pending';
  end if;
  if not exists (
    select 1 from public.admin_audit_log
    where actor_id = '1a111111-1111-4111-8111-111111111111'
      and action = 'refund_charge'
  ) or not exists (
    select 1 from public.admin_audit_log
    where action = 'reopen_cac'
  ) then
    raise exception 'auditoria do dinheiro incompleta';
  end if;
end $$;
rollback;
