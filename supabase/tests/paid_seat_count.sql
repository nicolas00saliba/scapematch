-- Vaga paga é a mesma da lista. Quem não pagou não ocupa.
-- Dois pagamentos da última vaga: um fica, o outro vai para a fila.
-- A trava entre sessões está em paid_seat_race.sh.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('a5100001-0000-4000-8000-000000000001', 'vaga-paga@example.com', '{"display_name":"Vaga Paga"}'),
  ('a5100001-0000-4000-8000-000000000002', 'vaga-dois@example.com', '{"display_name":"Vaga Dois"}'),
  ('a5100001-0000-4000-8000-000000000003', 'vaga-tres@example.com', '{"display_name":"Vaga Tres"}'),
  ('a5100001-0000-4000-8000-000000000004', 'vaga-held@example.com', '{"display_name":"Vaga Held"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'a5200001-0000-4000-8000-000000000001',
  'a5100001-0000-4000-8000-000000000001',
  'curitiba',
  'Casa Vaga Paga',
  'Centro',
  'Rua da Vaga',
  '8',
  '80010010',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '99888777000155',
  '41988880001',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'a5300001-0000-4000-8000-000000000001',
  'a5200001-0000-4000-8000-000000000001',
  'Sala da Vaga',
  '',
  6,
  2,
  60,
  'medium',
  9000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'a5400001-0000-4000-8000-000000000001',
  'a5300001-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, closes_at
) values (
  'a5500001-0000-4000-8000-000000000001',
  'curitiba',
  'a5200001-0000-4000-8000-000000000001',
  'a5300001-0000-4000-8000-000000000001',
  'a5400001-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00',
  2,
  2,
  9000,
  'a5100001-0000-4000-8000-000000000001',
  '2027-08-31 18:00:00+00'
);

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  (
    'a5600001-0000-4000-8000-000000000001',
    'a5500001-0000-4000-8000-000000000001',
    'a5100001-0000-4000-8000-000000000001',
    'Vaga Paga',
    true,
    'paid'
  ),
  (
    'a5600001-0000-4000-8000-000000000002',
    'a5500001-0000-4000-8000-000000000001',
    'a5100001-0000-4000-8000-000000000002',
    'Vaga Dois',
    false,
    'pending'
  ),
  (
    'a5600001-0000-4000-8000-000000000003',
    'a5500001-0000-4000-8000-000000000001',
    'a5100001-0000-4000-8000-000000000003',
    'Vaga Tres',
    false,
    'pending'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, charged_amount_cents,
  buyer_interest_cents, billing_type, status, provider, provider_ref,
  idempotency_key, wallet_id, commission_bps, paid_at, attempt_id
) values
  (
    'a5700001-0000-4000-8000-000000000002',
    'a5500001-0000-4000-8000-000000000001',
    'a5100001-0000-4000-8000-000000000002',
    'a5200001-0000-4000-8000-000000000001',
    9000, 9000, 0, 'PIX', 'paid', 'pagbank', 'CHAR_VAGA_2',
    'idem-vaga-2', 'wal_vaga', 2500, now(),
    'a5710001-0000-4000-8000-000000000002'
  ),
  (
    'a5700001-0000-4000-8000-000000000003',
    'a5500001-0000-4000-8000-000000000001',
    'a5100001-0000-4000-8000-000000000003',
    'a5200001-0000-4000-8000-000000000001',
    9000, 9540, 540, 'CREDIT_CARD', 'authorized', 'pagbank', 'CHAR_VAGA_3',
    'idem-vaga-3', 'wal_vaga', 2500, now(),
    'a5710001-0000-4000-8000-000000000003'
  );

do $$
declare
  v_filled integer;
  v_left integer;
begin
  select private.group_filled_spots('a5500001-0000-4000-8000-000000000001')
    into v_filled;
  select spots_left
    into v_left
  from public.venue_open_slots('a5200001-0000-4000-8000-000000000001')
  where session_id = 'a5400001-0000-4000-8000-000000000001';
  if v_filled <> 1 or v_left <> 1 or (
    select filled_spots from public.groups_with_counts
    where id = 'a5500001-0000-4000-8000-000000000001'
  ) <> 1 then
    raise exception 'pendente ocupou vaga: filled % lista %', v_filled, v_left;
  end if;
end $$;

select private.sync_charge_member(c.*)
from public.payment_charges c
where c.id = 'a5700001-0000-4000-8000-000000000002';

select private.sync_charge_member(c.*)
from public.payment_charges c
where c.id = 'a5700001-0000-4000-8000-000000000003';

-- Repetir o ganhador não tira a vaga dele.
select private.sync_charge_member(c.*)
from public.payment_charges c
where c.id = 'a5700001-0000-4000-8000-000000000002';

do $$
declare
  v_winner text;
  v_loser_attendance text;
  v_loser_refund text;
  v_loser_reason text;
  v_queue integer;
  v_filled integer;
  v_listed integer;
begin
  select attendance into v_winner
  from public.group_members
  where id = 'a5600001-0000-4000-8000-000000000002';
  select attendance, refund_status, refund_reason
    into v_loser_attendance, v_loser_refund, v_loser_reason
  from public.group_members
  where id = 'a5600001-0000-4000-8000-000000000003';
  select count(*) into v_queue
  from public.member_refund_queue
  where charge_id = 'a5700001-0000-4000-8000-000000000003'
    and status = 'queued'
    and action = 'void';
  select private.group_filled_spots('a5500001-0000-4000-8000-000000000001')
    into v_filled;
  select count(*) into v_listed
  from public.venue_open_slots('a5200001-0000-4000-8000-000000000001')
  where session_id = 'a5400001-0000-4000-8000-000000000001';
  if v_winner <> 'confirmed' or v_filled <> 2 or v_listed <> 0
    or v_loser_attendance <> 'cancelled'
    or v_loser_refund <> 'refund_pending'
    or v_loser_reason <> 'group_did_not_close'
    or v_queue <> 1
  then
    raise exception
      'última vaga: winner % loser %/%/% fila % filled % lista %',
      v_winner, v_loser_attendance, v_loser_refund, v_loser_reason,
      v_queue, v_filled, v_listed;
  end if;
end $$;

-- Custódia HELD ocupa como paid. Ainda cabe uma vaga, e ela entra.
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'a5400001-0000-4000-8000-000000000002',
  'a5300001-0000-4000-8000-000000000001',
  '2027-09-02 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, closes_at
) values (
  'a5500001-0000-4000-8000-000000000002',
  'curitiba',
  'a5200001-0000-4000-8000-000000000001',
  'a5300001-0000-4000-8000-000000000001',
  'a5400001-0000-4000-8000-000000000002',
  '2027-09-02 18:00:00+00',
  2,
  2,
  9000,
  'a5100001-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00'
);

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  (
    'a5600001-0000-4000-8000-000000000011',
    'a5500001-0000-4000-8000-000000000002',
    'a5100001-0000-4000-8000-000000000001',
    'Vaga Paga',
    true,
    'reserved'
  ),
  (
    'a5600001-0000-4000-8000-000000000012',
    'a5500001-0000-4000-8000-000000000002',
    'a5100001-0000-4000-8000-000000000004',
    'Vaga Held',
    false,
    'pending'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider, provider_ref, idempotency_key, wallet_id, commission_bps,
  paid_at, attempt_id
) values (
  'a5700001-0000-4000-8000-000000000004',
  'a5500001-0000-4000-8000-000000000002',
  'a5100001-0000-4000-8000-000000000004',
  'a5200001-0000-4000-8000-000000000001',
  9000, 'PIX', 'paid', 'pagbank', 'CHAR_VAGA_HELD',
  'idem-vaga-held', 'wal_vaga', 2500, now(),
  'a5710001-0000-4000-8000-000000000004'
);

do $$
declare
  v_left integer;
begin
  if private.group_filled_spots('a5500001-0000-4000-8000-000000000002') <> 1 then
    raise exception 'reserved não ocupou';
  end if;
  select spots_left into v_left
  from public.venue_open_slots('a5200001-0000-4000-8000-000000000001')
  where session_id = 'a5400001-0000-4000-8000-000000000002';
  if v_left <> 1 then
    raise exception 'lista não bate com a custódia: %', v_left;
  end if;
end $$;

select private.sync_charge_member(c.*)
from public.payment_charges c
where c.id = 'a5700001-0000-4000-8000-000000000004';

do $$
begin
  if (
    select attendance from public.group_members
    where id = 'a5600001-0000-4000-8000-000000000012'
  ) <> 'confirmed' or private.group_filled_spots(
    'a5500001-0000-4000-8000-000000000002'
  ) <> 2 or exists (
    select 1 from public.member_refund_queue
    where charge_id = 'a5700001-0000-4000-8000-000000000004'
  ) then
    raise exception 'a segunda vaga com um reserved na frente não entrou';
  end if;
end $$;
