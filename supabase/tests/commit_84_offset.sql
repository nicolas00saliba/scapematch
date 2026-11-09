-- Dado financeiro do #84 que precisa sobreviver às migrations do #85.
-- Grava de verdade. O script que chama este arquivo derruba o banco no final.

insert into auth.users (id, email, raw_user_meta_data)
values (
  'cb100000-0000-4000-8000-000000000001',
  'offset84@example.com',
  '{"display_name":"Offset 84"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'cb200000-0000-4000-8000-000000000001',
  'cb100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Offset', 'Centro', 'Rua Dois', '2', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '11444777000161', '4130000102', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'cb300000-0000-4000-8000-000000000001',
  'cb200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'cb310000-0000-4000-8000-000000000001',
  'cb300000-0000-4000-8000-000000000001',
  '2027-09-02 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'cb400000-0000-4000-8000-000000000001',
  'curitiba', 'cb200000-0000-4000-8000-000000000001',
  'cb300000-0000-4000-8000-000000000001',
  'cb310000-0000-4000-8000-000000000001',
  '2027-09-02 18:00:00+00', 4, 2, 10000,
  'cb100000-0000-4000-8000-000000000001'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps
) values (
  'cb500000-0000-4000-8000-000000000001',
  'cb400000-0000-4000-8000-000000000001',
  'cb100000-0000-4000-8000-000000000001',
  'cb200000-0000-4000-8000-000000000001',
  10000, 'PIX', 'paid', 'idem-offset-84', 'wal', 2500
);

insert into public.ledger_entries (
  venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
) values (
  'cb200000-0000-4000-8000-000000000001',
  'cb400000-0000-4000-8000-000000000001',
  'cb100000-0000-4000-8000-000000000001',
  'house', 'credit', 'venue_credit_clawback_offset', 700,
  'cb500000-0000-4000-8000-000000000001'
);
