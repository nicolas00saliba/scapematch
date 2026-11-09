-- Sorteio do cashback: bytes do pgcrypto, uma vez por cobrança, média até 100 bps.
-- Não fala com o Asaas. O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_def text;
  v_ev numeric;
  v_seed text;
  v_seed_again text;
  v_bps integer;
  v_bps_again integer;
  v_points integer;
  v_points_again integer;
  v_platform integer;
  v_again integer;
  v_draws integer;
  v_accruals integer;
  v_n integer;
  v_avg numeric;
  v_min integer;
  v_max integer;
  v_bands integer;
  v_seeds integer;
  i integer;
begin
  perform set_config('request.jwt.claim.sub', '', true);

  update public.referral_program_settings
  set cashback_distribution =
        '[{"bps":50,"weight":700},{"bps":100,"weight":170},{"bps":200,"weight":90},{"bps":500,"weight":40}]'::jsonb,
      cashback_min_bps = 50,
      cashback_max_bps = 500,
      cashback_ev_cap_bps = 100,
      first_booking_discount_bps = 0
  where id = 1;

  v_def := pg_catalog.pg_get_functiondef(
    'private.post_player_cashback(uuid, integer)'::regprocedure
  );
  if pg_catalog.strpos(v_def, 'extensions.gen_random_bytes') = 0
    or pg_catalog.strpos(v_def, 'clock_timestamp') > 0
    or pg_catalog.strpos(v_def, 'digest') > 0
  then
    raise exception 'sorteio ainda nao usa gen_random_bytes';
  end if;

  select coalesce(sum(band.bps::numeric * band.weight) / nullif(sum(band.weight), 0), 0)
    into v_ev
  from private.cashback_distribution() band;
  if v_ev > 100 or v_ev < 50 or exists (
    select 1
    from private.cashback_distribution() band
    where band.bps < 50 or band.bps > 500
  ) then
    raise exception 'faixa ou media configurada saiu do contrato %', v_ev;
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values
    (
      'cd100000-0000-4000-8000-000000000001',
      'sorteio-casa@example.com',
      '{"display_name":"Sorteio Casa"}'
    ),
    (
      'cd100000-0000-4000-8000-000000000002',
      'sorteio-jogador@example.com',
      '{"display_name":"Sorteio Jogador"}'
    );
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status
  ) values (
    'cd200000-0000-4000-8000-000000000001',
    'cd100000-0000-4000-8000-000000000001',
    'curitiba',
    'Casa Sorteio',
    'Centro',
    'Rua do Sorteio',
    '1',
    '80010000',
    -25.43,
    -49.27,
    5000,
    'cnpj',
    '19131243000197',
    '4130000199',
    'approved'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    'cd300000-0000-4000-8000-000000000001',
    'cd200000-0000-4000-8000-000000000001',
    'Sala Sorteio',
    '',
    4, 2, 60, 'medium', 10000
  );

  insert into public.groups (
    id, city_id, venue_id, room_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'cd610000-0000-4000-8000-000000000001',
    'curitiba',
    'cd200000-0000-4000-8000-000000000001',
    'cd300000-0000-4000-8000-000000000001',
    timestamptz '2026-08-15 18:00:00+00',
    4, 2, 10000,
    'cd100000-0000-4000-8000-000000000001'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator
  ) values (
    'cd610000-0000-4000-8000-000000000001',
    'cd100000-0000-4000-8000-000000000002',
    'Sorteio Jogador',
    false
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'cd600000-0000-4000-8000-000000000001',
    'cd610000-0000-4000-8000-000000000001',
    'cd100000-0000-4000-8000-000000000002',
    'cd200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'pending',
    'idem-sorteio-replay', 'wal_house', 1000
  );

  perform private.apply_payment_transition(
    'cd600000-0000-4000-8000-000000000001', 'paid', true
  );
  select draw.seed, draw.drawn_bps, draw.platform_cents
    into v_seed, v_bps, v_platform
  from public.cashback_draws draw
  where draw.payment_charge_id = 'cd600000-0000-4000-8000-000000000001';
  select entry.points into v_points
  from public.scape_point_entries entry
  where entry.source_charge_id = 'cd600000-0000-4000-8000-000000000001'
    and entry.program = 'cashback'
    and entry.kind = 'accrual';
  if v_seed is null or v_seed !~ '^[0-9a-f]{32}$' or v_bps < 50 or v_bps > 500 or v_points <= 0 then
    raise exception 'primeiro pagamento nao gravou o sorteio % % %', v_seed, v_bps, v_points;
  end if;

  perform public.apply_payment_transition(
    'cd600000-0000-4000-8000-000000000001', 'paid', true
  );
  perform private.post_referral_rewards('cd600000-0000-4000-8000-000000000001');
  v_again := private.post_player_cashback(
    'cd600000-0000-4000-8000-000000000001', 0
  );
  select draw.seed, draw.drawn_bps
    into v_seed_again, v_bps_again
  from public.cashback_draws draw
  where draw.payment_charge_id = 'cd600000-0000-4000-8000-000000000001';
  select count(*) into v_draws
  from public.cashback_draws draw
  where draw.payment_charge_id = 'cd600000-0000-4000-8000-000000000001';
  select count(*), max(entry.points)
    into v_accruals, v_points_again
  from public.scape_point_entries entry
  where entry.source_charge_id = 'cd600000-0000-4000-8000-000000000001'
    and entry.program = 'cashback'
    and entry.kind = 'accrual';
  if v_draws <> 1
    or v_accruals <> 1
    or v_seed_again is distinct from v_seed
    or v_bps_again is distinct from v_bps
    or v_points_again is distinct from v_points
    or v_again is distinct from v_platform
  then
    raise exception 'replay do webhook sorteou de novo % % %', v_draws, v_accruals, v_again;
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  )
  select
    ('cd40' || lpad(to_hex(g.i), 4, '0') || '-0000-4000-8000-000000000000')::uuid,
    'curitiba',
    'cd200000-0000-4000-8000-000000000001',
    'cd300000-0000-4000-8000-000000000001',
    timestamptz '2026-06-01 12:00:00+00' + make_interval(mins => g.i),
    4, 2, 10000,
    'cd100000-0000-4000-8000-000000000001'
  from generate_series(1, 400) as g(i);
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  )
  select
    ('cd50' || lpad(to_hex(g.i), 4, '0') || '-0000-4000-8000-000000000000')::uuid,
    ('cd40' || lpad(to_hex(g.i), 4, '0') || '-0000-4000-8000-000000000000')::uuid,
    'cd100000-0000-4000-8000-000000000002',
    'cd200000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid',
    'idem-sorteio-' || g.i,
    'wal_house', 1000,
    timestamptz '2026-06-01 12:00:00+00'
  from generate_series(1, 400) as g(i);

  for i in 1..400 loop
    perform private.post_player_cashback(
      ('cd50' || lpad(to_hex(i), 4, '0') || '-0000-4000-8000-000000000000')::uuid,
      1000
    );
  end loop;

  select count(*), avg(draw.drawn_bps), min(draw.drawn_bps), max(draw.drawn_bps),
         count(distinct draw.drawn_bps), count(distinct draw.seed)
    into v_n, v_avg, v_min, v_max, v_bands, v_seeds
  from public.cashback_draws draw
  where draw.payment_charge_id::text like 'cd50%';
  if v_n <> 400
    or v_seeds <> 400
    or v_bands < 3
    or v_min < 50
    or v_max > 500
    or v_avg > v_ev + 25
    or v_avg < v_ev - 25
    or exists (
      select 1
      from public.cashback_draws draw
      where draw.payment_charge_id::text like 'cd50%'
        and draw.seed !~ '^[0-9a-f]{32}$'
    )
  then
    raise exception 'media do sorteio fora do contrato n % avg % ev % faixa %-% bandas %',
      v_n, v_avg, v_ev, v_min, v_max, v_bands;
  end if;

  raise notice 'media amostral do cashback: % bps (esperada %)', round(v_avg, 1), round(v_ev, 1);
end $$;

rollback;
