-- Painel de pagamentos. Não fala com o Asaas.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'd7111111-1111-4111-8111-111111111111',
    'admin-pagamentos@example.com',
    '{"display_name":"Admin Pagamentos"}'
  ),
  (
    'd7222222-2222-4222-8222-222222222222',
    'jogador-pagamentos@example.com',
    '{"display_name":"Jogador Pagamentos"}'
  );

insert into public.admins (user_id)
values ('d7111111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'd7200000-0000-4000-8000-000000000001',
  'd7111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa do Painel',
  'Centro',
  'Rua do Painel',
  '1',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '90807060000103',
  '4130000101',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'd7300000-0000-4000-8000-000000000001',
  'd7200000-0000-4000-8000-000000000001',
  'Sala do Painel',
  '',
  4, 2, 60, 'medium', 8000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'd7310000-0000-4000-8000-000000000001',
  'd7300000-0000-4000-8000-000000000001',
  timestamptz '2026-11-12 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'd7400000-0000-4000-8000-000000000001',
  'curitiba',
  'd7200000-0000-4000-8000-000000000001',
  'd7300000-0000-4000-8000-000000000001',
  'd7310000-0000-4000-8000-000000000001',
  timestamptz '2026-11-12 18:00:00+00',
  4, 2, 8000,
  'd7111111-1111-4111-8111-111111111111'
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'd7310000-0000-4000-8000-000000000002',
  'd7300000-0000-4000-8000-000000000001',
  timestamptz '2026-11-13 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'd7400000-0000-4000-8000-000000000002',
  'curitiba',
  'd7200000-0000-4000-8000-000000000001',
  'd7300000-0000-4000-8000-000000000001',
  'd7310000-0000-4000-8000-000000000002',
  timestamptz '2026-11-13 18:00:00+00',
  4, 2, 8000,
  'd7111111-1111-4111-8111-111111111111'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, qr_code, idempotency_key, commission_bps, paid_at
) values (
  'd7500000-0000-4000-8000-000000000001',
  'd7400000-0000-4000-8000-000000000001',
  'd7222222-2222-4222-8222-222222222222',
  'd7200000-0000-4000-8000-000000000001',
  8000, 'PIX', 'paid',
  'pay_painel', 'segredo-qr-nao-sair', 'idem-painel-paga', 2500,
  timestamptz '2026-11-12 18:05:00+00'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, refunded_at
) values (
  'd7500000-0000-4000-8000-000000000002',
  'd7400000-0000-4000-8000-000000000002',
  'd7222222-2222-4222-8222-222222222222',
  'd7200000-0000-4000-8000-000000000001',
  4500, 'PIX', 'refunded',
  'pay_estorno_painel', 'idem-painel-estorno', 2500,
  timestamptz '2026-11-13 12:00:00+00'
);

insert into public.venue_withdrawals (
  venue_id, amount_cents, status, source, period_key, external_reference,
  asaas_transfer_id, receipt_url
) values (
  'd7200000-0000-4000-8000-000000000001',
  6000, 'done', 'automatic', 'auto:2026-W46',
  'saque-painel', 'tra_painel', 'https://example.com/recibo-secreto'
);

do $$
begin
  if has_function_privilege(
    'anon', 'public.admin_payments_board()', 'execute'
  ) or has_function_privilege(
    'service_role', 'public.admin_payments_board()', 'execute'
  ) or not has_function_privilege(
    'authenticated', 'public.admin_payments_board()', 'execute'
  ) or has_function_privilege(
    'anon', 'public.note_webhook_error(text,text,text)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.note_webhook_error(text,text,text)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.note_webhook_error(text,text,text)', 'execute'
  ) or has_table_privilege(
    'authenticated', 'public.payment_webhook_errors', 'select'
  ) then
    raise exception 'grant do painel de pagamentos saiu do combinado';
  end if;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'd7222222-2222-4222-8222-222222222222', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  perform public.admin_payments_board();
  raise exception 'jogador leu o painel';
exception
  when others then
    if sqlerrm <> 'not admin' then
      raise;
    end if;
end $$;

do $$
begin
  set local role authenticated;
  perform public.note_webhook_error('asaas-webhook', 'internal_error', 'pay_x');
  raise exception 'authenticated anotou erro de webhook';
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  set local role service_role;
  perform public.note_webhook_error(
    'asaas-webhook',
    'cartão não encontrado',
    'pay_painel segredo'
  );
  perform public.note_webhook_error(
    'asaas-transfer-webhook',
    'internal_error',
    'tra_painel'
  );
  perform public.note_webhook_error('outro', 'internal_error', 'tra_painel');
end $$;

do $$
declare
  v_board jsonb;
  v_audit integer;
begin
  perform set_config(
    'request.jwt.claim.sub', 'd7111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  perform public.admin_set_venue_payouts_enabled(true);
  v_board := public.admin_payments_board();
  if (v_board -> 'readiness' ->> 'venue_payouts_enabled') is distinct from 'true'
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_board -> 'charges') item
      where item ->> 'provider_ref' = 'pay_painel'
        and item ->> 'venue_name' = 'Casa do Painel'
    )
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_board -> 'refunds') item
      where item ->> 'provider_ref' = 'pay_estorno_painel'
    )
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_board -> 'withdrawals') item
      where item ->> 'asaas_transfer_id' = 'tra_painel'
        and item ->> 'venue_name' = 'Casa do Painel'
    )
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_board -> 'webhook_errors') item
      where item ->> 'code' = 'internal_error'
        and item ->> 'provider_ref' = 'tra_painel'
    )
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(v_board -> 'webhook_errors') item
      where item ->> 'code' = 'unknown'
        and item ->> 'provider_ref' = ''
    )
  then
    raise exception 'o painel não montou a lista: %', v_board;
  end if;
  if v_board::text like '%segredo-qr-nao-sair%'
    or v_board::text like '%90807060000103%'
    or v_board::text like '%recibo-secreto%'
    or v_board::text like '%cartão%'
  then
    raise exception 'o painel vazou dado';
  end if;
  reset role;
  select count(*) into v_audit
  from public.admin_audit_log
  where action = 'set_venue_payouts_enabled'
    and actor_id = 'd7111111-1111-4111-8111-111111111111'
    and after_state ->> 'enabled' = 'true';
  if v_audit < 1 then
    raise exception 'ligar os saques não entrou na auditoria';
  end if;
end $$;
