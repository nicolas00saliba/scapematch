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
end $$;

rollback;
