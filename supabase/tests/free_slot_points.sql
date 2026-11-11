-- Vaga grátis com pontos de indicação. Não fala com o Asaas.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e7a11111-1111-4111-8111-111111111111',
  'vaga-indicado@example.com',
  '{"display_name":"Vaga Indicado"}'
);

update public.profiles
set cpf = '10203040570', phone = '41966660011'
where id = 'e7a11111-1111-4111-8111-111111111111';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e7a22222-2222-4222-8222-222222222222',
  'vaga-colega@example.com',
  '{"display_name":"Vaga Colega"}'
);

update public.profiles
set cpf = '24681357928', phone = '41966660022'
where id = 'e7a22222-2222-4222-8222-222222222222';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e7a33333-3333-4333-8333-333333333333',
  'vaga-parcial@example.com',
  '{"display_name":"Vaga Parcial"}'
);

update public.profiles
set cpf = '12345678909', phone = '41966660033'
where id = 'e7a33333-3333-4333-8333-333333333333';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e7a44444-4444-4444-8444-444444444444',
  'vaga-fraude@example.com',
  '{"display_name":"Vaga Fraude"}'
);

update public.profiles
set cpf = '39053344705', phone = '41966660044'
where id = 'e7a44444-4444-4444-8444-444444444444';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e7a55555-5555-4555-8555-555555555555',
  'vaga-boasvindas@example.com',
  '{"display_name":"Vaga Boas Vindas"}'
);

update public.profiles
set cpf = '52998224725', phone = '41966660055'
where id = 'e7a55555-5555-4555-8555-555555555555';

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'e7b11111-1111-4111-8111-111111111111',
  'e7a11111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa Vaga Gratis',
  'Centro',
  'Rua da Vaga',
  '11',
  '80010010',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '88776655000199',
  '4133339911',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'e7c11111-1111-4111-8111-111111111111',
  'e7b11111-1111-4111-8111-111111111111',
  'Sala Vaga',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  (
    'e7d11111-1111-4111-8111-111111111111',
    'e7c11111-1111-4111-8111-111111111111',
    '2027-09-01 18:00:00+00',
    'partner_grid'
  ),
  (
    'e7d22222-2222-4222-8222-222222222222',
    'e7c11111-1111-4111-8111-111111111111',
    '2027-09-02 18:00:00+00',
    'partner_grid'
  ),
  (
    'e7d33333-3333-4333-8333-333333333333',
    'e7c11111-1111-4111-8111-111111111111',
    '2027-09-03 18:00:00+00',
    'partner_grid'
  );

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    'e7e11111-1111-4111-8111-111111111111',
    'curitiba',
    'e7b11111-1111-4111-8111-111111111111',
    'e7c11111-1111-4111-8111-111111111111',
    'e7d11111-1111-4111-8111-111111111111',
    '2027-09-01 18:00:00+00',
    4, 2, 10000,
    'e7a11111-1111-4111-8111-111111111111'
  ),
  (
    'e7e22222-2222-4222-8222-222222222222',
    'curitiba',
    'e7b11111-1111-4111-8111-111111111111',
    'e7c11111-1111-4111-8111-111111111111',
    'e7d22222-2222-4222-8222-222222222222',
    '2027-09-02 18:00:00+00',
    4, 2, 10000,
    'e7a22222-2222-4222-8222-222222222222'
  ),
  (
    'e7e33333-3333-4333-8333-333333333333',
    'curitiba',
    'e7b11111-1111-4111-8111-111111111111',
    'e7c11111-1111-4111-8111-111111111111',
    'e7d33333-3333-4333-8333-333333333333',
    '2027-09-03 18:00:00+00',
    4, 2, 10000,
    'e7a33333-3333-4333-8333-333333333333'
  );

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values
  (
    'e7e11111-1111-4111-8111-111111111111',
    'e7a11111-1111-4111-8111-111111111111',
    'Vaga Indicado', true, 'pending', 'none', 'none'
  ),
  (
    'e7e22222-2222-4222-8222-222222222222',
    'e7a22222-2222-4222-8222-222222222222',
    'Vaga Colega', true, 'pending', 'none', 'none'
  ),
  (
    'e7e33333-3333-4333-8333-333333333333',
    'e7a33333-3333-4333-8333-333333333333',
    'Vaga Parcial', true, 'pending', 'none', 'none'
  );

do $$
declare
  v_before public.referral_program_settings%rowtype;
  v_pix integer;
  v_card integer;
  v_bps integer;
  v_quote jsonb;
  v_held jsonb;
  v_confirmed jsonb;
  v_reserved jsonb;
  v_cash integer;
  v_reserve integer;
begin
  select * into v_before from public.referral_program_settings where id = 1;
  if v_before.backed_full_slot_enabled then
    raise exception 'a flag da vaga gratis nao nasceu desligada';
  end if;

  select pix_receipt_fee_cents, card_receipt_fee_cents, card_receipt_fee_bps
    into v_pix, v_card, v_bps
  from public.platform_settings where id = 1;

  update public.platform_settings
  set pix_receipt_fee_cents = 0,
      card_receipt_fee_cents = 0,
      card_receipt_fee_bps = 0
  where id = 1;

  update public.referral_program_settings
  set first_booking_discount_bps = 0,
      redeem_min_points = 1000,
      redeem_max_bps = 3000,
      backed_full_slot_enabled = false
  where id = 1;

  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at
  ) values (
    'player',
    'e7a22222-2222-4222-8222-222222222222',
    'player',
    'e7a55555-5555-4555-8555-555555555555',
    'vaga-reserva',
    pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days'
  );
  if public.points_reserve_split_cents(
    'e7a22222-2222-4222-8222-222222222222',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 10000, 7500, 'PIX'
  ) <> 0 then
    raise exception 'flag desligada separou lastro no split';
  end if;

  select private.point_reserve_cents() into v_reserve;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'e7a11111-1111-4111-8111-111111111111',
    'release', 20000, 20000, 'c2c', 'vaga-c2c-liberado'
  );
  if (
    select funding from public.scape_point_entries
    where idempotency_key = 'vaga-c2c-liberado'
  ) is distinct from 'backed' then
    raise exception 'indicacao nao ficou com lastro';
  end if;
  if private.point_reserve_cents() <> v_reserve + 20000 then
    raise exception 'o saldo reservado nao cresceu com a indicacao %',
      private.point_reserve_cents();
  end if;

  v_quote := private.subsidy_quote(
    'e7a11111-1111-4111-8111-111111111111', 10000, 2500, 20000, false
  );
  if (v_quote ->> 'points')::integer <> 2500
    or (v_quote ->> 'topup_cents')::integer <> 0
    or coalesce((v_quote ->> 'points_only')::boolean, false)
    or (v_quote ->> 'split_percent')::numeric <> 100
  then
    raise exception 'flag desligada nao manteve o teto %', v_quote;
  end if;

  update public.referral_program_settings
  set backed_full_slot_enabled = true
  where id = 1;

  v_quote := private.quote_redemption(
    'e7a11111-1111-4111-8111-111111111111',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 2500, 20000
  );
  if (v_quote ->> 'points')::integer <> 10000
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'topup_cents')::integer <> 7500
    or not (v_quote ->> 'points_only')::boolean
    or v_quote ->> 'split_percent' is not null
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 0
  then
    raise exception 'vaga gratis nao cobriu a sala %', v_quote;
  end if;

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'e7a55555-5555-4555-8555-555555555555',
    'release', 10000, 10000, 'welcome', 'vaga-boas-vindas'
  );
  if (
    select funding from public.scape_point_entries
    where idempotency_key = 'vaga-boas-vindas'
  ) is distinct from 'unbacked' then
    raise exception 'boas-vindas ganharam lastro';
  end if;
  v_quote := private.subsidy_quote(
    'e7a55555-5555-4555-8555-555555555555', 10000, 10000, 10000, false
  );
  if (v_quote ->> 'points')::integer <> 3000
    or (v_quote ->> 'topup_cents')::integer <> 0
  then
    raise exception 'promocao furou o teto de 30%% %', v_quote;
  end if;
  v_quote := private.subsidy_quote(
    'e7a55555-5555-4555-8555-555555555555', 10000, 2500, 10000, false
  );
  if (v_quote ->> 'points')::integer <> 2500
    or (v_quote ->> 'topup_cents')::integer <> 0
  then
    raise exception 'promocao comeu a comissao %', v_quote;
  end if;

  select private.point_reserve_cents() into v_cash;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'e7a22222-2222-4222-8222-222222222222',
    'release', 10000, 10000, 'cashback', 'vaga-cashback'
  );
  if (
    select funding from public.scape_point_entries
    where idempotency_key = 'vaga-cashback'
  ) is distinct from 'backed' then
    raise exception 'cashback ficou sem lastro';
  end if;
  if private.point_reserve_cents() <> v_cash + 10000 then
    raise exception 'lastro do cashback nao entrou na reserva';
  end if;
  v_quote := private.subsidy_quote(
    'e7a22222-2222-4222-8222-222222222222', 10000, 2500, 10000, false
  );
  if (v_quote ->> 'points')::integer <> 10000
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'topup_cents')::integer <> 7500
    or v_quote ->> 'limit_reason' is not null
  then
    raise exception 'cashback nao cobriu a vaga %', v_quote;
  end if;

  v_held := private.hold_point_redemption(
    'e7a11111-1111-4111-8111-111111111111',
    'vaga-hold-cheia',
    10000, 2500, 20000
  );
  v_confirmed := public.confirm_points_booking(
    'e7e11111-1111-4111-8111-111111111111',
    'e7a11111-1111-4111-8111-111111111111',
    'e7b11111-1111-4111-8111-111111111111',
    'vaga-hold-cheia',
    'wallet-vaga',
    2500,
    'PIX'
  );
  if (v_confirmed ->> 'status') <> 'paid'
    or (v_confirmed ->> 'amount_cents')::integer <> 0
    or (v_confirmed ->> 'topup_cents')::integer <> 7500
    or (v_confirmed ->> 'house_fixed_cents')::integer <> 0
  then
    raise exception 'confirmacao sem asaas falhou %', v_confirmed;
  end if;
  if (
    select provider from public.payment_charges
    where id = (v_confirmed ->> 'id')::uuid
  ) is distinct from 'points' then
    raise exception 'vaga gratis virou cobranca asaas';
  end if;
  if (
    select payment_status from public.group_members
    where group_id = 'e7e11111-1111-4111-8111-111111111111'
  ) is distinct from 'paid' then
    raise exception 'a cadeira nao foi confirmada';
  end if;
  if (
    select count(*) from public.free_slot_audits
    where user_id = 'e7a11111-1111-4111-8111-111111111111'
      and decision = 'points_only'
  ) <> 1 then
    raise exception 'auditoria da vaga gratis ausente';
  end if;
  if (
    select amount_cents from public.free_slot_topups
    where payment_charge_id = (v_confirmed ->> 'id')::uuid
  ) <> 7500 then
    raise exception 'credito da casa nao ficou em 75 reais';
  end if;

  v_quote := private.subsidy_quote(
    'e7a11111-1111-4111-8111-111111111111', 10000, 2500, 20000, false
  );
  if (v_quote ->> 'points')::integer <> 10000
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'topup_cents')::integer <> 7500
    or v_quote ->> 'limit_reason' is not null
  then
    raise exception 'segunda vaga do mes foi barrada %', v_quote;
  end if;

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, idempotency_key, commission_bps, wallet_id
  ) values (
    'e7f11111-1111-4111-8111-111111111111',
    'e7e22222-2222-4222-8222-222222222222',
    'e7a22222-2222-4222-8222-222222222222',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 'PIX', 'creating',
    'asaas', 'vaga-repasse-colega', 2500, 'wallet-vaga'
  );
  perform private.apply_share_adjustments('e7f11111-1111-4111-8111-111111111111');
  if private.sync_house_fixed('e7f11111-1111-4111-8111-111111111111') <> 10000 then
    raise exception 'o repasse nao completou o liquido da casa';
  end if;
  if (
    select free_slot_applied_cents from public.payment_charges
    where id = 'e7f11111-1111-4111-8111-111111111111'
  ) <> 2500
    or (
      select amount_cents - applied_cents from public.free_slot_topups
      where payment_charge_id = (v_confirmed ->> 'id')::uuid
    ) <> 5000
  then
    raise exception 'o credito da casa nao abateu so a comissao que cabia';
  end if;

  perform private.apply_payment_transition(
    (v_confirmed ->> 'id')::uuid, 'refunded', true
  );
  if (
    select available_points from private.scape_balances(
      'e7a11111-1111-4111-8111-111111111111'
    )
  ) <> 20000 then
    raise exception 'o estorno nao devolveu os pontos';
  end if;
  if private.point_reserve_cents() <> v_reserve + 30000 then
    raise exception 'desfazer a vaga nao devolveu o saldo reservado %',
      private.point_reserve_cents();
  end if;
  if (
    select amount_cents from public.free_slot_clawbacks
    where venue_id = 'e7b11111-1111-4111-8111-111111111111'
  ) <> 2500 then
    raise exception 'o que ja foi repassado nao virou clawback';
  end if;
  if (
    select amount_cents - applied_cents from public.free_slot_topups
    where payment_charge_id = (v_confirmed ->> 'id')::uuid
  ) <> 0
    or private.free_slots_used_this_month(
      'e7a11111-1111-4111-8111-111111111111'
    ) <> 1
  then
    raise exception 'o resto do credito nao congelou ou o mes foi liberado';
  end if;

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, review_status, idempotency_key
  ) values (
    'e7a44444-4444-4444-8444-444444444444',
    'accrual', 1000, 1000, 'c2c', 'em_revisao', 'vaga-fraude-revisao'
  );
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'e7a44444-4444-4444-8444-444444444444',
    'release', 20000, 20000, 'c2c', 'vaga-fraude-liberado'
  );
  v_quote := private.subsidy_quote(
    'e7a44444-4444-4444-8444-444444444444', 10000, 2500, 20000, false
  );
  if (v_quote ->> 'points')::integer <> 2500
    or v_quote ->> 'limit_reason' is distinct from 'antifraud'
  then
    raise exception 'indicacao em revisao liberou vaga gratis %', v_quote;
  end if;

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'e7a33333-3333-4333-8333-333333333333',
    'release', 20000, 20000, 'c2c', 'vaga-parcial-liberado'
  );
  select private.point_reserve_cents() into v_cash;
  if v_cash > 7000 then
    insert into public.ledger_entries (
      user_id, account, direction, kind, amount_cents, component_key
    ) values (
      'e7a33333-3333-4333-8333-333333333333',
      'platform_reserve', 'debit', 'point_reserve',
      v_cash - 7000, 'teste-reserva-aperta'
    );
  end if;
  v_quote := private.subsidy_quote(
    'e7a33333-3333-4333-8333-333333333333', 10000, 2500, 20000, false
  );
  if (v_quote ->> 'points')::integer <> 7000
    or (v_quote ->> 'charged_cents')::integer <> 3000
    or (v_quote ->> 'topup_cents')::integer <> 4500
    or v_quote ->> 'limit_reason' is distinct from 'reserve'
  then
    raise exception 'o saldo reservado ficou negativo ou nao travou a vaga % saldo %',
      v_quote, private.point_reserve_cents();
  end if;

  perform private.hold_point_redemption(
    'e7a33333-3333-4333-8333-333333333333',
    'vaga-hold-parcial',
    10000, 2500, 20000
  );
  v_reserved := private.reserve_with_subsidy(
    'e7e33333-3333-4333-8333-333333333333',
    'e7a33333-3333-4333-8333-333333333333',
    'e7b11111-1111-4111-8111-111111111111',
    3000,
    'vaga-hold-parcial',
    'wallet-vaga',
    2500,
    'PIX',
    10000,
    7000,
    7000,
    null
  );
  if (v_reserved ->> 'house_fixed_cents')::integer <> 3000
    or (v_reserved ->> 'amount_cents')::integer <> 3000
  then
    raise exception 'o pix parcial nao guardou o liquido %', v_reserved;
  end if;
  if (
    select amount_cents from public.free_slot_topups
    where user_id = 'e7a33333-3333-4333-8333-333333333333'
      and voided_at is null
  ) <> 4500 then
    raise exception 'o complemento parcial nao ficou em 45 reais';
  end if;
  if private.point_reserve_cents() < 0 then
    raise exception 'o saldo reservado ficou negativo';
  end if;

  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'cancelled', false
  );
  if (
    select available_points from private.scape_balances(
      'e7a33333-3333-4333-8333-333333333333'
    )
  ) <> 20000 then
    raise exception 'cancelar o pix nao devolveu os pontos';
  end if;
  if (
    select voided_at from public.free_slot_topups
    where user_id = 'e7a33333-3333-4333-8333-333333333333'
  ) is null then
    raise exception 'o credito nao pago continuou em aberto';
  end if;

  if public.points_reserve_split_cents(
    'e7a33333-3333-4333-8333-333333333333',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 10000, 7500, 'PIX'
  ) <> public.cashback_reserve_split_cents(10000) then
    raise exception 'o split sem indicacao nao reservou o teto do cashback';
  end if;
  if public.cashback_reserve_split_cents(10000) <> private.reward_cents(10000, (
    select cashback_max_bps from public.referral_program_settings where id = 1
  )) then
    raise exception 'o teto do cashback no split nao e o maximo configurado';
  end if;
  if public.points_reserve_split_cents(
    'e7a22222-2222-4222-8222-222222222222',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 10000, 7500, 'PIX'
  ) <> private.reward_cents(10000, (
    select c2c_bps + private.referrer_tier_bonus(
      'e7a55555-5555-4555-8555-555555555555'
    )
    from public.referral_program_settings
    where id = 1
  )) + public.cashback_reserve_split_cents(10000) then
    raise exception 'o split da reserva nao somou indicacao e cashback';
  end if;
  if public.points_reserve_split_cents(
    'e7a22222-2222-4222-8222-222222222222',
    'e7b11111-1111-4111-8111-111111111111',
    10000, 10000, 9900, 'PIX'
  ) <> 0 then
    raise exception 'o lastro passou do liquido';
  end if;
  if public.claim_points_reserve_transfer(
    'e7f11111-1111-4111-8111-111111111111', 'house', 7500, 'wallet-casa'
  ) is distinct from 'send' then
    raise exception 'a transferencia da reserva nao foi reservada';
  end if;
  perform public.complete_points_reserve_transfer(
    'e7f11111-1111-4111-8111-111111111111', 'house', 'tr_sandbox', true
  );
  if public.claim_points_reserve_transfer(
    'e7f11111-1111-4111-8111-111111111111', 'house', 7500, 'wallet-casa'
  ) is distinct from 'done' then
    raise exception 'a transferencia da reserva repetiu';
  end if;

  update public.platform_settings
  set pix_receipt_fee_cents = v_pix,
      card_receipt_fee_cents = v_card,
      card_receipt_fee_bps = v_bps
  where id = 1;
  update public.referral_program_settings
  set first_booking_discount_bps = v_before.first_booking_discount_bps,
      redeem_min_points = v_before.redeem_min_points,
      redeem_max_bps = v_before.redeem_max_bps,
      backed_full_slot_enabled = v_before.backed_full_slot_enabled
  where id = 1;
end $$;
