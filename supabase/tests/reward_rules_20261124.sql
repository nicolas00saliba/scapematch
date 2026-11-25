-- Regras de 24/11/2026. O bloco desfaz no final.
-- Indicado ativo continua o critério já gravado: atribuição active e
-- cobrança paga do sujeito dentro de tier_active_days.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_settings public.referral_program_settings%rowtype;
  v_referrer uuid := 'c2410000-0000-4000-8000-000000000001';
  v_i integer;
  v_subject uuid;
  v_charge uuid;
  v_group uuid;
  v_rate integer;
  v_points integer;
  v_cash integer;
  v_quote jsonb;
  v_reserved jsonb;
  v_player uuid := 'c2410000-0000-4000-8000-0000000000aa';
  v_denied text;
begin
  update public.referral_program_settings
  set c2b_bps = 500,
      b2c_bps = 500,
      b2b_bps = 500,
      point_value_cents = 1,
      redeem_min_points = 0,
      redeem_max_bps = 10000,
      backed_full_slot_enabled = false,
      first_booking_discount_bps = 2000,
      c2c_from_bps = 100,
      c2c_mid_active = 5,
      c2c_mid_bps = 250,
      c2c_high_active = 8,
      c2c_high_bps = 500
  where id = 1;
  select * into v_settings from public.referral_program_settings where id = 1;
  if v_settings.c2b_bps <> 500
    or v_settings.b2c_bps <> 500
    or v_settings.b2b_bps <> 500
    or v_settings.point_value_cents <> 1
    or v_settings.redeem_min_points <> 0
    or v_settings.redeem_max_bps <> 10000
    or v_settings.backed_full_slot_enabled is true
    or v_settings.first_booking_discount_bps <> 2000
    or v_settings.c2c_from_bps <> 100
    or v_settings.c2c_mid_active <> 5
    or v_settings.c2c_mid_bps <> 250
    or v_settings.c2c_high_active <> 8
    or v_settings.c2c_high_bps <> 500
  then
    raise exception 'a tabela nao gravou as regras de 24/11 %', v_settings;
  end if;

  if private.referrer_c2c_bps(null) <> 0
    or private.referrer_tier_name(null) <> 'nenhum'
  then
    raise exception 'sem indicador a taxa nao ficou zerada';
  end if;

  begin
    execute 'set local role authenticated';
    perform private.referrer_c2c_bps(null);
    v_denied := 'executou';
  exception
    when insufficient_privilege then
      v_denied := 'bloqueado';
  end;
  execute 'reset role';
  if v_denied is distinct from 'bloqueado' then
    raise exception 'authenticated leu a taxa da indicacao';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    v_referrer,
    'regras-indicador@example.com',
    '{"display_name":"Indicador"}'
  );
  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'c2410000-0000-4000-8000-0000000000bb',
    'regras-casa@example.com',
    '{"display_name":"Dono"}'
  );
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    'c2420000-0000-4000-8000-000000000001',
    'c2410000-0000-4000-8000-0000000000bb',
    'curitiba', 'Casa Regras', 'Centro', 'Rua das Regras', '24',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000190',
    '4130002424', 'approved'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    'c2430000-0000-4000-8000-000000000001',
    'c2420000-0000-4000-8000-000000000001',
    'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (
    'c2431000-0000-4000-8000-000000000001',
    'c2430000-0000-4000-8000-000000000001',
    '2027-11-24 18:00:00+00', 'partner_grid'
  );

  if private.referrer_c2c_bps(v_referrer) <> 0
    or private.referrer_tier_bonus(v_referrer) <> 0
  then
    raise exception 'zero indicados ativos ainda pagam';
  end if;

  for v_i in 1..8 loop
    v_subject := (
      'c244' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    v_charge := (
      'c245' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    v_group := (
      'c246' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001'
    )::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (
      v_subject,
      'regras-indicado-' || v_i::text || '@example.com',
      '{"display_name":"Indicado"}'
    );
    insert into public.referral_attributions (
      subject_kind, subject_user_id, referrer_kind, referrer_user_id,
      code, starts_at, ends_at, status
    ) values (
      'player', v_subject, 'player', v_referrer,
      'regras24', pg_catalog.now() - interval '1 day',
      pg_catalog.now() + interval '300 days', 'active'
    );
    insert into public.groups (
      id, city_id, venue_id, room_id, session_id, starts_at,
      total_spots, minimum_spots, price_cents, created_by
    ) values (
      v_group, 'curitiba',
      'c2420000-0000-4000-8000-000000000001',
      'c2430000-0000-4000-8000-000000000001',
      'c2431000-0000-4000-8000-000000000001',
      timestamptz '2027-11-24 18:00:00+00' + make_interval(days => v_i),
      4, 2, 10000, v_referrer
    );
    insert into public.payment_charges (
      id, group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, wallet_id, commission_bps, paid_at
    ) values (
      v_charge, v_group, v_subject,
      'c2420000-0000-4000-8000-000000000001',
      10000, 'PIX', 'paid',
      'idem-regras-' || v_i::text, 'wal', 2500, pg_catalog.now()
    );
    v_rate := private.referrer_c2c_bps(v_referrer);
    if v_i < 5 and v_rate <> 100 then
      raise exception 'o primeiro nivel nao ficou em 1%% no indicado % taxa %', v_i, v_rate;
    end if;
    if v_i >= 5 and v_i < 8 and v_rate <> 250 then
      raise exception 'o segundo nivel nao ficou em 2,5%% no indicado % taxa %', v_i, v_rate;
    end if;
    if v_i >= 8 and v_rate <> 500 then
      raise exception 'o terceiro nivel nao ficou em 5%% no indicado % taxa %', v_i, v_rate;
    end if;
  end loop;

  if private.referrer_tier_name(v_referrer) <> 'nivel_5'
    or private.referrer_tier_bonus(v_referrer) <> 50
  then
    raise exception 'oito ativos misturou a taxa nova com o bonus antigo';
  end if;

  update public.profiles
  set cpf = '39053344705'
  where id = v_referrer;
  update public.profiles
  set cpf = '15350946056'
  where id = 'c2440008-0000-4000-8000-000000000001';
  update public.referral_program_settings
  set cashback_distribution = '[{"bps":100,"weight":1}]'::jsonb
  where id = 1;
  insert into public.venue_empty_slots (
    venue_id, weekday, starts_minute, ends_minute, active
  )
  select
    'c2420000-0000-4000-8000-000000000001',
    extract(isodow from pg_catalog.now() at time zone 'America/Sao_Paulo')::integer,
    0, 1440, true;
  v_cash := private.post_player_cashback(
    'c2450001-0000-4000-8000-000000000001', 2500
  );
  if v_cash <> 100
    or exists (
      select 1 from public.venue_cashback_debits
      where source_charge_id = 'c2450001-0000-4000-8000-000000000001'
    )
    or exists (
      select 1 from public.cashback_draws
      where payment_charge_id = 'c2450001-0000-4000-8000-000000000001'
        and doubled
    )
  then
    raise exception 'horario vazio ainda dobrou o cashback %', v_cash;
  end if;

  perform private.post_referral_rewards('c2450008-0000-4000-8000-000000000001');
  select points into v_points
  from public.scape_point_entries
  where source_charge_id = 'c2450008-0000-4000-8000-000000000001'
    and program = 'c2c' and kind = 'accrual';
  if v_points is distinct from 500 then
    raise exception 'oito ativos nao pagaram 5%% %', v_points;
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (v_player, 'regras-jogador@example.com', '{"display_name":"Jogador"}');
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    v_player, 'release', 1, 1, 'welcome', 'regras-um-ponto'
  );
  v_quote := private.subsidy_quote(v_player, 10000, 2500, 1, false);
  if (v_quote ->> 'points')::integer <> 1
    or (v_quote ->> 'subsidy_cents')::integer <> 1
  then
    raise exception 'um ponto ainda nao resgata %', v_quote;
  end if;

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    v_player, 'release', 10000, 10000, 'c2c', 'regras-lastro'
  );
  update public.referral_program_settings
  set backed_full_slot_enabled = true
  where id = 1;
  v_quote := private.subsidy_quote(v_player, 10000, 2500, 10000, false);
  if (v_quote ->> 'points')::integer <> 10000
    or (v_quote ->> 'charged_cents')::integer <> 0
    or (v_quote ->> 'points_only')::boolean is not true
    or (v_quote ->> 'topup_cents')::integer <> 7500
    or (v_quote ->> 'house_net_cents')::integer <> 7500
  then
    raise exception 'a vaga inteira em pontos com lastro nao fechou %', v_quote;
  end if;
  update public.referral_program_settings
  set backed_full_slot_enabled = false
  where id = 1;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'c2410000-0000-4000-8000-0000000000cc',
    'regras-primeira@example.com',
    '{"display_name":"Primeira"}'
  );
  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at, status
  ) values (
    'player', 'c2410000-0000-4000-8000-0000000000cc', 'player', v_referrer,
    'regras24', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days', 'active'
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'c2470000-0000-4000-8000-000000000001', 'curitiba',
    'c2420000-0000-4000-8000-000000000001',
    'c2430000-0000-4000-8000-000000000001',
    'c2431000-0000-4000-8000-000000000001',
    '2027-12-24 18:00:00+00', 4, 2, 10000, v_referrer
  );
  if private.first_booking_discount_for(
    'c2410000-0000-4000-8000-0000000000cc',
    'c2420000-0000-4000-8000-000000000001',
    10000, 1000, 0, null
  ) <> 2000 then
    raise exception 'comissao de 10%% encolheu o desconto de 20%%';
  end if;
  v_reserved := private.reserve_pix_charge(
    'c2470000-0000-4000-8000-000000000001',
    'c2410000-0000-4000-8000-0000000000cc',
    'c2420000-0000-4000-8000-000000000001',
    10000,
    'idem-regras-desconto',
    'wal',
    1000
  );
  if (v_reserved ->> 'amount_cents')::integer <> 8000
    or (
      select first_booking_discount_cents
      from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 2000
    or (
      select free_slot_topup_cents
      from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 1000
    or exists (
      select 1
      from public.free_slot_topups
      where payment_charge_id = (v_reserved ->> 'id')::uuid
        and voided_at is null
    )
  then
    raise exception 'o desconto lançou complemento antes do pagamento %', v_reserved;
  end if;

  insert into public.group_members (group_id, user_id, display_name)
  values (
    'c2470000-0000-4000-8000-000000000001',
    'c2410000-0000-4000-8000-0000000000cc',
    'Primeira'
  );
  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'cancelled', false
  );
  if exists (
    select 1 from public.free_slot_topups
    where venue_id = 'c2420000-0000-4000-8000-000000000001'
      and voided_at is null
      and applied_cents < amount_cents
  ) then
    raise exception 'cancelar a reserva deixou complemento aberto';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'c2470000-0000-4000-8000-000000000002', 'curitiba',
    'c2420000-0000-4000-8000-000000000001',
    'c2430000-0000-4000-8000-000000000001',
    'c2431000-0000-4000-8000-000000000001',
    '2027-12-25 18:00:00+00', 4, 2, 10000, v_referrer
  );
  insert into public.group_members (group_id, user_id, display_name)
  values (
    'c2470000-0000-4000-8000-000000000002',
    'c2410000-0000-4000-8000-0000000000cc',
    'Primeira'
  );
  v_reserved := private.reserve_pix_charge(
    'c2470000-0000-4000-8000-000000000002',
    'c2410000-0000-4000-8000-0000000000cc',
    'c2420000-0000-4000-8000-000000000001',
    10000,
    'idem-regras-desconto-2',
    'wal',
    1000
  );
  update public.payment_charges
  set reserved_at = pg_catalog.now() - interval '5 minutes'
  where id = (v_reserved ->> 'id')::uuid;
  if not private.release_expired_pix_reservation(
    (v_reserved ->> 'id')::uuid,
    (
      select attempt_id from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    )
  ) then
    raise exception 'o pix expirado nao soltou a reserva';
  end if;
  v_reserved := private.reserve_pix_charge(
    'c2470000-0000-4000-8000-000000000002',
    'c2410000-0000-4000-8000-0000000000cc',
    'c2420000-0000-4000-8000-000000000001',
    10000,
    'idem-regras-desconto-3',
    'wal',
    1000
  );
  update public.payment_charges
  set reserved_at = pg_catalog.now() - interval '5 minutes'
  where id = (v_reserved ->> 'id')::uuid;
  if not private.release_expired_pix_reservation(
    (v_reserved ->> 'id')::uuid,
    (
      select attempt_id from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    )
  ) then
    raise exception 'o segundo pix expirado nao soltou a reserva';
  end if;
  if private.open_free_slot_cents() <> 0
    or exists (
      select 1 from public.free_slot_topups
      where venue_id = 'c2420000-0000-4000-8000-000000000001'
        and voided_at is null
        and applied_cents < amount_cents
    )
  then
    raise exception 'abandono repetido deixou complemento aberto';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'c2470000-0000-4000-8000-000000000003', 'curitiba',
    'c2420000-0000-4000-8000-000000000001',
    'c2430000-0000-4000-8000-000000000001',
    'c2431000-0000-4000-8000-000000000001',
    '2027-12-26 18:00:00+00', 4, 2, 10000, v_referrer
  );
  insert into public.group_members (
    id, group_id, user_id, display_name, payment_status
  ) values (
    'c2480000-0000-4000-8000-000000000003',
    'c2470000-0000-4000-8000-000000000003',
    'c2410000-0000-4000-8000-0000000000cc',
    'Primeira',
    'paid'
  );
  v_reserved := private.reserve_pix_charge(
    'c2470000-0000-4000-8000-000000000003',
    'c2410000-0000-4000-8000-0000000000cc',
    'c2420000-0000-4000-8000-000000000001',
    10000,
    'idem-regras-desconto-pago',
    'wal',
    1000
  );
  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'paid', true
  );
  if exists (
    select 1 from public.free_slot_topups
    where payment_charge_id = (v_reserved ->> 'id')::uuid
      and voided_at is null
  ) then
    raise exception 'o pagamento ainda lançou complemento na casa';
  end if;
  if (
    select status || ':' || amount_cents::text || ':' || assumed_cents::text
    from public.platform_cac_transfers
    where payment_charge_id = (v_reserved ->> 'id')::uuid
  ) is distinct from 'pending:1000:1080' then
    raise exception 'o pagamento nao lançou o CAC da plataforma';
  end if;
  update public.payment_charges
  set provider_ref = 'pagbank-regras-estorno'
  where id = (v_reserved ->> 'id')::uuid;
  if not private.enqueue_member_refund(
    'c2470000-0000-4000-8000-000000000003',
    'c2410000-0000-4000-8000-0000000000cc',
    'c2480000-0000-4000-8000-000000000003'
  ) then
    raise exception 'o estorno individual nao entrou na fila';
  end if;
  if (
    select status
    from public.platform_cac_transfers
    where payment_charge_id = (v_reserved ->> 'id')::uuid
  ) is distinct from 'pending' then
    raise exception 'a fila do estorno cancelou o CAC antes da PagBank';
  end if;
  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'refunded', false
  );
  if exists (
    select 1 from public.free_slot_topups
    where payment_charge_id = (v_reserved ->> 'id')::uuid
      and voided_at is null
      and applied_cents < amount_cents
  ) or private.open_free_slot_cents() <> 0 then
    raise exception 'o estorno individual deixou o complemento aberto';
  end if;
  if (
    select status || ':' || coalesce(last_error, '')
    from public.platform_cac_transfers
    where payment_charge_id = (v_reserved ->> 'id')::uuid
  ) is distinct from 'failed:estorno' then
    raise exception 'o estorno nao cancelou o CAC pendente';
  end if;
end $$;

rollback;
