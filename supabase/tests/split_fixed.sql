-- fixedValue em centavos bate com o livro. Taxa estimada não come a casa.

\set ON_ERROR_STOP on

begin;

select set_config('request.jwt.claim.sub', '', true);

update public.referral_program_settings
set first_booking_discount_bps = 0
where id = 1;

update public.platform_settings
set pix_receipt_fee_cents = 199,
    card_receipt_fee_cents = 49,
    card_receipt_fee_bps = 299
where id = 1;

do $$
begin
  if private.estimated_receipt_fee_cents('PIX', 10000) <> 199 then
    raise exception 'taxa pix';
  end if;
  if private.estimated_receipt_fee_cents('CREDIT_CARD', 10000) <> 348 then
    raise exception 'taxa cartao';
  end if;
  if private.estimated_receipt_fee_cents('CREDIT_CARD', 2000) <> 109 then
    raise exception 'taxa cartao pequena';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'ff100000-0000-4000-8000-000000000001',
  'fixo@example.com',
  '{"display_name":"Fixo"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ff200000-0000-4000-8000-000000000001',
  'ff100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Fixa', 'Centro', 'Rua do Fixo', '8', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '90807060000103', '4130000188', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ff300000-0000-4000-8000-000000000001',
  'ff200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ff310000-0000-4000-8000-000000000001',
  'ff300000-0000-4000-8000-000000000001',
  '2027-11-01 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  ('ff400000-0000-4000-8000-000000000001', 'curitiba', 'ff200000-0000-4000-8000-000000000001', 'ff300000-0000-4000-8000-000000000001', 'ff310000-0000-4000-8000-000000000001', '2027-11-01 18:00:00+00', 4, 2, 10000, 'ff100000-0000-4000-8000-000000000001'),
  ('ff400000-0000-4000-8000-000000000002', 'curitiba', 'ff200000-0000-4000-8000-000000000001', 'ff300000-0000-4000-8000-000000000001', 'ff310000-0000-4000-8000-000000000001', '2027-11-02 18:00:00+00', 4, 2, 10000, 'ff100000-0000-4000-8000-000000000001'),
  ('ff400000-0000-4000-8000-000000000003', 'curitiba', 'ff200000-0000-4000-8000-000000000001', 'ff300000-0000-4000-8000-000000000001', 'ff310000-0000-4000-8000-000000000001', '2027-11-03 18:00:00+00', 4, 2, 10000, 'ff100000-0000-4000-8000-000000000001'),
  ('ff400000-0000-4000-8000-000000000004', 'curitiba', 'ff200000-0000-4000-8000-000000000001', 'ff300000-0000-4000-8000-000000000001', 'ff310000-0000-4000-8000-000000000001', '2027-11-04 18:00:00+00', 4, 2, 10000, 'ff100000-0000-4000-8000-000000000001');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps, provider, provider_ref
) values
  ('ff500000-0000-4000-8000-000000000001', 'ff400000-0000-4000-8000-000000000001', 'ff100000-0000-4000-8000-000000000001', 'ff200000-0000-4000-8000-000000000001', 10000, 'PIX', 'creating', 'idem-fixo-credito', 'wal', 2500, 'asaas', null),
  ('ff500000-0000-4000-8000-000000000002', 'ff400000-0000-4000-8000-000000000002', 'ff100000-0000-4000-8000-000000000001', 'ff200000-0000-4000-8000-000000000001', 10000, 'PIX', 'creating', 'idem-fixo-grande', 'wal', 2500, 'asaas', null),
  ('ff500000-0000-4000-8000-000000000003', 'ff400000-0000-4000-8000-000000000003', 'ff100000-0000-4000-8000-000000000001', 'ff200000-0000-4000-8000-000000000001', 1500, 'PIX', 'creating', 'idem-fixo-apertado', 'wal', 1000, 'asaas', null),
  ('ff500000-0000-4000-8000-000000000004', 'ff400000-0000-4000-8000-000000000004', 'ff100000-0000-4000-8000-000000000001', 'ff200000-0000-4000-8000-000000000001', 10000, 'PIX', 'pending', 'idem-fixo-alerta', 'wal', 2500, 'asaas', 'pay_divergence');

insert into public.venue_referral_entries (
  venue_id, kind, amount_cents, program, settlement, source_charge_id,
  idempotency_key, available_at, applied_cents
) values
  ('ff200000-0000-4000-8000-000000000001', 'accrual', 400, 'b2c', 'released', 'ff500000-0000-4000-8000-000000000004', 'idem-fixo-400', now(), 0),
  ('ff200000-0000-4000-8000-000000000001', 'accrual', 5000, 'b2b', 'released', 'ff500000-0000-4000-8000-000000000004', 'idem-fixo-5000', now(), 0);

do $$
declare
  v_fixed integer;
  v_house integer;
begin
  perform private.apply_share_adjustments('ff500000-0000-4000-8000-000000000001');
  v_fixed := private.sync_house_fixed('ff500000-0000-4000-8000-000000000001');
  if v_fixed <> 7900 or (
    select venue_credit_applied_cents
    from public.payment_charges
    where id = 'ff500000-0000-4000-8000-000000000001'
  ) <> 400 then
    raise exception 'credito que cabe nao entrou no fixo %', v_fixed;
  end if;
  update public.payment_charges
  set status = 'paid', paid_at = pg_catalog.now()
  where id = 'ff500000-0000-4000-8000-000000000001';
  perform private.ledger_credit_charge('ff500000-0000-4000-8000-000000000001');
  select coalesce(sum(
    case when direction = 'credit' then amount_cents else -amount_cents end
  ), 0) into v_house
  from public.ledger_entries
  where payment_charge_id = 'ff500000-0000-4000-8000-000000000001'
    and account = 'house';
  if v_house <> v_fixed then
    raise exception 'livro % diferente do fixo %', v_house, v_fixed;
  end if;

  perform private.apply_share_adjustments('ff500000-0000-4000-8000-000000000002');
  v_fixed := private.sync_house_fixed('ff500000-0000-4000-8000-000000000002');
  if v_fixed <> 7500 or (
    select venue_credit_applied_cents
    from public.payment_charges
    where id = 'ff500000-0000-4000-8000-000000000002'
  ) <> 0 then
    raise exception 'credito maior que a sala depois da taxa entrou %', v_fixed;
  end if;

  begin
    perform private.sync_house_fixed('ff500000-0000-4000-8000-000000000003');
    raise exception 'comissao menor que a taxa foi aceita';
  exception
    when sqlstate '23514' then
      if sqlerrm not like '%split_excede_liquido%' then
        raise;
      end if;
  end;

  if not private.note_split_divergence(
    'pay_divergence', 'PAYMENT_SPLIT_DIVERGENCE_BLOCK'
  ) then
    raise exception 'alerta de divergencia nao gravou';
  end if;
  if (
    select split_divergence_event
    from public.payment_charges
    where id = 'ff500000-0000-4000-8000-000000000004'
  ) is distinct from 'PAYMENT_SPLIT_DIVERGENCE_BLOCK' then
    raise exception 'evento de divergencia ausente';
  end if;
  if private.note_split_divergence('pay_divergence', 'PAYMENT_RECEIVED') then
    raise exception 'evento comum virou alerta';
  end if;
end $$;

do $$
declare
  v_fixed integer;
begin
  if to_regclass('public.venue_cashback_debits') is null then
    return;
  end if;
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'ff400000-0000-4000-8000-000000000005', 'curitiba',
    'ff200000-0000-4000-8000-000000000001',
    'ff300000-0000-4000-8000-000000000001',
    'ff310000-0000-4000-8000-000000000001',
    '2027-11-05 18:00:00+00', 4, 2, 10000,
    'ff100000-0000-4000-8000-000000000001'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, provider
  ) values (
    'ff500000-0000-4000-8000-000000000005',
    'ff400000-0000-4000-8000-000000000005',
    'ff100000-0000-4000-8000-000000000001',
    'ff200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'creating', 'idem-fixo-debito', 'wal', 2500, 'asaas'
  );
  insert into public.venue_cashback_debits (
    venue_id, source_charge_id, amount_cents
  ) values (
    'ff200000-0000-4000-8000-000000000001',
    'ff500000-0000-4000-8000-000000000004',
    400
  );
  perform private.apply_share_adjustments('ff500000-0000-4000-8000-000000000005');
  v_fixed := private.sync_house_fixed('ff500000-0000-4000-8000-000000000005');
  if v_fixed <> 7100 or (
    select empty_slot_offset_cents from public.payment_charges
    where id = 'ff500000-0000-4000-8000-000000000005'
  ) <> 400 then
    raise exception 'debito de horario vazio nao saiu do fixo %', v_fixed;
  end if;
end $$;

rollback;
