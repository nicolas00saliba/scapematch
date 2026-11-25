-- Estorno capturado devolve o dinheiro pago menos a taxa daquela cobrança.
-- Autorização aberta devolve o valor retido inteiro.
-- Pontos e a parte da casa ficam como estavam.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('b7100001-0000-4000-8000-000000000001', 'taxa-casa@example.com', '{"display_name":"Casa Taxa"}'),
  ('b7100001-0000-4000-8000-000000000002', 'taxa-pix@example.com', '{"display_name":"Pix Taxa"}'),
  ('b7100001-0000-4000-8000-000000000003', 'taxa-card@example.com', '{"display_name":"Card Taxa"}'),
  ('b7100001-0000-4000-8000-000000000004', 'taxa-real@example.com', '{"display_name":"Taxa Real"}'),
  ('b7100001-0000-4000-8000-000000000005', 'taxa-misto@example.com', '{"display_name":"Misto Taxa"}'),
  ('b7100001-0000-4000-8000-000000000006', 'taxa-miudo@example.com', '{"display_name":"Miudo Taxa"}'),
  ('b7100001-0000-4000-8000-000000000007', 'taxa-void@example.com', '{"display_name":"Void Taxa"}'),
  ('b7100001-0000-4000-8000-000000000008', 'taxa-casa-jogador@example.com', '{"display_name":"Jogador Casa"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'b7200001-0000-4000-8000-000000000001',
  'b7100001-0000-4000-8000-000000000001',
  'curitiba',
  'Casa da Taxa',
  'Centro',
  'Rua da Taxa',
  '16',
  '80010016',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '77666555000133',
  '41988880003',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'b7300001-0000-4000-8000-000000000001',
  'b7200001-0000-4000-8000-000000000001',
  'Sala da Taxa',
  '',
  8,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  (
    'b7400001-0000-4000-8000-000000000001',
    'b7300001-0000-4000-8000-000000000001',
    '2027-09-02 18:00:00+00',
    'partner_grid'
  ),
  (
    'b7400001-0000-4000-8000-000000000002',
    'b7300001-0000-4000-8000-000000000001',
    '2027-09-03 18:00:00+00',
    'partner_grid'
  ),
  (
    'b7400001-0000-4000-8000-000000000003',
    'b7300001-0000-4000-8000-000000000001',
    '2027-09-04 18:00:00+00',
    'partner_grid'
  );

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, closes_at
) values
  (
    'b7500001-0000-4000-8000-000000000001',
    'curitiba',
    'b7200001-0000-4000-8000-000000000001',
    'b7300001-0000-4000-8000-000000000001',
    'b7400001-0000-4000-8000-000000000001',
    '2027-09-02 18:00:00+00',
    8, 2, 10000,
    'b7100001-0000-4000-8000-000000000001',
    '2027-09-01 18:00:00+00'
  ),
  (
    'b7500001-0000-4000-8000-000000000002',
    'curitiba',
    'b7200001-0000-4000-8000-000000000001',
    'b7300001-0000-4000-8000-000000000001',
    'b7400001-0000-4000-8000-000000000002',
    '2027-09-03 18:00:00+00',
    8, 2, 10000,
    'b7100001-0000-4000-8000-000000000001',
    '2027-09-02 18:00:00+00'
  ),
  (
    'b7500001-0000-4000-8000-000000000003',
    'curitiba',
    'b7200001-0000-4000-8000-000000000001',
    'b7300001-0000-4000-8000-000000000001',
    'b7400001-0000-4000-8000-000000000003',
    '2027-09-04 18:00:00+00',
    8, 2, 10000,
    'b7100001-0000-4000-8000-000000000001',
    '2027-09-03 18:00:00+00'
  );

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  (
    'b7600001-0000-4000-8000-000000000001',
    'b7500001-0000-4000-8000-000000000001',
    'b7100001-0000-4000-8000-000000000001',
    'Casa Taxa', true, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000002',
    'b7500001-0000-4000-8000-000000000001',
    'b7100001-0000-4000-8000-000000000002',
    'Pix Taxa', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000011',
    'b7500001-0000-4000-8000-000000000002',
    'b7100001-0000-4000-8000-000000000001',
    'Casa Taxa', true, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000008',
    'b7500001-0000-4000-8000-000000000002',
    'b7100001-0000-4000-8000-000000000008',
    'Jogador Casa', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000031',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000001',
    'Casa Taxa', true, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000003',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000003',
    'Card Taxa', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000004',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000004',
    'Taxa Real', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000005',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000005',
    'Misto Taxa', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000006',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000006',
    'Miudo Taxa', false, 'paid'
  ),
  (
    'b7600001-0000-4000-8000-000000000007',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000007',
    'Void Taxa', false, 'reserved'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, charged_amount_cents,
  buyer_interest_cents, gross_amount_cents, subsidy_cents, points_redeemed,
  billing_type, status, provider, provider_ref, provider_fee_cents,
  house_fixed_cents, idempotency_key, wallet_id, commission_bps, paid_at,
  attempt_id
) values
  (
    'b7700001-0000-4000-8000-000000000002',
    'b7500001-0000-4000-8000-000000000001',
    'b7100001-0000-4000-8000-000000000002',
    'b7200001-0000-4000-8000-000000000001',
    10000, 10000, 0, null, 0, 0,
    'PIX', 'paid', 'pagbank', 'CHAR_TAXA_PIX', null,
    8000, 'idem-taxa-pix', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000002'
  ),
  (
    'b7700001-0000-4000-8000-000000000008',
    'b7500001-0000-4000-8000-000000000002',
    'b7100001-0000-4000-8000-000000000008',
    'b7200001-0000-4000-8000-000000000001',
    10000, 10000, 0, null, 0, 0,
    'PIX', 'paid', 'pagbank', 'CHAR_TAXA_CASA', null,
    8000, 'idem-taxa-casa', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000008'
  ),
  (
    'b7700001-0000-4000-8000-000000000003',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000003',
    'b7200001-0000-4000-8000-000000000001',
    10001, 10001, 0, null, 0, 0,
    'CREDIT_CARD', 'paid', 'pagbank', 'CHAR_TAXA_CARD', null,
    8000, 'idem-taxa-card', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000003'
  ),
  (
    'b7700001-0000-4000-8000-000000000004',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000004',
    'b7200001-0000-4000-8000-000000000001',
    10000, 10000, 0, null, 0, 0,
    'PIX', 'paid', 'pagbank', 'CHAR_TAXA_REAL', 321,
    8000, 'idem-taxa-real', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000004'
  ),
  (
    'b7700001-0000-4000-8000-000000000005',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000005',
    'b7200001-0000-4000-8000-000000000001',
    6000, 6000, 0, 10000, 4000, 4000,
    'PIX', 'paid', 'pagbank', 'CHAR_TAXA_MISTO', null,
    8000, 'idem-taxa-misto', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000005'
  ),
  (
    'b7700001-0000-4000-8000-000000000006',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000006',
    'b7200001-0000-4000-8000-000000000001',
    100, 100, 0, null, 0, 0,
    'PIX', 'paid', 'pagbank', 'CHAR_TAXA_MIUDO', 150,
    8000, 'idem-taxa-miudo', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000006'
  ),
  (
    'b7700001-0000-4000-8000-000000000007',
    'b7500001-0000-4000-8000-000000000003',
    'b7100001-0000-4000-8000-000000000007',
    'b7200001-0000-4000-8000-000000000001',
    10000, 10640, 640, null, 0, 0,
    'CREDIT_CARD', 'authorized', 'pagbank', 'CHAR_TAXA_VOID', 400,
    8000, 'idem-taxa-void', 'wal_taxa', 2500, now(),
    'b7710001-0000-4000-8000-000000000007'
  );

do $$
declare
  v_direct uuid := 'b7500001-0000-4000-8000-000000000003';
  v_points_before integer;
  v_preview integer;
  v_amount integer;
  v_action text;
  v_house integer;
  v_points integer;
  v_entries integer;
  v_pix integer;
  v_fixed integer;
  v_bps integer;
  v_percent integer;
  v_claim jsonb;
begin
  select pix_receipt_fee_cents, card_receipt_fee_cents, card_receipt_fee_bps
    into v_pix, v_fixed, v_bps
  from public.platform_settings
  where id = 1;
  v_percent := ((10001::bigint * v_bps + 9999) / 10000)::integer;
  if v_pix <> 199 or v_fixed <> 49 or v_bps <> 299
    or v_percent <> 300
    or least(10001, v_fixed + v_percent) <> 349
  then
    raise exception
      'taxa padrão inesperada pix % fixo % bps % percent %',
      v_pix, v_fixed, v_bps, v_percent;
  end if;

  select count(*) into v_points_before
  from public.scape_point_entries
  where user_id = 'b7100001-0000-4000-8000-000000000005';

  perform private.enqueue_member_refund(
    v_direct,
    'b7100001-0000-4000-8000-000000000003',
    'b7600001-0000-4000-8000-000000000003'
  );
  perform private.enqueue_member_refund(
    v_direct,
    'b7100001-0000-4000-8000-000000000004',
    'b7600001-0000-4000-8000-000000000004'
  );
  perform private.enqueue_member_refund(
    v_direct,
    'b7100001-0000-4000-8000-000000000005',
    'b7600001-0000-4000-8000-000000000005'
  );
  perform private.enqueue_member_refund(
    v_direct,
    'b7100001-0000-4000-8000-000000000006',
    'b7600001-0000-4000-8000-000000000006'
  );
  perform private.enqueue_member_refund(
    v_direct,
    'b7100001-0000-4000-8000-000000000007',
    'b7600001-0000-4000-8000-000000000007'
  );

  perform set_config(
    'request.jwt.claim.sub',
    'b7100001-0000-4000-8000-000000000002',
    true
  );
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  v_preview := public.preview_member_refund(
    'b7500001-0000-4000-8000-000000000001'
  );
  if v_preview is distinct from 9801 then
    raise exception 'prévia do pix %', v_preview;
  end if;
  perform public.leave_group('b7500001-0000-4000-8000-000000000001');

  perform set_config(
    'request.jwt.claim.sub',
    'b7100001-0000-4000-8000-000000000001',
    true
  );
  perform public.remove_room_session('b7400001-0000-4000-8000-000000000002');

  select amount_cents, action into v_amount, v_action
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000002';
  if v_amount is distinct from 9801 or v_action is distinct from 'refund' then
    raise exception 'pix saída % %', v_action, v_amount;
  end if;

  select amount_cents into v_amount
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000003';
  if v_amount is distinct from 9652 then
    raise exception 'cartão %', v_amount;
  end if;

  select amount_cents into v_amount
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000004';
  if v_amount is distinct from 9679 then
    raise exception 'taxa informada %', v_amount;
  end if;

  select q.amount_cents, c.house_fixed_cents, c.points_redeemed
    into v_amount, v_house, v_points
  from public.member_refund_queue q
  join public.payment_charges c on c.id = q.charge_id
  where q.charge_id = 'b7700001-0000-4000-8000-000000000005';
  select count(*) into v_entries
  from public.scape_point_entries
  where user_id = 'b7100001-0000-4000-8000-000000000005';
  if v_amount is distinct from 5801
    or v_house is distinct from 8000
    or v_points is distinct from 4000
    or v_entries is distinct from v_points_before
  then
    raise exception
      'misto valor % casa % pontos % lançamentos %/%',
      v_amount, v_house, v_points, v_entries, v_points_before;
  end if;

  select amount_cents into v_amount
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000006';
  if v_amount is distinct from 0 then
    raise exception 'taxa maior que o pago %', v_amount;
  end if;

  select amount_cents, action into v_amount, v_action
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000007';
  if v_amount is distinct from 10640 or v_action is distinct from 'void' then
    raise exception 'autorização % %', v_action, v_amount;
  end if;

  select house_fixed_cents into v_house
  from public.payment_charges
  where id = 'b7700001-0000-4000-8000-000000000002';
  if v_house is distinct from 8000 then
    raise exception 'casa do pix %', v_house;
  end if;

  select amount_cents into v_amount
  from public.member_refund_queue
  where charge_id = 'b7700001-0000-4000-8000-000000000008';
  if v_amount is distinct from 9801 then
    raise exception 'casa cancelou %', v_amount;
  end if;

  select body into v_action
  from public.app_notices
  where user_id = 'b7100001-0000-4000-8000-000000000008'
  order by created_at desc
  limit 1;
  if v_action is null or v_action ilike '%integral%' then
    raise exception 'aviso da casa ainda promete integral: %', v_action;
  end if;

  v_claim := private.claim_member_refunds(20, null, null);
  if not exists (
    select 1
    from jsonb_array_elements(v_claim) item
    where item ->> 'charge_id' = 'b7700001-0000-4000-8000-000000000003'
      and (item ->> 'amount_cents')::integer = 9652
  ) then
    raise exception 'claim sem o valor do cartão';
  end if;
end $$;
