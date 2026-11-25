-- O perfil do jogador no Admin mostra a mesma taxa que a conta usa.
-- Com 4, 5, 7 e 8 indicados ativos: 1%, 2,5%, 2,5% e 5%.
-- O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_admin uuid := 'c2f10000-0000-4000-8000-0000000000a1';
  v_owner uuid := 'c2f10000-0000-4000-8000-0000000000b1';
  v_referrer uuid := 'c2f10000-0000-4000-8000-0000000000d1';
  v_venue uuid := 'c2f20000-0000-4000-8000-000000000001';
  v_room uuid := 'c2f30000-0000-4000-8000-000000000001';
  v_session uuid := 'c2f31000-0000-4000-8000-000000000001';
  v_subject uuid;
  v_group uuid;
  v_player jsonb;
  v_expected integer;
  v_i integer;
begin
  update public.referral_program_settings
  set c2c_from_bps = 100,
      c2c_mid_active = 5,
      c2c_mid_bps = 250,
      c2c_high_active = 8,
      c2c_high_bps = 500,
      tier_silver_active = 5,
      tier_silver_bonus_bps = 50,
      tier_gold_active = 15,
      tier_gold_bonus_bps = 100
  where id = 1;

  insert into auth.users (id, email, raw_user_meta_data) values
    (v_admin, 'nivel-admin@example.com', '{"display_name":"Admin"}'),
    (v_owner, 'nivel-dono@example.com', '{"display_name":"Dono"}'),
    (v_referrer, 'nivel-indicador@example.com', '{"display_name":"Indicador"}');
  insert into public.admins (user_id) values (v_admin);
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status, pagbank_account_id
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa Nivel', 'Centro', 'Rua do Nivel', '8',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000913',
    '4130002713', 'approved',
    'ACCO_31111111-1111-4111-8111-111111111111'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    v_room, v_venue, 'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (v_session, v_room, '2027-11-25 18:00:00+00', 'partner_grid');

  for v_i in 1..8 loop
    v_subject := ('c2f4' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid;
    v_group := ('c2f6' || lpad(v_i::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid;
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_subject, 'nivel-indicado-' || v_i::text || '@example.com', '{"display_name":"Indicado"}');
    insert into public.referral_attributions (
      subject_kind, subject_user_id, referrer_kind, referrer_user_id,
      code, starts_at, ends_at, status
    ) values (
      'player', v_subject, 'player', v_referrer,
      'NIVEL025', pg_catalog.now() - interval '1 day',
      pg_catalog.now() + interval '300 days', 'active'
    );
    insert into public.groups (
      id, city_id, venue_id, room_id, session_id, starts_at,
      total_spots, minimum_spots, price_cents, created_by
    ) values (
      v_group, 'curitiba', v_venue, v_room, v_session,
      timestamptz '2027-11-25 18:00:00+00' + make_interval(days => v_i),
      4, 2, 10000, v_referrer
    );
    insert into public.payment_charges (
      group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, wallet_id, commission_bps, paid_at
    ) values (
      v_group, v_subject, v_venue, 10000, 'PIX', 'paid',
      'idem-nivel-' || v_i::text, 'wal', 2500, pg_catalog.now()
    );

    if v_i in (4, 5, 7, 8) then
      v_expected := case when v_i >= 8 then 500 when v_i >= 5 then 250 else 100 end;
      perform set_config('request.jwt.claim.sub', v_admin::text, true);
      perform set_config('request.jwt.claim.aal', 'aal2', true);
      v_player := public.admin_player(v_referrer);
      if (v_player ->> 'tier_bonus_bps')::integer is distinct from v_expected
        or (v_player ->> 'tier_bonus_bps')::integer
          is distinct from private.referrer_c2c_bps(v_referrer)
        or (v_player ->> 'active_referrals')::integer <> v_i
      then
        raise exception 'o admin mostrou % com % ativos, esperado %',
          v_player ->> 'tier_bonus_bps', v_i, v_expected;
      end if;
    end if;
  end loop;
end $$;

rollback;
