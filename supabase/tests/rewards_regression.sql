-- Regressão isolada dos dois pacotes de recompensa.
-- Não chama o Asaas e não grava nada: o bloco desfaz no final.
-- Rode de novo quando quiser revisar. Precisa do schema já migrado.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_paid timestamptz := timestamptz '2026-11-09 15:00:00+00';
  v_weekday integer;
  v_plain integer;
  v_doubled integer;
  v_off integer;
  v_quote jsonb;
begin
  update public.referral_program_settings
  set cashback_distribution = '[{"bps":100,"weight":1}]'::jsonb,
      cashback_min_bps = 50,
      cashback_max_bps = 500,
      cashback_ev_cap_bps = 100,
      empty_slot_house_share_bps = 5000,
      welcome_points = 100,
      redeem_min_points = 1000,
      redeem_max_bps = 3000,
      first_booking_discount_bps = 0
  where id = 1;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'aa100000-0000-4000-8000-000000000001',
    'regressao-casa@example.com',
    '{"display_name":"Regressao Casa"}'
  );
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa100000-0000-4000-8000-000000000001',
    'curitiba',
    'Casa Regressao',
    'Centro',
    'Rua da Revisao',
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
    'aa300000-0000-4000-8000-000000000001',
    'aa200000-0000-4000-8000-000000000001',
    'Sala Regressao',
    '',
    4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (
    'aa310000-0000-4000-8000-000000000001',
    'aa300000-0000-4000-8000-000000000001',
    v_paid,
    'partner_grid'
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    (
      'aa400000-0000-4000-8000-000000000001',
      'curitiba', 'aa200000-0000-4000-8000-000000000001',
      'aa300000-0000-4000-8000-000000000001',
      'aa310000-0000-4000-8000-000000000001',
      v_paid, 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001'
    ),
    (
      'aa400000-0000-4000-8000-000000000002',
      'curitiba', 'aa200000-0000-4000-8000-000000000001',
      'aa300000-0000-4000-8000-000000000001',
      'aa310000-0000-4000-8000-000000000001',
      v_paid + interval '1 day', 4, 2, 10000,
      'aa100000-0000-4000-8000-000000000001'
    ),
    (
      'aa400000-0000-4000-8000-000000000003',
      'curitiba', 'aa200000-0000-4000-8000-000000000001',
      'aa300000-0000-4000-8000-000000000001',
      'aa310000-0000-4000-8000-000000000001',
      v_paid + interval '2 day', 4, 2, 10000,
      'aa100000-0000-4000-8000-000000000001'
    );

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'aa100000-0000-4000-8000-000000000002',
    'regressao-jogador@example.com',
    '{"display_name":"Regressao Jogador"}'
  );
  update public.profiles
  set cpf = '47890507348'
  where id = 'aa100000-0000-4000-8000-000000000002';

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'aa500000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000001',
    'aa100000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid',
    'idem-regressao-sem-faixa', 'wal_house', 2500, v_paid
  );

  v_plain := private.post_player_cashback(
    'aa500000-0000-4000-8000-000000000001', 2500
  );
  if v_plain <> 100
    or private.post_player_cashback(
      'aa500000-0000-4000-8000-000000000001', 2500
    ) <> 100
    or exists (
      select 1 from public.venue_cashback_debits
      where source_charge_id = 'aa500000-0000-4000-8000-000000000001'
    )
    or exists (
      select 1 from public.cashback_draws
      where payment_charge_id = 'aa500000-0000-4000-8000-000000000001'
        and doubled
    )
  then
    raise exception 'casa sem opt-in foi cobrada no horario vazio %', v_plain;
  end if;

  v_weekday := extract(isodow from v_paid at time zone 'America/Sao_Paulo')::integer;
  insert into public.venue_empty_slots (
    venue_id, weekday, starts_minute, ends_minute, active
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    v_weekday, 0, 1440, false
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'aa500000-0000-4000-8000-000000000003',
    'aa400000-0000-4000-8000-000000000003',
    'aa100000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid',
    'idem-regressao-faixa-inativa', 'wal_house', 2500, v_paid
  );
  v_off := private.post_player_cashback(
    'aa500000-0000-4000-8000-000000000003', 2500
  );
  if v_off <> 100 or exists (
    select 1 from public.venue_cashback_debits
    where source_charge_id = 'aa500000-0000-4000-8000-000000000003'
  ) then
    raise exception 'faixa inativa ainda tirou repasse da casa %', v_off;
  end if;

  update public.venue_empty_slots
  set active = true
  where venue_id = 'aa200000-0000-4000-8000-000000000001';
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'aa500000-0000-4000-8000-000000000002',
    'aa400000-0000-4000-8000-000000000002',
    'aa100000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid',
    'idem-regressao-com-faixa', 'wal_house', 2500,
    v_paid + interval '7 days'
  );
  v_doubled := private.post_player_cashback(
    'aa500000-0000-4000-8000-000000000002', 2500
  );
  if v_doubled <> 150
    or (
      select points from public.scape_point_entries
      where source_charge_id = 'aa500000-0000-4000-8000-000000000002'
        and program = 'cashback' and kind = 'accrual'
    ) <> 200
    or (
      select amount_cents from public.venue_cashback_debits
      where source_charge_id = 'aa500000-0000-4000-8000-000000000002'
    ) <> 50
    or (
      select applied_cents from public.venue_cashback_debits
      where source_charge_id = 'aa500000-0000-4000-8000-000000000002'
    ) <> 0
  then
    raise exception 'opt-in nao dobrou ou ja consumiu o repasse %', v_doubled;
  end if;

  perform private.grant_welcome_points('aa100000-0000-4000-8000-000000000002');
  perform private.grant_welcome_points('aa100000-0000-4000-8000-000000000002');
  if (
    select count(*) from public.scape_point_entries
    where user_id = 'aa100000-0000-4000-8000-000000000002'
      and program = 'welcome' and kind = 'release'
  ) <> 1 then
    raise exception 'boas-vindas da regressao nao ficou idempotente';
  end if;

  v_quote := private.subsidy_quote(
    'aa100000-0000-4000-8000-000000000002', 10000, 2500, 5000, false
  );
  if (v_quote ->> 'points')::integer <> 0 then
    raise exception 'regressao deixou resgatar abaixo de 1000 %', v_quote;
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'aa100000-0000-4000-8000-000000000003',
    'regressao-admin@example.com',
    '{"display_name":"Regressao Admin"}'
  );
  insert into public.admins (user_id)
  values ('aa100000-0000-4000-8000-000000000003');
  perform set_config(
    'request.jwt.claim.sub',
    'aa100000-0000-4000-8000-000000000003',
    true
  );
  execute 'set local role authenticated';
  begin
    perform public.upsert_venue_empty_slot(
      'aa200000-0000-4000-8000-000000000001', 1, 0, 60
    );
    raise exception 'admin marcou horario vazio sem a casa';
  exception
    when insufficient_privilege then
      null;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);

  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa500000-0000-4000-8000-000000000001',
    300
  );
  perform private.reverse_referral_rewards('aa500000-0000-4000-8000-000000000001');
  perform private.apply_empty_slot_debit(
    'aa500000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000,
    true
  );
  if exists (
    select 1 from public.venue_cashback_debits
    where source_charge_id = 'aa500000-0000-4000-8000-000000000001'
      and amount_cents = 300
      and (voided_at is null or applied_cents <> 0)
  ) then
    raise exception 'debito de horario vazio sobreviveu ao estorno';
  end if;

  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents, applied_cents, applied_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa500000-0000-4000-8000-000000000003',
    300, 300, 'aa500000-0000-4000-8000-000000000002'
  );
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000002',
    'aa100000-0000-4000-8000-000000000002',
    'house', 'debit', 'empty_slot_offset', 300,
    'aa500000-0000-4000-8000-000000000002'
  );
  perform private.ledger_reverse_charge('aa500000-0000-4000-8000-000000000002');
  if (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = 'aa500000-0000-4000-8000-000000000003'
  ) <> 0 or not exists (
    select 1 from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000002'
      and kind = 'empty_slot_offset_undo' and direction = 'credit' and amount_cents = 300
  ) then
    raise exception 'estorno da cobranca que absorveu o horario vazio nao devolveu os 300';
  end if;
  perform private.reverse_referral_rewards('aa500000-0000-4000-8000-000000000003');
  if exists (
    select 1 from public.venue_cashback_refunds f
    join public.venue_cashback_debits d on d.id = f.debit_id
    where d.source_charge_id = 'aa500000-0000-4000-8000-000000000003'
      and f.voided_at is null
  ) then
    raise exception 'o gerador estornado pagou de novo o horario vazio';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    ('aa400000-0000-4000-8000-000000000004', 'curitiba', 'aa200000-0000-4000-8000-000000000001', 'aa300000-0000-4000-8000-000000000001', 'aa310000-0000-4000-8000-000000000001', v_paid + interval '4 day', 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001'),
    ('aa400000-0000-4000-8000-000000000005', 'curitiba', 'aa200000-0000-4000-8000-000000000001', 'aa300000-0000-4000-8000-000000000001', 'aa310000-0000-4000-8000-000000000001', v_paid + interval '5 day', 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001'),
    ('aa400000-0000-4000-8000-000000000006', 'curitiba', 'aa200000-0000-4000-8000-000000000001', 'aa300000-0000-4000-8000-000000000001', 'aa310000-0000-4000-8000-000000000001', v_paid + interval '6 day', 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001'),
    ('aa400000-0000-4000-8000-000000000007', 'curitiba', 'aa200000-0000-4000-8000-000000000001', 'aa300000-0000-4000-8000-000000000001', 'aa310000-0000-4000-8000-000000000001', v_paid + interval '7 day', 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001'),
    ('aa400000-0000-4000-8000-000000000008', 'curitiba', 'aa200000-0000-4000-8000-000000000001', 'aa300000-0000-4000-8000-000000000001', 'aa310000-0000-4000-8000-000000000001', v_paid + interval '8 day', 4, 2, 10000, 'aa100000-0000-4000-8000-000000000001');
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values
    ('aa500000-0000-4000-8000-000000000004', 'aa400000-0000-4000-8000-000000000004', 'aa100000-0000-4000-8000-000000000002', 'aa200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-reg-d1', 'wal', 2500),
    ('aa500000-0000-4000-8000-000000000005', 'aa400000-0000-4000-8000-000000000005', 'aa100000-0000-4000-8000-000000000002', 'aa200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-reg-d2', 'wal', 2500),
    ('aa500000-0000-4000-8000-000000000006', 'aa400000-0000-4000-8000-000000000006', 'aa100000-0000-4000-8000-000000000002', 'aa200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-reg-abs', 'wal', 2500),
    ('aa500000-0000-4000-8000-000000000007', 'aa400000-0000-4000-8000-000000000007', 'aa100000-0000-4000-8000-000000000002', 'aa200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-reg-dev', 'wal', 2500),
    ('aa500000-0000-4000-8000-000000000008', 'aa400000-0000-4000-8000-000000000008', 'aa100000-0000-4000-8000-000000000002', 'aa200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-reg-src', 'wal', 2500);
  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents, applied_cents, applied_charge_id
  ) values
    ('aa200000-0000-4000-8000-000000000001', 'aa500000-0000-4000-8000-000000000004', 200, 200, 'aa500000-0000-4000-8000-000000000006'),
    ('aa200000-0000-4000-8000-000000000001', 'aa500000-0000-4000-8000-000000000005', 150, 150, 'aa500000-0000-4000-8000-000000000006');
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000006',
    'aa100000-0000-4000-8000-000000000002',
    'house', 'debit', 'empty_slot_offset', 350,
    'aa500000-0000-4000-8000-000000000006'
  );
  perform private.ledger_reverse_charge('aa500000-0000-4000-8000-000000000006');
  perform private.ledger_reverse_charge('aa500000-0000-4000-8000-000000000006');
  if (
    select count(*) from public.venue_cashback_debits
    where applied_charge_id = 'aa500000-0000-4000-8000-000000000006'
  ) <> 0 or (
    select coalesce(sum(amount_cents), 0) from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000006'
      and kind = 'empty_slot_offset_undo'
  ) is distinct from 350 or exists (
    select 1 from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000006'
      and kind = 'empty_slot_refund_reversal'
  ) then
    raise exception 'dois debitos na mesma cobranca nao estornaram juntos ou o replay mudou o livro';
  end if;

  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents, applied_cents, applied_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa500000-0000-4000-8000-000000000008',
    400, 400, 'aa500000-0000-4000-8000-000000000006'
  );
  insert into public.venue_cashback_refunds (
    venue_id, debit_id, amount_cents, applied_cents, applied_charge_id
  )
  select
    'aa200000-0000-4000-8000-000000000001', d.id, 400, 400,
    'aa500000-0000-4000-8000-000000000007'
  from public.venue_cashback_debits d
  where d.source_charge_id = 'aa500000-0000-4000-8000-000000000008';
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000007',
    'aa100000-0000-4000-8000-000000000002',
    'house', 'credit', 'house_net', 7500,
    'aa500000-0000-4000-8000-000000000007'
  ), (
    'aa200000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000007',
    'aa100000-0000-4000-8000-000000000002',
    'house', 'credit', 'empty_slot_offset_refund', 400,
    'aa500000-0000-4000-8000-000000000007'
  );
  perform private.ledger_reverse_charge('aa500000-0000-4000-8000-000000000007');
  perform private.ledger_reverse_charge('aa500000-0000-4000-8000-000000000007');
  if (
    select f.applied_cents from public.venue_cashback_refunds f
    join public.venue_cashback_debits d on d.id = f.debit_id
    where d.source_charge_id = 'aa500000-0000-4000-8000-000000000008'
  ) <> 0 or (
    select coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)
    from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000007'
      and account = 'house'
  ) <> 0 then
    raise exception 'estorno da devolucao nao reabriu a obrigacao ou o livro da casa nao zerou';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'aa400000-0000-4000-8000-000000000009',
    'curitiba', 'aa200000-0000-4000-8000-000000000001',
    'aa300000-0000-4000-8000-000000000001',
    'aa310000-0000-4000-8000-000000000001',
    v_paid + interval '9 day', 4, 2, 10000,
    'aa100000-0000-4000-8000-000000000001'
  ), (
    'aa400000-0000-4000-8000-000000000010',
    'curitiba', 'aa200000-0000-4000-8000-000000000001',
    'aa300000-0000-4000-8000-000000000001',
    'aa310000-0000-4000-8000-000000000001',
    v_paid + interval '10 day', 4, 2, 10000,
    'aa100000-0000-4000-8000-000000000001'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'aa400000-0000-4000-8000-000000000009',
    'aa100000-0000-4000-8000-000000000002',
    'Regressao Jogador', true, 'pending', 'none', 'none'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'aa500000-0000-4000-8000-000000000009',
    'aa400000-0000-4000-8000-000000000009',
    'aa100000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'pending', 'idem-reg-replay', 'wal', 2500
  ), (
    'aa500000-0000-4000-8000-000000000010',
    'aa400000-0000-4000-8000-000000000010',
    'aa100000-0000-4000-8000-000000000002',
    'aa200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid', 'idem-reg-replay-src', 'wal', 2500
  );
  perform private.apply_payment_transition(
    'aa500000-0000-4000-8000-000000000009', 'paid', true
  );
  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents, applied_cents, applied_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa500000-0000-4000-8000-000000000010',
    400, 400, 'aa500000-0000-4000-8000-000000000009'
  );
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'aa200000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000009',
    'aa100000-0000-4000-8000-000000000002',
    'house', 'debit', 'empty_slot_offset', 400,
    'aa500000-0000-4000-8000-000000000009'
  );
  perform private.apply_payment_transition(
    'aa500000-0000-4000-8000-000000000009', 'refunded', true
  );
  perform private.apply_payment_transition(
    'aa500000-0000-4000-8000-000000000009', 'refunded', true
  );
  if (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = 'aa500000-0000-4000-8000-000000000010'
  ) <> 0 or (
    select amount_cents from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000009'
      and kind = 'empty_slot_offset_undo'
  ) is distinct from 400 or exists (
    select 1 from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000009'
      and kind = 'empty_slot_refund_reversal'
  ) or (
    select coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)
    from public.ledger_entries
    where payment_charge_id = 'aa500000-0000-4000-8000-000000000009'
      and account = 'house'
  ) <> 0 then
    raise exception 'replay do estorno reabriu o debito ou tirou o undo do livro';
  end if;
end $$;

rollback;
