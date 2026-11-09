-- Estorno de crédito da casa e livro. Sem Asaas. Desfaz no final.
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_entry uuid;
  v_taken integer;
  v_house integer;
  v_credit integer;
  v_gate text;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    ('c1000000-0000-4000-8000-000000000001', 'estorno-casa@example.com', '{"display_name":"Estorno Casa"}'),
    ('c1000000-0000-4000-8000-000000000002', 'estorno-jogador@example.com', '{"display_name":"Estorno Jogador"}');
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    'c2000000-0000-4000-8000-000000000001',
    'c1000000-0000-4000-8000-000000000001',
    'curitiba', 'Casa Estorno', 'Centro', 'Rua do Estorno', '9',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '90807060000103', '4130000199', 'approved'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    'c3000000-0000-4000-8000-000000000001',
    'c2000000-0000-4000-8000-000000000001',
    'Sala Estorno', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability) values (
    'c3100000-0000-4000-8000-000000000001',
    'c3000000-0000-4000-8000-000000000001',
    '2027-08-01 18:00:00+00', 'partner_grid'
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    ('c4000000-0000-4000-8000-000000000001', 'curitiba', 'c2000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000001', 'c3100000-0000-4000-8000-000000000001', '2027-08-01 18:00:00+00', 4, 2, 10000, 'c1000000-0000-4000-8000-000000000001'),
    ('c4000000-0000-4000-8000-000000000002', 'curitiba', 'c2000000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-000000000001', 'c3100000-0000-4000-8000-000000000001', '2027-08-02 18:00:00+00', 4, 2, 10000, 'c1000000-0000-4000-8000-000000000001');
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values
    ('c5000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-estorno-origem', 'wal', 2500, now()),
    ('c5000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000001', 10000, 'PIX', 'creating', 'idem-estorno-seguinte', 'wal', 2500, null);

  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, settlement, source_charge_id,
    idempotency_key, available_at, applied_cents
  ) values (
    'c2000000-0000-4000-8000-000000000001', 'accrual', 400, 'b2c', 'released',
    'c5000000-0000-4000-8000-000000000001', 'idem-credito-estorno', now(), 0
  ) returning id into v_entry;

  perform private.reverse_referral_rewards('c5000000-0000-4000-8000-000000000001');
  if (
    select settlement from public.venue_referral_entries where id = v_entry
  ) is distinct from 'reversed' then
    raise exception 'credito liberado continuou elegivel depois do estorno';
  end if;
  v_taken := private.apply_venue_credit(
    'c5000000-0000-4000-8000-000000000002',
    'c2000000-0000-4000-8000-000000000001',
    2500
  );
  if v_taken <> 0 then
    raise exception 'split seguinte levou credito estornado %', v_taken;
  end if;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values
    ('c2000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'house', 'credit', 'house_net', 7500, 'c5000000-0000-4000-8000-000000000002'),
    ('c2000000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002', 'house', 'credit', 'venue_credit_applied', 400, 'c5000000-0000-4000-8000-000000000002');
  perform private.ledger_reverse_charge('c5000000-0000-4000-8000-000000000002');
  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = 'c5000000-0000-4000-8000-000000000002'
    and kind = 'house_refund' and direction = 'debit';
  select amount_cents into v_credit
  from public.ledger_entries
  where payment_charge_id = 'c5000000-0000-4000-8000-000000000002'
    and kind = 'venue_credit_refund' and direction = 'debit';
  if v_house is distinct from 7500 or v_credit is distinct from 400 then
    raise exception 'livro nao estornou o credito aplicado % / %', v_house, v_credit;
  end if;

  update public.payment_charges
  set payer_document_hash = null, payer_card_key = null
  where id = 'c5000000-0000-4000-8000-000000000001';
  v_gate := private.referral_reward_gate(
    'c5000000-0000-4000-8000-000000000001',
    'c2c',
    'c1000000-0000-4000-8000-000000000001',
    null,
    'c1000000-0000-4000-8000-000000000002',
    null
  );
  if v_gate is distinct from 'em_revisao' then
    raise exception 'indicacao sem documento do pagador foi lancada %', v_gate;
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'c4000000-0000-4000-8000-000000000003', 'curitiba',
    'c2000000-0000-4000-8000-000000000001',
    'c3000000-0000-4000-8000-000000000001',
    'c3100000-0000-4000-8000-000000000001',
    '2027-08-03 18:00:00+00', 4, 2, 10000,
    'c1000000-0000-4000-8000-000000000001'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'c5000000-0000-4000-8000-000000000003',
    'c4000000-0000-4000-8000-000000000003',
    'c1000000-0000-4000-8000-000000000002',
    'c2000000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid', 'idem-cadeia-consumidora', 'wal', 2500
  );
  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, settlement, source_charge_id,
    idempotency_key, available_at, applied_cents
  ) values (
    'c2000000-0000-4000-8000-000000000001', 'accrual', 400, 'b2b', 'released',
    'c5000000-0000-4000-8000-000000000001', 'idem-cadeia-credito', now(), 0
  );
  if private.apply_venue_credit(
    'c5000000-0000-4000-8000-000000000003',
    'c2000000-0000-4000-8000-000000000001',
    2500
  ) <> 400 then
    raise exception 'a cadeia nao aplicou os 400';
  end if;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'c2000000-0000-4000-8000-000000000001',
    'c4000000-0000-4000-8000-000000000003',
    'c1000000-0000-4000-8000-000000000002',
    'house', 'credit', 'venue_credit_applied', 400,
    'c5000000-0000-4000-8000-000000000003'
  );
  perform private.reverse_referral_rewards('c5000000-0000-4000-8000-000000000001');
  if private.apply_venue_clawback(
    'c5000000-0000-4000-8000-000000000002',
    'c2000000-0000-4000-8000-000000000001',
    7500
  ) <> 400 then
    raise exception 'clawback nao foi cobrado';
  end if;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind, amount_cents, payment_charge_id
  ) values (
    'c2000000-0000-4000-8000-000000000001',
    'c4000000-0000-4000-8000-000000000002',
    'c1000000-0000-4000-8000-000000000002',
    'house', 'debit', 'venue_credit_clawback', 400,
    'c5000000-0000-4000-8000-000000000002'
  );
  perform private.ledger_reverse_charge('c5000000-0000-4000-8000-000000000003');
  if (
    select coalesce(sum(
      case direction when 'credit' then amount_cents else -amount_cents end
    ), 0)
    from public.ledger_entries
    where venue_id = 'c2000000-0000-4000-8000-000000000001'
      and kind in (
      'venue_credit_applied', 'venue_credit_refund',
      'venue_credit_clawback', 'venue_credit_clawback_refund',
      'venue_credit_clawback_offset'
    )
  ) <> 0 then
    raise exception 'a casa devolveu o credito e ainda pagou o clawback %', (
      select string_agg(payment_charge_id::text || ':' || kind || ':' || direction || ':' || amount_cents::text, ',')
      from public.ledger_entries
      where venue_id = 'c2000000-0000-4000-8000-000000000001'
        and kind like 'venue_credit%'
    );
  end if;
  if (
    select neutralized_at is null from public.venue_credit_clawbacks
    where amount_cents = 400
  ) then
    raise exception 'clawback cobrado continuou aberto depois do estorno';
  end if;
end $$;

rollback;
