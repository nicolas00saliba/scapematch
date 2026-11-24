-- A regra pública segue o que o admin gravou. O pedido já enviado
-- ao PagBank fica com o valor e o split da criação.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_owner uuid := 'c2610000-0000-4000-8000-0000000000b1';
  v_player uuid := 'c2610000-0000-4000-8000-0000000000c1';
  v_new uuid := 'c2610000-0000-4000-8000-0000000000c2';
  v_referrer uuid := 'c2610000-0000-4000-8000-0000000000c3';
  v_admin uuid := 'c2610000-0000-4000-8000-0000000000a1';
  v_venue uuid := 'c2620000-0000-4000-8000-000000000001';
  v_room uuid := 'c2630000-0000-4000-8000-000000000001';
  v_session uuid := 'c2631000-0000-4000-8000-000000000001';
  v_group uuid := 'c2650000-0000-4000-8000-000000000001';
  v_charge uuid := 'c2640000-0000-4000-8000-000000000001';
  v_public jsonb;
  v_before timestamptz;
  v_amount integer;
  v_split numeric;
  v_fixed integer;
  v_discount integer;
  v_ref text;
  v_next integer;
  v_denied text;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_owner, 'regras-dono@example.com', '{"display_name":"Dono"}'),
    (v_player, 'regras-jogador@example.com', '{"display_name":"Jogador"}'),
    (v_new, 'regras-novo@example.com', '{"display_name":"Novo"}'),
    (v_referrer, 'regras-indicador@example.com', '{"display_name":"Indicador"}'),
    (v_admin, 'regras-admin@example.com', '{"display_name":"Admin"}');
  insert into public.admins (user_id) values (v_admin);
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa Regras', 'Centro', 'Rua das Regras', '1',
    '80010020', -25.43, -49.27, 5000, 'cnpj', '61234567000389',
    '4130002611', 'approved'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    v_room, v_venue, 'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (v_session, v_room, '2027-12-10 18:00:00+00', 'partner_grid');
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group, 'curitiba', v_venue, v_room, v_session, '2027-12-10 18:00:00+00',
    4, 2, 10000, v_player
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    subsidy_cents, first_booking_discount_cents, house_fixed_cents,
    split_percent, billing_type, status, idempotency_key, provider_ref,
    commission_bps
  ) values (
    v_charge, v_group, v_player, v_venue, 8000, 10000,
    0, 2000, 7500, 75, 'PIX', 'pending', 'idem-regras-publicas',
    'ORDE_REGRAS_PUBLICAS', 2500
  );

  begin
    execute 'set local role anon';
    perform 1 from public.referral_program_settings;
    v_denied := 'leu';
  exception
    when insufficient_privilege then
      v_denied := 'bloqueado';
  end;
  execute 'reset role';
  if v_denied is distinct from 'bloqueado' then
    raise exception 'anon leu a tabela inteira das regras';
  end if;

  execute 'set local role anon';
  v_public := public.reward_rules_public();
  execute 'reset role';
  v_before := (v_public ->> 'updated_at')::timestamptz;
  if (v_public ->> 'c2b_bps') is null
    or (v_public ->> 'c2c_from_bps') is null
    or (v_public ->> 'cashback_min_bps') is null
    or (v_public ->> 'cashback_max_bps') is null
    or (v_public ->> 'first_booking_discount_bps') is null
    or (v_public ->> 'redeem_max_bps') is null
    or (v_public ->> 'point_value_cents') is null
    or v_public ? 'cashback_distribution'
    or v_public ? 'block_self_payer'
    or v_public ? 'same_device_review_threshold'
    or v_public ? 'payer_referred_account_cap'
    or v_public ? 'backed_full_slot_enabled'
    or v_before is null
  then
    raise exception 'a leitura publica saiu errada %', v_public;
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  perform public.admin_save_reward_settings(
    '{"c2b_bps":400,"first_booking_discount_bps":1000,"c2c_from_bps":150}'::jsonb
  );

  execute 'set local role authenticated';
  v_public := public.reward_rules_public();
  execute 'reset role';
  if (v_public ->> 'c2b_bps')::integer <> 400
    or (v_public ->> 'first_booking_discount_bps')::integer <> 1000
    or (v_public ->> 'c2c_from_bps')::integer <> 150
    or (v_public ->> 'updated_at')::timestamptz <= v_before
  then
    raise exception 'a rpc nao devolveu a regra nova %', v_public;
  end if;

  select amount_cents, split_percent, house_fixed_cents,
         first_booking_discount_cents, provider_ref
    into v_amount, v_split, v_fixed, v_discount, v_ref
  from public.payment_charges
  where id = v_charge;
  if v_amount <> 8000
    or v_split <> 75
    or v_fixed <> 7500
    or v_discount <> 2000
    or v_ref <> 'ORDE_REGRAS_PUBLICAS'
  then
    raise exception 'o pedido ja criado mudou com a regra nova % % % %',
      v_amount, v_split, v_fixed, v_discount;
  end if;

  v_next := private.reward_cents(10000, (v_public ->> 'c2b_bps')::integer);
  if v_next <> 400 then
    raise exception 'a proxima indicacao de casa nao usou 4%% %', v_next;
  end if;

  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at, status
  ) values (
    'player', v_new, 'player', v_referrer,
    'REGRAS01', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days', 'active'
  );
  v_next := private.first_booking_discount_for(
    v_new, v_venue, 10000, 2500, 0, null
  );
  if v_next <> 1000 then
    raise exception 'a proxima reserva nao usou o desconto novo %', v_next;
  end if;
end $$;

rollback;
