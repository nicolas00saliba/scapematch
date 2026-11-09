-- Término não pago devolve crédito, clawback e débito. A sala é compartilhada.

\set ON_ERROR_STOP on

begin;

select set_config('request.jwt.claim.sub', '', true);

update public.referral_program_settings
set first_booking_discount_bps = 0
where id = 1;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'ee100000-0000-4000-8000-0000000000aa',
  'libera@example.com',
  '{"display_name":"Libera"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ee200000-0000-4000-8000-0000000000aa',
  'ee100000-0000-4000-8000-0000000000aa',
  'curitiba', 'Casa Libera', 'Centro', 'Rua Solta', '5', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '45997418000153', '4130000155', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ee300000-0000-4000-8000-0000000000aa',
  'ee200000-0000-4000-8000-0000000000aa',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ee310000-0000-4000-8000-0000000000aa',
  'ee300000-0000-4000-8000-0000000000aa',
  '2027-03-01 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  ('ee400000-0000-4000-8000-0000000000a1', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-01 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000a2', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-02 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000a3', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-03 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000a4', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-04 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa');

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'ee400000-0000-4000-8000-0000000000a2',
  'ee100000-0000-4000-8000-0000000000aa',
  'Libera', true, 'pending', 'none', 'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps, paid_at, attempt_id
) values
  ('ee500000-0000-4000-8000-0000000000a1', 'ee400000-0000-4000-8000-0000000000a1', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-libera-origem', 'wal', 2500, now(), 'ee510000-0000-4000-8000-0000000000a1'),
  ('ee500000-0000-4000-8000-0000000000a2', 'ee400000-0000-4000-8000-0000000000a2', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'creating', 'idem-libera-cria', 'wal', 2500, null, 'ee510000-0000-4000-8000-0000000000a2');

insert into public.venue_referral_entries (
  venue_id, kind, amount_cents, program, settlement, source_charge_id,
  idempotency_key, available_at, applied_cents
) values (
  'ee200000-0000-4000-8000-0000000000aa', 'accrual', 2000, 'b2c', 'released',
  'ee500000-0000-4000-8000-0000000000a1', 'idem-libera-credito', now(), 0
);

do $$
begin
  if private.apply_venue_credit(
    'ee500000-0000-4000-8000-0000000000a2',
    'ee200000-0000-4000-8000-0000000000aa',
    10000
  ) <> 2000 then
    raise exception 'o credito nao entrou na cobranca creating';
  end if;
  perform private.apply_payment_transition(
    'ee500000-0000-4000-8000-0000000000a2', 'cancelled', false
  );
  if (
    select settlement from public.venue_referral_entries
    where idempotency_key = 'idem-libera-credito'
  ) is distinct from 'released' or (
    select applied_cents from public.venue_referral_entries
    where idempotency_key = 'idem-libera-credito'
  ) <> 0 or exists (
    select 1 from public.venue_credit_applications
    where payment_charge_id = 'ee500000-0000-4000-8000-0000000000a2'
  ) then
    raise exception 'cancelled nao devolveu o credito';
  end if;
end $$;

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps, attempt_id, reserved_at
) values (
  'ee500000-0000-4000-8000-0000000000a3',
  'ee400000-0000-4000-8000-0000000000a3',
  'ee100000-0000-4000-8000-0000000000aa',
  'ee200000-0000-4000-8000-0000000000aa',
  10000, 'PIX', 'creating', 'idem-libera-pix', 'wal', 2500,
  'ee510000-0000-4000-8000-0000000000a3', now()
);

do $$
declare
  v_released boolean;
  v_exists boolean;
  v_applied integer;
begin
  if private.apply_venue_credit(
    'ee500000-0000-4000-8000-0000000000a3',
    'ee200000-0000-4000-8000-0000000000aa',
    10000
  ) <> 2000 then
    raise exception 'o segundo credito nao entrou';
  end if;
  v_released := private.release_pix_reservation(
    'ee500000-0000-4000-8000-0000000000a3',
    'ee510000-0000-4000-8000-0000000000a3'
  );
  v_exists := exists (
    select 1 from public.payment_charges
    where id = 'ee500000-0000-4000-8000-0000000000a3'
  );
  select applied_cents into v_applied
  from public.venue_referral_entries
  where idempotency_key = 'idem-libera-credito';
  if v_released is not true or v_exists or v_applied <> 0 then
    raise exception 'release pix % / existe % / applied %',
      v_released, v_exists, v_applied;
  end if;
end $$;

do $$
declare
  v_taken integer;
begin
  if to_regprocedure('private.apply_empty_slot_debit(uuid,uuid,integer,boolean)') is null then
    return;
  end if;
  update public.venue_referral_entries
  set settlement = 'reversed', applied_cents = 0
  where idempotency_key = 'idem-libera-credito';
  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, settlement, source_charge_id,
    idempotency_key, available_at, applied_cents
  ) values (
    'ee200000-0000-4000-8000-0000000000aa', 'accrual', 4000, 'b2b', 'released',
    'ee500000-0000-4000-8000-0000000000a1', 'idem-libera-claw', now(), 0
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'ee500000-0000-4000-8000-0000000000a4',
    'ee400000-0000-4000-8000-0000000000a4',
    'ee100000-0000-4000-8000-0000000000aa',
    'ee200000-0000-4000-8000-0000000000aa',
    10000, 'PIX', 'paid', 'idem-libera-pago', 'wal', 2500, now()
  );
  if private.apply_venue_credit(
    'ee500000-0000-4000-8000-0000000000a4',
    'ee200000-0000-4000-8000-0000000000aa',
    10000
  ) <> 4000 then
    raise exception 'o credito do clawback nao aplicou';
  end if;
  perform private.reverse_referral_rewards('ee500000-0000-4000-8000-0000000000a1');
  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents
  ) values (
    'ee200000-0000-4000-8000-0000000000aa',
    'ee500000-0000-4000-8000-0000000000a4',
    4000
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'ee400000-0000-4000-8000-0000000000a5',
    'curitiba', 'ee200000-0000-4000-8000-0000000000aa',
    'ee300000-0000-4000-8000-0000000000aa',
    'ee310000-0000-4000-8000-0000000000aa',
    '2027-03-05 18:00:00+00', 4, 2, 10000,
    'ee100000-0000-4000-8000-0000000000aa'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'ee400000-0000-4000-8000-0000000000a5',
    'ee100000-0000-4000-8000-0000000000aa',
    'Libera', true, 'pending', 'none', 'none'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'ee500000-0000-4000-8000-0000000000a5',
    'ee400000-0000-4000-8000-0000000000a5',
    'ee100000-0000-4000-8000-0000000000aa',
    'ee200000-0000-4000-8000-0000000000aa',
    10000, 'PIX', 'creating', 'idem-libera-sala', 'wal', 2500
  );
  perform private.apply_share_adjustments('ee500000-0000-4000-8000-0000000000a5');
  select empty_slot_offset_cents + venue_credit_clawback_cents into v_taken
  from public.payment_charges
  where id = 'ee500000-0000-4000-8000-0000000000a5';
  if v_taken is distinct from 4000 then
    raise exception 'debito e clawback dividiram a sala duas vezes: %', v_taken;
  end if;
  perform private.apply_payment_transition(
    'ee500000-0000-4000-8000-0000000000a5', 'failed', false
  );
  if exists (
    select 1 from public.venue_cashback_debits
    where source_charge_id = 'ee500000-0000-4000-8000-0000000000a4'
      and applied_cents <> 0
  ) or exists (
    select 1 from public.venue_credit_clawbacks
    where venue_id = 'ee200000-0000-4000-8000-0000000000aa'
      and voided_at is null
      and applied_cents <> 0
  ) then
    raise exception 'failed nao devolveu debito ou clawback';
  end if;
end $$;

do $$
declare
  v_offset integer;
  v_refund integer;
begin
  if to_regprocedure('private.apply_empty_slot_debit(uuid,uuid,integer,boolean)') is null then
    return;
  end if;
  update public.referral_program_settings
  set first_booking_discount_bps = 0
  where id = 1;
  update public.venue_cashback_debits
  set voided_at = pg_catalog.now()
  where venue_id = 'ee200000-0000-4000-8000-0000000000aa'
    and voided_at is null;
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    ('ee400000-0000-4000-8000-0000000000b1', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-11 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
    ('ee400000-0000-4000-8000-0000000000b2', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-12 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
    ('ee400000-0000-4000-8000-0000000000b3', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-03-13 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa');
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values
    ('ee400000-0000-4000-8000-0000000000b2', 'ee100000-0000-4000-8000-0000000000aa', 'Libera', true, 'pending', 'none', 'none'),
    ('ee400000-0000-4000-8000-0000000000b3', 'ee100000-0000-4000-8000-0000000000aa', 'Libera', true, 'pending', 'none', 'none');
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'ee500000-0000-4000-8000-0000000000b1',
    'ee400000-0000-4000-8000-0000000000b1',
    'ee100000-0000-4000-8000-0000000000aa',
    'ee200000-0000-4000-8000-0000000000aa',
    10000, 'PIX', 'paid', 'idem-janela-origem', 'wal', 2500, now()
  );
  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents
  ) values (
    'ee200000-0000-4000-8000-0000000000aa',
    'ee500000-0000-4000-8000-0000000000b1',
    4000
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'ee500000-0000-4000-8000-0000000000b2',
    'ee400000-0000-4000-8000-0000000000b2',
    'ee100000-0000-4000-8000-0000000000aa',
    'ee200000-0000-4000-8000-0000000000aa',
    10000, 'PIX', 'creating', 'idem-janela-reserva', 'wal', 2500
  );
  perform private.apply_share_adjustments('ee500000-0000-4000-8000-0000000000b2');
  perform private.reverse_referral_rewards('ee500000-0000-4000-8000-0000000000b1');
  perform private.apply_payment_transition(
    'ee500000-0000-4000-8000-0000000000b2', 'cancelled', false
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'ee500000-0000-4000-8000-0000000000b3',
    'ee400000-0000-4000-8000-0000000000b3',
    'ee100000-0000-4000-8000-0000000000aa',
    'ee200000-0000-4000-8000-0000000000aa',
    10000, 'PIX', 'creating', 'idem-janela-seguinte', 'wal', 2500
  );
  perform private.apply_share_adjustments('ee500000-0000-4000-8000-0000000000b3');
  select empty_slot_offset_cents, cashback_refund_cents
    into v_offset, v_refund
  from public.payment_charges
  where id = 'ee500000-0000-4000-8000-0000000000b3';
  if v_offset <> 0 or v_refund <> 0 or exists (
    select 1 from public.venue_cashback_debits d
    where d.source_charge_id = 'ee500000-0000-4000-8000-0000000000b1'
      and d.voided_at is null
  ) or exists (
    select 1 from public.venue_cashback_refunds f
    join public.venue_cashback_debits d on d.id = f.debit_id
    where d.source_charge_id = 'ee500000-0000-4000-8000-0000000000b1'
      and f.voided_at is null
  ) then
    raise exception 'reserva estornada ainda cobrou horario vazio % / %', v_offset, v_refund;
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    ('ee400000-0000-4000-8000-0000000000b4', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-04 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
    ('ee400000-0000-4000-8000-0000000000b5', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-05 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa');
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values
    ('ee500000-0000-4000-8000-0000000000b4', 'ee400000-0000-4000-8000-0000000000b4', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-pago-origem', 'wal', 2500, now()),
    ('ee500000-0000-4000-8000-0000000000b5', 'ee400000-0000-4000-8000-0000000000b5', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-pago-absorve', 'wal', 2500, now());
  insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
  values (
    'ee200000-0000-4000-8000-0000000000aa',
    'ee500000-0000-4000-8000-0000000000b4',
    4000
  );
  perform private.apply_share_adjustments('ee500000-0000-4000-8000-0000000000b5');
  if (
    select empty_slot_offset_cents from public.payment_charges
    where id = 'ee500000-0000-4000-8000-0000000000b5'
  ) <> 4000 then
    raise exception 'debito pago nao foi lancado';
  end if;
  perform private.reverse_referral_rewards('ee500000-0000-4000-8000-0000000000b4');
  if not exists (
    select 1 from public.venue_cashback_refunds f
    join public.venue_cashback_debits d on d.id = f.debit_id
    where d.source_charge_id = 'ee500000-0000-4000-8000-0000000000b4'
      and d.voided_at is null
      and f.voided_at is null
      and f.amount_cents = 4000
      and f.applied_cents = 0
  ) then
    raise exception 'estorno de debito pago nao gerou devolucao';
  end if;
end $$;

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  ('ee400000-0000-4000-8000-0000000000c1', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-11 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000c2', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-12 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000c3', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-13 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000c4', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-14 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000c5', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-15 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa'),
  ('ee400000-0000-4000-8000-0000000000c6', 'curitiba', 'ee200000-0000-4000-8000-0000000000aa', 'ee300000-0000-4000-8000-0000000000aa', 'ee310000-0000-4000-8000-0000000000aa', '2027-08-16 18:00:00+00', 4, 2, 10000, 'ee100000-0000-4000-8000-0000000000aa');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps
) values
  ('ee500000-0000-4000-8000-0000000000c1', 'ee400000-0000-4000-8000-0000000000c1', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-split-origem', 'wal', 2500),
  ('ee500000-0000-4000-8000-0000000000c2', 'ee400000-0000-4000-8000-0000000000c2', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-split-pago', 'wal', 2500),
  ('ee500000-0000-4000-8000-0000000000c3', 'ee400000-0000-4000-8000-0000000000c3', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'creating', 'idem-split-reserva', 'wal', 2500),
  ('ee500000-0000-4000-8000-0000000000c4', 'ee400000-0000-4000-8000-0000000000c4', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-split-origem-2', 'wal', 2500),
  ('ee500000-0000-4000-8000-0000000000c5', 'ee400000-0000-4000-8000-0000000000c5', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'paid', 'idem-split-pago-2', 'wal', 2500),
  ('ee500000-0000-4000-8000-0000000000c6', 'ee400000-0000-4000-8000-0000000000c6', 'ee100000-0000-4000-8000-0000000000aa', 'ee200000-0000-4000-8000-0000000000aa', 10000, 'PIX', 'creating', 'idem-split-reserva-2', 'wal', 2500);

insert into public.venue_referral_entries (
  id, venue_id, kind, amount_cents, program, settlement, source_charge_id,
  idempotency_key, available_at, applied_cents
) values
  ('ee600000-0000-4000-8000-0000000000c1', 'ee200000-0000-4000-8000-0000000000aa', 'accrual', 700, 'b2c', 'applied', 'ee500000-0000-4000-8000-0000000000c1', 'idem-split-credito', now(), 700),
  ('ee600000-0000-4000-8000-0000000000c2', 'ee200000-0000-4000-8000-0000000000aa', 'accrual', 700, 'b2c', 'applied', 'ee500000-0000-4000-8000-0000000000c4', 'idem-split-credito-2', now(), 700);

insert into public.venue_credit_applications (entry_id, payment_charge_id, amount_cents)
values
  ('ee600000-0000-4000-8000-0000000000c1', 'ee500000-0000-4000-8000-0000000000c2', 400),
  ('ee600000-0000-4000-8000-0000000000c1', 'ee500000-0000-4000-8000-0000000000c3', 300),
  ('ee600000-0000-4000-8000-0000000000c2', 'ee500000-0000-4000-8000-0000000000c5', 400),
  ('ee600000-0000-4000-8000-0000000000c2', 'ee500000-0000-4000-8000-0000000000c6', 300);

do $$
begin
  perform private.reverse_referral_rewards('ee500000-0000-4000-8000-0000000000c1');
  if (
    select amount_cents from public.venue_credit_clawbacks
    where entry_id = 'ee600000-0000-4000-8000-0000000000c1'
      and voided_at is null
  ) is distinct from 400 or exists (
    select 1 from public.venue_credit_applications
    where payment_charge_id = 'ee500000-0000-4000-8000-0000000000c3'
  ) then
    raise exception 'reserva de credito virou clawback';
  end if;
  perform private.release_unpaid_components('ee500000-0000-4000-8000-0000000000c6');
  if (
    select applied_cents from public.venue_referral_entries
    where id = 'ee600000-0000-4000-8000-0000000000c2'
  ) <> 400 or (
    select settlement from public.venue_referral_entries
    where id = 'ee600000-0000-4000-8000-0000000000c2'
  ) is distinct from 'applied' or not exists (
    select 1 from public.venue_credit_applications
    where entry_id = 'ee600000-0000-4000-8000-0000000000c2'
      and payment_charge_id = 'ee500000-0000-4000-8000-0000000000c5'
      and amount_cents = 400
  ) then
    raise exception 'liberar a reserva apagou a parte paga do credito';
  end if;
end $$;

rollback;
