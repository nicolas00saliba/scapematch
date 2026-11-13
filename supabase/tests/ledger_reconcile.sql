-- Conciliação diária. Não fala com o Asaas.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'e8111111-1111-4111-8111-111111111111',
    'admin-conciliacao@example.com',
    '{"display_name":"Admin Conciliacao"}'
  ),
  (
    'e8222222-2222-4222-8222-222222222222',
    'jogador-conciliacao@example.com',
    '{"display_name":"Jogador Conciliacao"}'
  );

insert into public.admins (user_id)
values ('e8111111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'e8200000-0000-4000-8000-000000000001',
  'e8111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa da Conciliacao',
  'Centro',
  'Rua da Conciliacao',
  '1',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '80706050000120',
  '4130000102',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'e8300000-0000-4000-8000-000000000001',
  'e8200000-0000-4000-8000-000000000001',
  'Sala da Conciliacao',
  '',
  4, 2, 60, 'medium', 8000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'e8310000-0000-4000-8000-000000000001',
  'e8300000-0000-4000-8000-000000000001',
  timestamptz '2026-11-12 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'e8400000-0000-4000-8000-000000000001',
  'curitiba',
  'e8200000-0000-4000-8000-000000000001',
  'e8300000-0000-4000-8000-000000000001',
  'e8310000-0000-4000-8000-000000000001',
  timestamptz '2026-11-12 18:00:00+00',
  4, 2, 8000,
  'e8111111-1111-4111-8111-111111111111'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, qr_code, idempotency_key, commission_bps, paid_at
) values (
  'e8500000-0000-4000-8000-000000000001',
  'e8400000-0000-4000-8000-000000000001',
  'e8222222-2222-4222-8222-222222222222',
  'e8200000-0000-4000-8000-000000000001',
  8000, 'PIX', 'paid',
  'pay_conciliacao', 'segredo-qr-nao-sair', 'idem-conciliacao', 2500,
  timestamptz '2026-11-12 18:05:00+00'
);

insert into public.ledger_entries (
  venue_id, group_id, user_id, account, direction, kind, amount_cents,
  payment_charge_id
) values (
  'e8200000-0000-4000-8000-000000000001',
  'e8400000-0000-4000-8000-000000000001',
  'e8222222-2222-4222-8222-222222222222',
  'house', 'credit', 'house_net', 6000,
  'e8500000-0000-4000-8000-000000000001'
);

insert into public.venue_withdrawals (
  id, venue_id, amount_cents, status, source, period_key, external_reference,
  asaas_transfer_id
) values (
  'e8600000-0000-4000-8000-000000000001',
  'e8200000-0000-4000-8000-000000000001',
  6000, 'done', 'automatic', 'auto:2026-W46-conciliacao',
  'saque-conciliacao', 'tra_conciliacao'
);

do $$
begin
  if has_function_privilege(
    'anon', 'public.ledger_reconcile_snapshot(timestamptz,timestamptz,text[],text[])', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.ledger_reconcile_snapshot(timestamptz,timestamptz,text[],text[])', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.ledger_reconcile_snapshot(timestamptz,timestamptz,text[],text[])', 'execute'
  ) or has_function_privilege(
    'anon', 'public.admin_payment_divergences()', 'execute'
  ) or has_function_privilege(
    'service_role', 'public.admin_payment_divergences()', 'execute'
  ) or has_function_privilege(
    'anon', 'private.invoke_ledger_reconcile()', 'execute'
  ) or has_table_privilege(
    'authenticated', 'public.payment_divergences', 'select'
  ) then
    raise exception 'grant da conciliação saiu do combinado';
  end if;
end $$;

do $$
declare
  v_snap jsonb;
begin
  set local role service_role;
  v_snap := public.ledger_reconcile_snapshot(
    timestamptz '2026-11-01 00:00:00+00',
    timestamptz '2026-11-14 00:00:00+00',
    array['pay_conciliacao'],
    array['tra_conciliacao']
  );
  if not exists (
    select 1 from pg_catalog.jsonb_array_elements(v_snap -> 'charges') item
    where item ->> 'provider_ref' = 'pay_conciliacao'
      and item -> 'ledger_kinds' ? 'house_net'
      and (item ->> 'amount_cents')::integer = 8000
  ) or not exists (
    select 1 from pg_catalog.jsonb_array_elements(v_snap -> 'withdrawals') item
    where item ->> 'asaas_transfer_id' = 'tra_conciliacao'
  ) or v_snap::text like '%segredo-qr-nao-sair%'
    or v_snap::text like '%80706050000120%'
  then
    raise exception 'o retrato do livro saiu errado: %', v_snap;
  end if;
end $$;

do $$
declare
  v_run uuid;
begin
  set local role service_role;
  v_run := public.record_payment_divergences(
    1, 1, false,
    jsonb_build_array(
      jsonb_build_object(
        'kind', 'charge_status',
        'providerRef', 'pay_conciliacao',
        'localId', 'e8500000-0000-4000-8000-000000000001',
        'expected', 'paid',
        'actual', 'pending'
      ),
      jsonb_build_object(
        'kind', 'segredo',
        'providerRef', 'nao-grava',
        'localId', '',
        'expected', '',
        'actual', ''
      )
    )
  );
  if v_run is null then
    raise exception 'a divergência não foi gravada';
  end if;
end $$;

do $$
declare
  v_board jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'e8222222-2222-4222-8222-222222222222', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  perform public.admin_payment_divergences();
  raise exception 'jogador leu a conciliação';
exception
  when others then
    if sqlerrm <> 'not admin' then
      raise;
    end if;
end $$;

do $$
declare
  v_board jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'e8111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_board := public.admin_payment_divergences();
  if (v_board -> 'run' ->> 'divergence_count')::integer <> 1
    or v_board -> 'rows' -> 0 ->> 'kind' is distinct from 'charge_status'
    or v_board::text like '%nao-grava%'
    or v_board::text like '%80706050000120%'
  then
    raise exception 'o admin não viu a divergência: %', v_board;
  end if;
end $$;

do $$
begin
  perform private.invoke_ledger_reconcile();
  raise exception 'config ausente não falhou';
exception
  when others then
    if sqlerrm not like 'ledger_reconcile_config_ausente:%' then
      raise;
    end if;
end $$;

create schema if not exists net;

create table if not exists net._http_response (
  id bigint primary key,
  status_code integer,
  timed_out boolean,
  error_msg text
);

create or replace function net.http_post(
  url text,
  body jsonb,
  headers jsonb,
  timeout_milliseconds integer
) returns bigint
language plpgsql
as $$
begin
  if url not like 'https://%' then
    raise exception 'url do cron invalida';
  end if;
  return 77;
end;
$$;

select vault.create_secret(
  'https://example.test/ledger-reconcile',
  'ledger_reconcile_url',
  'url de teste'
);

select vault.create_secret(
  'segredo-do-cron-teste',
  'ledger_reconcile_secret',
  'segredo de teste'
);

select private.invoke_ledger_reconcile();

do $$
begin
  if not exists (
    select 1 from public.ledger_reconcile_dispatches where request_id = 77
  ) or exists (
    select 1 from public.ledger_reconcile_dispatches
    where request_id::text like '%segredo%'
  ) then
    raise exception 'o cron não guardou só o id do pedido';
  end if;
end $$;

insert into net._http_response (id, status_code, timed_out)
values (77, 500, false);

do $$
begin
  perform private.check_ledger_reconcile_response();
  raise exception 'resposta de erro não falhou';
exception
  when others then
    if sqlerrm is distinct from 'ledger_reconcile_http_erro' then
      raise;
    end if;
end $$;

update net._http_response set status_code = 200 where id = 77;

select private.check_ledger_reconcile_response();
