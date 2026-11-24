-- Desconto da primeira sessão: 20% com código, 10% sem código.
-- O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_owner uuid := 'c2710000-0000-4000-8000-0000000000b1';
  v_organic uuid := 'c2710000-0000-4000-8000-0000000000c1';
  v_referred uuid := 'c2710000-0000-4000-8000-0000000000c2';
  v_snap uuid := 'c2710000-0000-4000-8000-0000000000c3';
  v_admin uuid := 'c2710000-0000-4000-8000-0000000000a1';
  v_referrer uuid := 'c2710000-0000-4000-8000-0000000000d1';
  v_venue uuid := 'c2720000-0000-4000-8000-000000000001';
  v_room uuid := 'c2730000-0000-4000-8000-000000000001';
  v_session uuid := 'c2731000-0000-4000-8000-000000000001';
  v_group_org uuid := 'c2750000-0000-4000-8000-000000000001';
  v_group_ref uuid := 'c2750000-0000-4000-8000-000000000002';
  v_settings public.referral_program_settings%rowtype;
  v_default text;
  v_public jsonb;
  v_quote jsonb;
  v_reserved jsonb;
  v_charge uuid;
  v_discount integer;
  v_assumed integer;
  v_amount integer;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attrdef d
  join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
  where a.attrelid = 'public.referral_program_settings'::regclass
    and a.attname = 'organic_first_booking_discount_bps';
  if v_default is distinct from '1000' then
    raise exception 'o padrao sem codigo nao e 1000: %', v_default;
  end if;
  update public.referral_program_settings
  set first_booking_discount_bps = 2000,
      organic_first_booking_discount_bps = 1000
  where id = 1;
  select * into v_settings from public.referral_program_settings where id = 1;
  if v_settings.first_booking_discount_bps <> 2000
    or v_settings.organic_first_booking_discount_bps <> 1000
  then
    raise exception 'o padrao nao e 20%% com codigo e 10%% sem %', v_settings;
  end if;

  insert into auth.users (id, email, raw_user_meta_data) values
    (v_owner, 'sessao-dono@example.com', '{"display_name":"Dono"}'),
    (v_organic, 'sessao-sozinho@example.com', '{"display_name":"Sozinho"}'),
    (v_referred, 'sessao-codigo@example.com', '{"display_name":"Codigo"}'),
    (v_snap, 'sessao-foto@example.com', '{"display_name":"Foto"}'),
    (v_admin, 'sessao-admin@example.com', '{"display_name":"Admin"}'),
    (v_referrer, 'sessao-indicador@example.com', '{"display_name":"Indicador"}');
  insert into public.admins (user_id) values (v_admin);
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status, pagbank_account_id
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa Sessao', 'Centro', 'Rua da Sessao', '1',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000911',
    '4130002711', 'approved',
    'ACCO_11111111-1111-4111-8111-111111111111'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    v_room, v_venue, 'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (v_session, v_room, '2027-12-01 18:00:00+00', 'partner_grid');

  if private.first_booking_discount_for(
    v_organic, v_venue, 10000, 2500, 0, null
  ) <> 1000 then
    raise exception 'sem codigo a primeira sessao nao ficou em 10%%';
  end if;

  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at, status
  ) values (
    'player', v_referred, 'player', v_referrer,
    'SESSAO01', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days', 'active'
  );
  if private.first_booking_discount_for(
    v_referred, v_venue, 10000, 1000, 0, null
  ) <> 2000 then
    raise exception 'com codigo a primeira sessao nao ficou em 20%%';
  end if;

  update public.profiles
  set signup_referred = true
  where id = v_snap;
  insert into public.referral_attributions (
    subject_kind, subject_user_id, referrer_kind, referrer_user_id,
    code, starts_at, ends_at, status, block_reason
  ) values (
    'player', v_snap, 'player', v_referrer,
    'SESSAO02', pg_catalog.now() - interval '1 day',
    pg_catalog.now() + interval '300 days', 'blocked', 'shared_cpf'
  );
  if private.first_booking_discount_for(
    v_snap, v_venue, 10000, 2500, 0, null
  ) <> 2000 then
    raise exception 'o snapshot do cadastro perdeu os 20%%';
  end if;

  perform set_config('request.jwt.claim.sub', v_organic::text, true);
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group_org, 'curitiba', v_venue, v_room, v_session,
    '2027-12-01 18:00:00+00', 4, 2, 10000, v_owner
  );
  v_quote := public.quote_my_point_subsidy(v_group_org, 0);
  if (v_quote ->> 'first_booking_discount_cents')::integer <> 1000 then
    raise exception 'a cotacao sem codigo nao devolveu 10%% %', v_quote;
  end if;

  v_reserved := private.reserve_pix_charge(
    v_group_org, v_organic, v_venue, 10000,
    'idem-sessao-organica', 'wal', 500
  );
  v_charge := (v_reserved ->> 'id')::uuid;
  select first_booking_discount_cents into v_discount
  from public.payment_charges where id = v_charge;
  if v_discount <> 1000 or (v_reserved ->> 'amount_cents')::integer <> 9000 then
    raise exception 'create-charge sem codigo nao aplicou 10%% %', v_reserved;
  end if;
  insert into public.group_members (group_id, user_id, display_name)
  values (v_group_org, v_organic, 'Sozinho');
  perform private.apply_payment_transition(v_charge, 'paid', false);
  select amount_cents, assumed_cents into v_amount, v_assumed
  from public.platform_cac_transfers
  where payment_charge_id = v_charge;
  if v_assumed is distinct from 500 then
    raise exception 'o cac nao usou os 10%% % %', v_amount, v_assumed;
  end if;

  if private.first_booking_discount_for(
    v_organic, v_venue, 10000, 2500, 0, null
  ) <> 0 then
    raise exception 'a segunda sessao ainda teve desconto';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    v_group_ref, 'curitiba', v_venue, v_room, v_session,
    '2027-12-02 18:00:00+00', 4, 2, 10000, v_owner
  );
  perform set_config('request.jwt.claim.sub', v_referred::text, true);
  v_quote := public.quote_my_point_subsidy(v_group_ref, 0);
  if (v_quote ->> 'first_booking_discount_cents')::integer <> 2000 then
    raise exception 'a cotacao com codigo nao devolveu 20%% %', v_quote;
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  perform public.admin_save_reward_settings(
    '{"organic_first_booking_discount_bps":1500}'::jsonb
  );
  execute 'set local role anon';
  v_public := public.reward_rules_public();
  execute 'reset role';
  if (v_public ->> 'organic_first_booking_discount_bps')::integer <> 1500
    or (v_public ->> 'first_booking_discount_bps')::integer <> 2000
    or v_public ? 'signup_referred'
  then
    raise exception 'a rpc nao devolveu os dois descontos %', v_public;
  end if;
end $$;

rollback;
