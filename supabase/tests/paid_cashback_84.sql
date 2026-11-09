-- Cashback fixo de 1% do #84, antes das funções do #85.
-- Falha se a migration histórica chamar post_player_cashback.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'ca100000-0000-4000-8000-000000000001',
  'cashback84@example.com',
  '{"display_name":"Cashback 84"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ca200000-0000-4000-8000-000000000001',
  'ca100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Cashback', 'Centro', 'Rua Um', '1', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '90807060000103', '4130000101', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ca300000-0000-4000-8000-000000000001',
  'ca200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ca310000-0000-4000-8000-000000000001',
  'ca300000-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'ca400000-0000-4000-8000-000000000001',
  'curitiba', 'ca200000-0000-4000-8000-000000000001',
  'ca300000-0000-4000-8000-000000000001',
  'ca310000-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00', 4, 2, 10000,
  'ca100000-0000-4000-8000-000000000001'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'ca400000-0000-4000-8000-000000000001',
  'ca100000-0000-4000-8000-000000000001',
  'Cashback 84', true, 'pending', 'none', 'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps
) values (
  'ca500000-0000-4000-8000-000000000001',
  'ca400000-0000-4000-8000-000000000001',
  'ca100000-0000-4000-8000-000000000001',
  'ca200000-0000-4000-8000-000000000001',
  10000, 'PIX', 'pending', 'idem-cashback-84', 'wal', 2500
);

do $$
declare
  v_points integer;
begin
  if to_regprocedure('private.post_player_cashback(uuid,integer)') is not null then
    raise exception 'o #84 ainda depende de post_player_cashback';
  end if;
  perform private.apply_payment_transition(
    'ca500000-0000-4000-8000-000000000001', 'paid', true
  );
  select points into v_points
  from public.scape_point_entries
  where source_charge_id = 'ca500000-0000-4000-8000-000000000001'
    and kind = 'accrual'
    and program = 'cashback';
  if v_points is distinct from 100 then
    raise exception 'cashback fixo de 1%% nao postou 100 pontos: %', v_points;
  end if;
end $$;

rollback;
