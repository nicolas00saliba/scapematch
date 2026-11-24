-- Sair no prazo enfileira. Fora do prazo não estorna. Remoção do
-- organizador enfileira. refunded só depois da cobrança estornada,
-- e esse caminho desfaz o ponto da reserva.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('fa100000-0000-4000-8000-000000000001', 'fa-org@example.com', '{"display_name":"Org"}'),
  ('fa100000-0000-4000-8000-000000000002', 'fa-jog@example.com', '{"display_name":"Jog"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'fa200000-0000-4000-8000-000000000001',
  'fa100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Estorno', 'Centro', 'Rua do Prazo', '8', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '19000000000991', '4130000991', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'fa300000-0000-4000-8000-000000000001',
  'fa200000-0000-4000-8000-000000000001',
  'Sala Estorno', '', 6, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  ('fa310000-0000-4000-8000-000000000001', 'fa300000-0000-4000-8000-000000000001', now() + interval '6 hours', 'partner_grid'),
  ('fa310000-0000-4000-8000-000000000002', 'fa300000-0000-4000-8000-000000000001', now() + interval '30 minutes', 'partner_grid'),
  ('fa310000-0000-4000-8000-000000000003', 'fa300000-0000-4000-8000-000000000001', now() + interval '8 hours', 'partner_grid');

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, confirmed_at
) values
  (
    'fa400000-0000-4000-8000-000000000001', 'curitiba',
    'fa200000-0000-4000-8000-000000000001',
    'fa300000-0000-4000-8000-000000000001',
    'fa310000-0000-4000-8000-000000000001',
    now() + interval '6 hours', 4, 2, 10000,
    'fa100000-0000-4000-8000-000000000001', now()
  ),
  (
    'fa400000-0000-4000-8000-000000000002', 'curitiba',
    'fa200000-0000-4000-8000-000000000001',
    'fa300000-0000-4000-8000-000000000001',
    'fa310000-0000-4000-8000-000000000002',
    now() + interval '30 minutes', 4, 2, 10000,
    'fa100000-0000-4000-8000-000000000001', now()
  ),
  (
    'fa400000-0000-4000-8000-000000000003', 'curitiba',
    'fa200000-0000-4000-8000-000000000001',
    'fa300000-0000-4000-8000-000000000001',
    'fa310000-0000-4000-8000-000000000003',
    now() + interval '8 hours', 4, 2, 10000,
    'fa100000-0000-4000-8000-000000000001', now()
  );

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  ('fa410000-0000-4000-8000-000000000001', 'fa400000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000001', 'Org', true, 'paid'),
  ('fa410000-0000-4000-8000-000000000011', 'fa400000-0000-4000-8000-000000000001', 'fa100000-0000-4000-8000-000000000002', 'Jog', false, 'paid'),
  ('fa410000-0000-4000-8000-000000000002', 'fa400000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000001', 'Org', true, 'paid'),
  ('fa410000-0000-4000-8000-000000000012', 'fa400000-0000-4000-8000-000000000002', 'fa100000-0000-4000-8000-000000000002', 'Jog', false, 'paid'),
  ('fa410000-0000-4000-8000-000000000003', 'fa400000-0000-4000-8000-000000000003', 'fa100000-0000-4000-8000-000000000001', 'Org', true, 'paid'),
  ('fa410000-0000-4000-8000-000000000013', 'fa400000-0000-4000-8000-000000000003', 'fa100000-0000-4000-8000-000000000002', 'Jog', false, 'paid');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, charged_amount_cents,
  buyer_interest_cents, billing_type, status, provider, provider_ref,
  idempotency_key, wallet_id, commission_bps, paid_at, attempt_id
) values
  (
    'fa500000-0000-4000-8000-000000000001',
    'fa400000-0000-4000-8000-000000000001',
    'fa100000-0000-4000-8000-000000000002',
    'fa200000-0000-4000-8000-000000000001',
    10000, 10640, 640, 'PIX', 'paid', 'pagbank', 'CHAR_IN',
    'idem-fa-in', 'wal', 1000, now(), 'fa510000-0000-4000-8000-000000000001'
  ),
  (
    'fa500000-0000-4000-8000-000000000002',
    'fa400000-0000-4000-8000-000000000002',
    'fa100000-0000-4000-8000-000000000002',
    'fa200000-0000-4000-8000-000000000001',
    10000, null, 0, 'CREDIT_CARD', 'paid', 'pagbank', 'CHAR_LATE',
    'idem-fa-late', 'wal', 1000, now(), 'fa510000-0000-4000-8000-000000000002'
  ),
  (
    'fa500000-0000-4000-8000-000000000003',
    'fa400000-0000-4000-8000-000000000003',
    'fa100000-0000-4000-8000-000000000002',
    'fa200000-0000-4000-8000-000000000001',
    10000, 10640, 640, 'CREDIT_CARD', 'paid', 'pagbank', 'CHAR_RM',
    'idem-fa-rm', 'wal', 1000, now(), 'fa510000-0000-4000-8000-000000000003'
  );

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'fa100000-0000-4000-8000-000000000002', true
  );
  perform public.leave_group('fa400000-0000-4000-8000-000000000001');
  if (
    select refund_status from public.group_members
    where id = 'fa410000-0000-4000-8000-000000000011'
  ) is distinct from 'refund_pending' then
    raise exception 'dentro do prazo marcou refunded cedo';
  end if;
  if not exists (
    select 1 from public.member_refund_queue
    where charge_id = 'fa500000-0000-4000-8000-000000000001'
      and action = 'refund' and status = 'queued'
  ) or (
    select refund_requested_at from public.payment_charges
    where id = 'fa500000-0000-4000-8000-000000000001'
  ) is null then
    raise exception 'dentro do prazo nao enfileirou';
  end if;

  perform public.leave_group('fa400000-0000-4000-8000-000000000002');
  if (
    select refund_status from public.group_members
    where id = 'fa410000-0000-4000-8000-000000000012'
  ) is distinct from 'denied' or exists (
    select 1 from public.member_refund_queue
    where charge_id = 'fa500000-0000-4000-8000-000000000002'
  ) then
    raise exception 'fora do prazo estornou';
  end if;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'fa100000-0000-4000-8000-000000000001', true
  );
  perform public.remove_member(
    'fa400000-0000-4000-8000-000000000003',
    'fa410000-0000-4000-8000-000000000013'
  );
  if (
    select refund_status from public.group_members
    where id = 'fa410000-0000-4000-8000-000000000013'
  ) is distinct from 'refund_pending' or not exists (
    select 1 from public.member_refund_queue
    where charge_id = 'fa500000-0000-4000-8000-000000000003'
      and action = 'refund'
  ) then
    raise exception 'remocao nao enfileirou';
  end if;
end $$;

insert into public.scape_point_entries (
  user_id, kind, points, amount_cents, program,
  source_charge_id, payment_charge_id, idempotency_key
) values (
  'fa100000-0000-4000-8000-000000000002', 'accrual', 10, 1000, 'welcome',
  'fa500000-0000-4000-8000-000000000001',
  'fa500000-0000-4000-8000-000000000001',
  'fa-ponto-in'
);

do $$
begin
  perform private.apply_payment_transition(
    'fa500000-0000-4000-8000-000000000001', 'paid', false
  );
  if (
    select refund_status from public.group_members
    where id = 'fa410000-0000-4000-8000-000000000011'
  ) is distinct from 'refund_pending' then
    raise exception 'replay de pago apagou o estorno pendente';
  end if;

  perform private.apply_payment_transition(
    'fa500000-0000-4000-8000-000000000001', 'refunded', false
  );
  if (
    select refund_status from public.group_members
    where id = 'fa410000-0000-4000-8000-000000000011'
  ) is distinct from 'refunded' or not exists (
    select 1 from public.scape_point_entries
    where kind = 'reversal'
      and source_charge_id = 'fa500000-0000-4000-8000-000000000001'
  ) then
    raise exception 'estorno confirmado nao devolveu o ponto';
  end if;
end $$;

select 'member refund ok';
