-- Auditoria de 25/11/2026. O bloco desfaz no final.
-- Taxa cheia, B2B só no desconto de 20%, pontos até o valor a pagar
-- e Bronze nas bordas 0, 1, 4, 5, 7 e 8.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_referrer uuid := 'a2510000-0000-4000-8000-000000000001';
  v_owner uuid := 'a2510000-0000-4000-8000-0000000000bb';
  v_venue uuid := 'a2520000-0000-4000-8000-000000000001';
  v_other uuid := 'a2520000-0000-4000-8000-000000000002';
  v_room uuid := 'a2530000-0000-4000-8000-000000000001';
  v_session uuid := 'a2531000-0000-4000-8000-000000000001';
  v_i integer;
  v_subject uuid;
  v_charge uuid;
  v_group uuid;
  v_rate integer;
  v_buyer uuid;
  v_quote jsonb;
  v_held jsonb;
  v_reserved jsonb;
  v_cents integer;
  v_assumed integer;
  v_amount integer;
  v_status text;
  v_house integer;
  v_cac integer;
begin
  update public.referral_program_settings
  set cashback_distribution = '[{"bps":100,"weight":1}]'::jsonb,
      redeem_min_points = 0,
      redeem_max_bps = 10000,
      backed_full_slot_enabled = false,
      first_booking_discount_bps = 2000,
      organic_first_booking_discount_bps = 1000,
      c2c_from_bps = 100,
      c2c_mid_active = 5,
      c2c_mid_bps = 250,
      c2c_high_active = 8,
      c2c_high_bps = 500,
      b2c_bps = 500,
      c2b_bps = 500,
      b2b_bps = 500,
      point_value_cents = 1
  where id = 1;

  if private.reward_cents(3333, 500) <> 167
    or private.reward_cents(1, 500) <> 0
    or private.reward_cents(50, 100) <> 1
    or private.reward_cents(49, 100) <> 0
  then
    raise exception 'arredondamento da taxa saiu do meio para cima';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (v_referrer, 'audit-indicador@example.com', '{"display_name":"Indicador"}');
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_owner, 'audit-dono@example.com', '{"display_name":"Dono"}');
  if private.referrer_c2c_bps(v_referrer) <> 0 then
    raise exception 'zero indicados ativos nao ficou em 0%%';
  end if;

  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa Auditoria', 'Centro', 'Rua da Auditoria', '25',
    '80025110', -25.43, -49.27, 5000, 'cnpj', '25112500000146',
    '4192511001', 'approved'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    v_room, v_venue, 'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (v_session, v_room, '2027-11-25 18:00:00+00', 'partner_grid');

  for v_i in 1..8 loop
    v_subject := (
      'a254' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    v_charge := (
      'a255' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    v_group := (
      'a256' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      v_subject,
      'audit-indicado-' || v_i::text || '@example.com',
      '{"display_name":"Indicado"}'
    );
    insert into public.referral_attributions (
      subject_kind, subject_user_id, referrer_kind, referrer_user_id,
      code, starts_at, ends_at, status
    ) values (
      'player', v_subject, 'player', v_referrer,
      'audit25', pg_catalog.now() - interval '1 day',
      pg_catalog.now() + interval '300 days', 'active'
    );
    insert into public.groups (
      id, city_id, venue_id, room_id, session_id, starts_at,
      total_spots, minimum_spots, price_cents, created_by
    ) values (
      v_group, 'curitiba', v_venue, v_room, v_session,
      timestamptz '2027-11-25 18:00:00+00' + make_interval(days => v_i),
      4, 2, 10000, v_referrer
    );
    insert into public.payment_charges (
      id, group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, wallet_id, commission_bps, paid_at
    ) values (
      v_charge, v_group, v_subject, v_venue,
      10000, 'PIX', 'paid',
      'idem-audit-ativo-' || v_i::text, 'wal-audit', 2500, pg_catalog.now()
    );
    v_rate := private.referrer_c2c_bps(v_referrer);
    if v_i in (1, 4) and v_rate <> 100 then
      raise exception 'borda bronze falhou no indicado % taxa %', v_i, v_rate;
    end if;
    if v_i in (5, 7) and v_rate <> 250 then
      raise exception 'borda prata falhou no indicado % taxa %', v_i, v_rate;
    end if;
    if v_i = 8 and v_rate <> 500 then
      raise exception 'borda ouro falhou no indicado % taxa %', v_i, v_rate;
    end if;
  end loop;

  update public.profiles set cpf = '10000000108' where id = v_referrer;

  v_buyer := 'a2570000-0000-4000-8000-000000000001';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-comprador@example.com', '{"display_name":"Comprador"}');
  update public.profiles
  set cpf = '10000000280', signup_referred = true
  where id = v_buyer;
  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at, status
  ) values (
    'player', v_buyer, 'player', v_referrer,
    'audit25', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days', 'active'
  );

  v_group := 'a2560009-0000-4000-8000-000000000001';
  v_charge := 'a2550009-0000-4000-8000-000000000001';
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session,
    '2027-12-20 18:00:00+00', 4, 2, 10000, v_referrer
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    billing_type, status, idempotency_key, wallet_id, commission_bps,
    first_booking_discount_cents, first_booking_discount_kind, paid_at,
    payer_document_status
  ) values (
    v_charge, v_group, v_buyer, v_venue, 8000, 10000,
    'PIX', 'paid', 'idem-audit-25', 'wal-audit', 2500,
    2000, 'coded', pg_catalog.now(), 'matched'
  );
  perform private.post_referral_rewards(v_charge);
  select amount_cents into v_cents
  from public.scape_point_entries
  where source_charge_id = v_charge and program = 'c2c' and kind = 'accrual';
  if v_cents is distinct from 500 then
    raise exception 'comissao 25%% pagou % em vez de 500', v_cents;
  end if;
  select amount_cents into v_cents
  from public.scape_point_entries
  where source_charge_id = v_charge and program = 'cashback' and kind = 'accrual';
  if v_cents is distinct from 80 then
    raise exception 'cashback de 1%% em 8000 pagou %', v_cents;
  end if;
  perform private.book_platform_cac(v_charge);
  select assumed_cents, amount_cents, status
    into v_assumed, v_amount, v_status
  from public.platform_cac_transfers
  where payment_charge_id = v_charge;
  if v_assumed is distinct from 80 or v_amount is distinct from 0 or v_status is distinct from 'paid' then
    raise exception 'CAC da comissao 25%% ficou % % %', v_assumed, v_amount, v_status;
  end if;

  v_group := 'a2560010-0000-4000-8000-000000000001';
  v_charge := 'a2550010-0000-4000-8000-000000000001';
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session,
    '2027-12-21 18:00:00+00', 4, 2, 10000, v_referrer
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    billing_type, status, idempotency_key, wallet_id, commission_bps,
    first_booking_discount_cents, first_booking_discount_kind, paid_at,
    payer_document_status
  ) values (
    v_charge, v_group, v_buyer, v_venue, 8000, 10000,
    'PIX', 'paid', 'idem-audit-20', 'wal-audit', 2000,
    2000, 'coded', pg_catalog.now(), 'matched'
  );
  perform private.post_referral_rewards(v_charge);
  select amount_cents into v_cents
  from public.scape_point_entries
  where source_charge_id = v_charge and program = 'c2c' and kind = 'accrual';
  if v_cents is distinct from 500 then
    raise exception 'comissao 20%% zerou o indicador %', v_cents;
  end if;
  perform private.book_platform_cac(v_charge);
  select assumed_cents, amount_cents, status
    into v_assumed, v_amount, v_status
  from public.platform_cac_transfers
  where payment_charge_id = v_charge;
  if v_assumed is distinct from 580 or v_amount is distinct from 0 or v_status is distinct from 'paid' then
    raise exception 'CAC da comissao 20%% ficou % % %', v_assumed, v_amount, v_status;
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'a2510000-0000-4000-8000-0000000000cc',
    'audit-outra@example.com',
    '{"display_name":"Outra"}'
  );
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    v_other, 'a2510000-0000-4000-8000-0000000000cc', 'curitiba', 'Casa Indicadora',
    'Centro', 'Rua da Outra', '26',
    '80025120', -25.43, -49.27, 5000, 'cnpj', '25112500000227',
    '4192511002', 'approved'
  );
  insert into public.referral_attributions (
    subject_kind, subject_venue_id, referrer_kind, referrer_venue_id,
    code, starts_at, ends_at, status
  ) values (
    'venue', v_venue, 'venue', v_other,
    'audit25b', pg_catalog.now() - interval '10 days',
    pg_catalog.now() + interval '300 days', 'active'
  );

  v_buyer := 'a2570000-0000-4000-8000-000000000002';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-organico@example.com', '{"display_name":"Organico"}');
  update public.profiles set cpf = '10000000361' where id = v_buyer;
  v_group := 'a2560011-0000-4000-8000-000000000001';
  v_charge := 'a2550011-0000-4000-8000-000000000001';
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session,
    '2027-12-22 18:00:00+00', 4, 2, 10000, v_owner
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    billing_type, status, idempotency_key, wallet_id, commission_bps,
    first_booking_discount_cents, first_booking_discount_kind, paid_at,
    payer_document_status
  ) values (
    v_charge, v_group, v_buyer, v_venue, 9000, 10000,
    'PIX', 'paid', 'idem-audit-b2b-10', 'wal-audit', 2500,
    1000, 'organic', pg_catalog.now(), 'matched'
  );
  perform private.post_referral_rewards(v_charge);
  select amount_cents into v_cents
  from public.venue_referral_entries
  where source_charge_id = v_charge and program = 'b2b' and kind = 'accrual';
  if v_cents is distinct from 500 then
    raise exception 'B2B sumiu no desconto de 10%% %', v_cents;
  end if;

  v_charge := 'a2550012-0000-4000-8000-000000000001';
  v_group := 'a2560012-0000-4000-8000-000000000001';
  v_buyer := 'a2570000-0000-4000-8000-000000000003';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-codigo@example.com', '{"display_name":"Codigo"}');
  update public.profiles set cpf = '10000000442', signup_referred = true where id = v_buyer;
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session,
    '2027-12-23 18:00:00+00', 4, 2, 10000, v_owner
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    billing_type, status, idempotency_key, wallet_id, commission_bps,
    first_booking_discount_cents, first_booking_discount_kind, paid_at,
    payer_document_status
  ) values (
    v_charge, v_group, v_buyer, v_venue, 8000, 10000,
    'PIX', 'paid', 'idem-audit-b2b-20', 'wal-audit', 2500,
    2000, 'coded', pg_catalog.now(), 'matched'
  );
  perform private.post_referral_rewards(v_charge);
  if exists (
    select 1 from public.venue_referral_entries
    where source_charge_id = v_charge and program = 'b2b' and kind = 'accrual'
  ) then
    raise exception 'B2B pagou no desconto de 20%%';
  end if;

  v_buyer := 'a2570000-0000-4000-8000-000000000004';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-pontos@example.com', '{"display_name":"Pontos"}');
  update public.profiles set cpf = '10000000523' where id = v_buyer;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    v_buyer, 'release', 20000, 20000, 'welcome', 'audit-saldo-20000'
  );
  v_quote := private.quote_redemption(v_buyer, v_venue, 10000, 2500, 20000);
  if (v_quote ->> 'points')::integer <> 9000
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 1000
    or (v_quote ->> 'topup_cents')::integer <> 7500
    or (v_quote ->> 'house_net_cents')::integer <> 7500
  then
    raise exception 'R$ 100 com 10%% e 20000 pontos nao aceitou 9000 %', v_quote;
  end if;

  v_held := private.hold_point_redemption(
    v_buyer, 'idem-audit-pontos', 10000, 2500, 9000
  );
  v_group := 'a2560013-0000-4000-8000-000000000001';
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session,
    '2027-12-24 18:00:00+00', 4, 2, 10000, v_owner
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    v_group, v_buyer, 'Pontos', true, 'pending', 'none', 'none'
  );
  v_reserved := public.reserve_pix_charge(
    v_group, v_buyer, v_venue,
    (v_held ->> 'charged_cents')::integer,
    'idem-audit-pontos', 'wal-audit', 2500, 10000,
    (v_held ->> 'subsidy_cents')::integer,
    (v_held ->> 'points')::integer,
    nullif(v_held ->> 'split_percent', '')::numeric
  );
  if (v_reserved ->> 'amount_cents')::integer <> 0
    or (
      select free_slot_topup_cents from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 7500
    or (
      select first_booking_discount_kind from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) is distinct from 'organic'
  then
    raise exception 'reserva coberta por pontos nao zerou o caixa %', v_reserved;
  end if;
  perform public.settle_points_covered_charge((v_reserved ->> 'id')::uuid);
  select amount_cents, status into v_amount, v_status
  from public.platform_cac_transfers
  where payment_charge_id = (v_reserved ->> 'id')::uuid;
  select coalesce(sum(amount_cents), 0) into v_house
  from public.ledger_entries
  where payment_charge_id = (v_reserved ->> 'id')::uuid
    and kind = 'house_net';
  if v_amount is distinct from 7500
    or v_status is distinct from 'pending'
    or v_house + v_amount is distinct from 7500
  then
    raise exception 'a casa nao ficou com 7500 no caixa mais o CAC % % %',
      v_house, v_amount, v_status;
  end if;
  if exists (
    select 1 from public.free_slot_topups
    where payment_charge_id = (v_reserved ->> 'id')::uuid
  ) then
    raise exception 'flag desligada gravou credito de vaga gratis';
  end if;

  v_buyer := 'a2570000-0000-4000-8000-000000000005';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-codigo-pontos@example.com', '{"display_name":"Codigo Pontos"}');
  update public.profiles
  set cpf = '10000000604', signup_referred = true
  where id = v_buyer;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    v_buyer, 'release', 20000, 20000, 'welcome', 'audit-saldo-codigo'
  );
  v_quote := private.quote_redemption(v_buyer, v_venue, 10000, 2500, 20000);
  if (v_quote ->> 'points')::integer <> 8000
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 2000
    or (v_quote ->> 'charged_cents')::integer <> 0
  then
    raise exception 'codigo de 20%% nao deixou 8000 pontos %', v_quote;
  end if;

  v_buyer := 'a2570000-0000-4000-8000-000000000006';
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_buyer, 'audit-segunda@example.com', '{"display_name":"Segunda"}');
  update public.profiles set cpf = '10000000795' where id = v_buyer;
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'a2560014-0000-4000-8000-000000000001',
    'curitiba', v_venue, v_room, v_session,
    '2027-12-25 18:00:00+00', 4, 2, 10000, v_owner
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'a2550014-0000-4000-8000-000000000001',
    'a2560014-0000-4000-8000-000000000001',
    v_buyer, v_venue, 10000, 'PIX', 'paid',
    'idem-audit-ja-pagou', 'wal-audit', 2500, pg_catalog.now()
  );
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    v_buyer, 'release', 20000, 20000, 'welcome', 'audit-saldo-segunda'
  );
  v_quote := private.quote_redemption(v_buyer, v_venue, 10000, 2500, 20000);
  if (v_quote ->> 'points')::integer <> 10000
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 0
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'topup_cents')::integer <> 7500
  then
    raise exception 'sem desconto os pontos nao cobriram a reserva %', v_quote;
  end if;

  if private.discount_blocks_b2b(v_buyer, 10000, 1000, null)
    or not private.discount_blocks_b2b(v_buyer, 10000, 2000, null)
    or private.discount_blocks_b2b(v_buyer, 10000, 1000, 'organic')
    or not private.discount_blocks_b2b(v_buyer, 10000, 2000, 'coded')
  then
    raise exception 'a classificacao do B2B misturou 10%% e 20%%';
  end if;
end;
$$;

rollback;
