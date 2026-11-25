-- Custódia só depois do horário. Grupo ou sessão cancelados não liberam.
-- Saldo da conta PJ alerta abaixo do limite e não no limite.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('d8c10000-0000-4000-8000-000000000001', 'custodia-dono@example.com', '{"display_name":"Dono"}'),
  ('d8c10000-0000-4000-8000-000000000002', 'custodia-jog@example.com', '{"display_name":"Jog"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'd8c20000-0000-4000-8000-000000000001',
  'd8c10000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Custodia', 'Centro', 'Rua da Sessao', '9',
  '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000983',
  '4130000983', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'd8c30000-0000-4000-8000-000000000001',
  'd8c20000-0000-4000-8000-000000000001',
  'Sala Custodia', '', 6, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability, cancelled_at)
values
  ('d8c31000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', '2026-12-01 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000002', 'd8c30000-0000-4000-8000-000000000001', '2026-11-01 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000003', 'd8c30000-0000-4000-8000-000000000001', '2026-11-02 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000004', 'd8c30000-0000-4000-8000-000000000001', '2026-11-03 18:00:00+00', 'partner_grid', '2026-11-03 12:00:00+00'),
  ('d8c31000-0000-4000-8000-000000000005', 'd8c30000-0000-4000-8000-000000000001', '2026-11-04 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000006', 'd8c30000-0000-4000-8000-000000000001', '2026-12-20 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000007', 'd8c30000-0000-4000-8000-000000000001', '2026-11-05 18:00:00+00', 'partner_grid', null),
  ('d8c31000-0000-4000-8000-000000000008', 'd8c30000-0000-4000-8000-000000000001', '2026-11-06 18:00:00+00', 'partner_grid', null);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, confirmed_at, cancelled_at
) values
  ('d8c40000-0000-4000-8000-000000000001', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000001', '2026-12-01 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-11-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000002', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000002', '2026-11-01 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000003', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000003', '2026-11-02 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', '2026-11-02 12:00:00+00'),
  ('d8c40000-0000-4000-8000-000000000004', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000004', '2026-11-03 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000005', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000005', '2026-11-04 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000006', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000006', '2026-11-01 12:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000007', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000007', '2026-12-15 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-10-20 12:00:00+00', null),
  ('d8c40000-0000-4000-8000-000000000008', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000008', '2026-11-06 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', null, null);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider, provider_ref, provider_split_id, idempotency_key, wallet_id,
  commission_bps, paid_at, refund_requested_at, custody_release_attempts
) values
  ('d8c50000-0000-4000-8000-000000000001', 'd8c40000-0000-4000-8000-000000000001', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_FUTURO', 'SPLI_FUTURO', 'idem-custodia-futuro', 'wal', 1000, '2026-11-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000002', 'd8c40000-0000-4000-8000-000000000002', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_PRONTO', 'SPLI_PRONTO', 'idem-custodia-pronto', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000003', 'd8c40000-0000-4000-8000-000000000003', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_GRUPO', 'SPLI_GRUPO', 'idem-custodia-grupo', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000004', 'd8c40000-0000-4000-8000-000000000004', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_SESSAO', 'SPLI_SESSAO', 'idem-custodia-sessao', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000005', 'd8c40000-0000-4000-8000-000000000005', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_ESTORNO', 'SPLI_ESTORNO', 'idem-custodia-estorno', 'wal', 1000, '2026-10-20 12:00:00+00', '2026-11-04 10:00:00+00', 0),
  ('d8c50000-0000-4000-8000-000000000006', 'd8c40000-0000-4000-8000-000000000006', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_SESSAO_TARDE', 'SPLI_TARDE', 'idem-custodia-tarde', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000007', 'd8c40000-0000-4000-8000-000000000007', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_SESSAO_CEDO', 'SPLI_CEDO', 'idem-custodia-cedo', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0),
  ('d8c50000-0000-4000-8000-000000000008', 'd8c40000-0000-4000-8000-000000000008', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_ABERTO', 'SPLI_ABERTO', 'idem-custodia-aberto', 'wal', 1000, '2026-10-20 12:00:00+00', null, 0);

do $$
declare
  v_now timestamptz := '2026-11-25 15:00:00+00';
  v_due uuid;
  v_limit integer;
begin
  if has_function_privilege(
    'anon', 'public.custody_release_due(uuid,timestamptz)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.custody_release_due(uuid,timestamptz)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.custody_release_due(uuid,timestamptz)', 'execute'
  ) or has_function_privilege(
    'anon', 'public.pj_balance_alert_due(bigint)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.low_balance_alert_cents()', 'execute'
  ) then
    raise exception 'grant da custódia ou do saldo saiu do combinado';
  end if;

  if public.low_balance_alert_cents() <> 100000 then
    raise exception 'limite padrão %', public.low_balance_alert_cents();
  end if;

  if public.custody_release_due('d8c50000-0000-4000-8000-000000000001', v_now) then
    raise exception 'liberou antes do starts_at';
  end if;
  if not public.custody_release_due('d8c50000-0000-4000-8000-000000000002', v_now) then
    raise exception 'não liberou depois do starts_at';
  end if;
  if public.custody_release_due(
    'd8c50000-0000-4000-8000-000000000002',
    '2026-11-01 18:00:00+00'
  ) is not true then
    raise exception 'não liberou no instante do starts_at';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000003', v_now) then
    raise exception 'liberou grupo cancelado';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000004', v_now) then
    raise exception 'liberou sessão cancelada';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000005', v_now) then
    raise exception 'liberou cobrança estornada';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000006', '2026-11-10 12:00:00+00') then
    raise exception 'liberou pela hora do grupo com a sessão ainda no futuro';
  end if;
  if not public.custody_release_due('d8c50000-0000-4000-8000-000000000007', '2026-11-20 12:00:00+00') then
    raise exception 'segurou a sessão que já começou';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000008', v_now) then
    raise exception 'liberou grupo que não confirmou';
  end if;

  select id into v_due
  from public.list_due_custody_releases(40, v_now)
  where id = 'd8c50000-0000-4000-8000-000000000002';
  if v_due is null then
    raise exception 'a fila não devolveu a cobrança vencida';
  end if;
  if exists (
    select 1
    from public.list_due_custody_releases(40, v_now)
    where id in (
      'd8c50000-0000-4000-8000-000000000001',
      'd8c50000-0000-4000-8000-000000000003',
      'd8c50000-0000-4000-8000-000000000004',
      'd8c50000-0000-4000-8000-000000000005',
      'd8c50000-0000-4000-8000-000000000006',
      'd8c50000-0000-4000-8000-000000000008'
    )
  ) then
    raise exception 'a fila devolveu cobrança que não pode liberar';
  end if;

  update public.payment_charges
  set custody_release_attempts = 8
  where id = 'd8c50000-0000-4000-8000-000000000002';
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000002', v_now) then
    raise exception 'liberou depois de 8 falhas';
  end if;

  if public.pj_balance_alert_due(99999) is not true
    or public.pj_balance_alert_due(100000) is not false
    or public.pj_balance_alert_due(100001) is not false
  then
    raise exception 'alerta no limite padrão saiu do combinado';
  end if;

  update public.platform_settings
  set low_balance_alert_cents = 50000
  where id = 1;
  select public.low_balance_alert_cents() into v_limit;
  if v_limit <> 50000
    or public.pj_balance_alert_due(49999) is not true
    or public.pj_balance_alert_due(50000) is not false
    or public.pj_balance_alert_due(50001) is not false
    or public.pj_balance_alert_due(-1) is not true
  then
    raise exception 'alerta com limite editado saiu do combinado %', v_limit;
  end if;
end $$;

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  ('d8c31000-0000-4000-8000-000000000009', 'd8c30000-0000-4000-8000-000000000001', '2026-11-07 18:00:00+00', 'partner_grid'),
  ('d8c31000-0000-4000-8000-000000000010', 'd8c30000-0000-4000-8000-000000000001', '2026-11-08 18:00:00+00', 'partner_grid');

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, closes_at
) values
  ('d8c40000-0000-4000-8000-000000000009', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000009', '2026-11-07 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-11-01 12:00:00+00'),
  ('d8c40000-0000-4000-8000-000000000010', 'curitiba', 'd8c20000-0000-4000-8000-000000000001', 'd8c30000-0000-4000-8000-000000000001', 'd8c31000-0000-4000-8000-000000000010', '2026-11-08 18:00:00+00', 4, 2, 10000, 'd8c10000-0000-4000-8000-000000000002', '2026-11-01 12:00:00+00');

insert into public.group_members (group_id, user_id, display_name, joined_at) values
  ('d8c40000-0000-4000-8000-000000000009', 'd8c10000-0000-4000-8000-000000000001', 'Dono', '2026-10-01 12:00:00+00'),
  ('d8c40000-0000-4000-8000-000000000009', 'd8c10000-0000-4000-8000-000000000002', 'Jog', '2026-10-20 12:00:00+00'),
  ('d8c40000-0000-4000-8000-000000000010', 'd8c10000-0000-4000-8000-000000000001', 'Dono', '2026-10-01 12:00:00+00'),
  ('d8c40000-0000-4000-8000-000000000010', 'd8c10000-0000-4000-8000-000000000002', 'Jog', '2026-11-02 12:00:00+00');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider, provider_ref, provider_split_id, idempotency_key, wallet_id,
  commission_bps, paid_at, custody_release_attempts
) values
  ('d8c50000-0000-4000-8000-000000000009', 'd8c40000-0000-4000-8000-000000000009', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_NO_PRAZO', 'SPLI_NO_PRAZO', 'idem-custodia-no-prazo', 'wal', 1000, '2026-10-20 12:00:00+00', 0),
  ('d8c50000-0000-4000-8000-000000000010', 'd8c40000-0000-4000-8000-000000000010', 'd8c10000-0000-4000-8000-000000000002', 'd8c20000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'pagbank', 'CHAR_DEPOIS', 'SPLI_DEPOIS', 'idem-custodia-depois', 'wal', 1000, '2026-10-20 12:00:00+00', 0);

do $$
declare
  v_now timestamptz := '2026-11-25 15:00:00+00';
  v_expired uuid;
begin
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000009', v_now) is not true then
    raise exception 'não liberou mínimo atingido antes do prazo sem confirmed_at';
  end if;
  if public.custody_release_due('d8c50000-0000-4000-8000-000000000010', v_now) then
    raise exception 'liberou mínimo atingido depois do prazo';
  end if;
  select expire_unconfirmed_groups into v_expired
  from public.expire_unconfirmed_groups()
  where expire_unconfirmed_groups = 'd8c40000-0000-4000-8000-000000000010';
  if v_expired is null
    or (select cancelled_at from public.groups where id = 'd8c40000-0000-4000-8000-000000000009') is not null
  then
    raise exception 'o prazo cancelou o mínimo no horário ou segurou o mínimo atrasado';
  end if;
end $$;

rollback;
