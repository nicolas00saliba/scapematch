-- CAC da plataforma. Não chama o PagBank.
-- O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_owner uuid := 'c2510000-0000-4000-8000-0000000000b1';
  v_player uuid := 'c2510000-0000-4000-8000-0000000000c1';
  v_admin uuid := 'c2510000-0000-4000-8000-0000000000a1';
  v_venue uuid := 'c2520000-0000-4000-8000-000000000001';
  v_room uuid := 'c2530000-0000-4000-8000-000000000001';
  v_session uuid := 'c2531000-0000-4000-8000-000000000001';
  v_gap uuid := 'c2540000-0000-4000-8000-000000000001';
  v_referral uuid := 'c2540000-0000-4000-8000-000000000002';
  v_waiting uuid := 'c2540000-0000-4000-8000-000000000003';
  v_group_gap uuid := 'c2550000-0000-4000-8000-000000000001';
  v_group_ref uuid := 'c2550000-0000-4000-8000-000000000002';
  v_group_wait uuid := 'c2550000-0000-4000-8000-000000000003';
  v_claim record;
  v_count integer;
  v_report jsonb;
  v_day date;
  v_denied text;
begin
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_owner, 'cac-dono@example.com', '{"display_name":"Dono"}'),
    (v_player, 'cac-jogador@example.com', '{"display_name":"Jogador"}'),
    (v_admin, 'cac-admin@example.com', '{"display_name":"Admin"}');
  insert into public.admins (user_id) values (v_admin);
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status, pagbank_account_id
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa CAC', 'Centro', 'Rua do CAC', '1',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000206',
    '4130002501', 'approved', 'ACCO_CASA_CAC'
  );
  insert into public.rooms (
    id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    v_room, v_venue, 'Sala', '', 4, 2, 60, 'medium', 10000
  );
  insert into public.room_sessions (id, room_id, starts_at, availability)
  values (v_session, v_room, '2027-12-01 18:00:00+00', 'partner_grid');

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    (v_group_gap, 'curitiba', v_venue, v_room, v_session, '2027-12-01 18:00:00+00', 4, 2, 10000, v_player),
    (v_group_ref, 'curitiba', v_venue, v_room, v_session, '2027-12-02 18:00:00+00', 4, 2, 10000, v_player),
    (v_group_wait, 'curitiba', v_venue, v_room, v_session, '2027-12-03 18:00:00+00', 4, 2, 10000, v_player);

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    subsidy_cents, first_booking_discount_cents, free_slot_topup_cents,
    house_fixed_cents, billing_type, status, idempotency_key, wallet_id,
    commission_bps, paid_at, custody_released_at
  ) values (
    v_gap, v_group_gap, v_player, v_venue, 8000, 10000,
    0, 2000, 1000, 8000, 'PIX', 'paid', 'idem-cac-gap', 'wal',
    1000, pg_catalog.now(), pg_catalog.now()
  );

  perform private.book_platform_cac(v_gap);
  perform private.book_platform_cac(v_gap);
  select count(*) into v_count
  from public.platform_cac_transfers
  where payment_charge_id = v_gap;
  if v_count <> 1 then
    raise exception 'o CAC da mesma reserva saiu duplicado %', v_count;
  end if;
  if (
    select status || ':' || amount_cents::text || ':' || assumed_cents::text
    from public.platform_cac_transfers
    where payment_charge_id = v_gap
  ) is distinct from 'pending:1000:1000' then
    raise exception 'o desconto acima da comissao nao gerou o complemento';
  end if;

  select * into v_claim from public.claim_platform_cac(10);
  if v_claim.payment_charge_id is distinct from v_gap
    or v_claim.amount_cents <> 1000
    or v_claim.account_id is distinct from 'ACCO_CASA_CAC'
    or v_claim.attempts <> 1
  then
    raise exception 'a custodia liberada nao entregou o CAC %', v_claim;
  end if;
  perform public.complete_platform_cac(v_claim.id, 'paid', 'TRAN_CAC', null);
  if (
    select status || ':' || coalesce(provider_ref, '')
    from public.platform_cac_transfers
    where id = v_claim.id
  ) is distinct from 'paid:TRAN_CAC' then
    raise exception 'o complete nao marcou o CAC como pago';
  end if;
  if exists (select 1 from public.claim_platform_cac(10)) then
    raise exception 'o CAC pago voltou para a fila';
  end if;

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    subsidy_cents, first_booking_discount_cents, free_slot_topup_cents,
    house_fixed_cents, billing_type, status, idempotency_key, wallet_id,
    commission_bps, paid_at, custody_released_at
  ) values (
    v_referral, v_group_ref, v_player, v_venue, 10000, 10000,
    0, 0, 0, 7500, 'PIX', 'paid', 'idem-cac-referral', 'wal',
    2500, pg_catalog.now(), pg_catalog.now()
  );
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, source_charge_id,
    idempotency_key
  ) values (
    v_player, 'accrual', 3000, 3000, 'c2c', v_referral, 'idem-cac-c2c'
  );
  perform private.book_platform_cac(v_referral);
  if (
    select status || ':' || amount_cents::text || ':' || assumed_cents::text
    from public.platform_cac_transfers
    where payment_charge_id = v_referral
  ) is distinct from 'paid:0:500' then
    raise exception 'a indicacao acima da comissao nao entrou no CAC sem transferencia';
  end if;

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, gross_amount_cents,
    subsidy_cents, first_booking_discount_cents, free_slot_topup_cents,
    house_fixed_cents, billing_type, status, idempotency_key, wallet_id,
    commission_bps, paid_at
  ) values (
    v_waiting, v_group_wait, v_player, v_venue, 8000, 10000,
    0, 2000, 1000, 8000, 'PIX', 'paid', 'idem-cac-wait', 'wal',
    1000, pg_catalog.now()
  );
  perform private.book_platform_cac(v_waiting);
  if exists (
    select 1 from public.claim_platform_cac(10) c
    where c.payment_charge_id = v_waiting
  ) then
    raise exception 'o CAC saiu antes da custodia';
  end if;

  perform private.void_platform_cac(v_waiting);
  if (
    select status || ':' || coalesce(last_error, '') || ':' || attempts::text
    from public.platform_cac_transfers
    where payment_charge_id = v_waiting
  ) is distinct from 'failed:estorno:8' then
    raise exception 'o estorno nao tirou o CAC da fila';
  end if;

  begin
    execute 'set local role authenticated';
    perform public.claim_platform_cac(1);
    v_denied := 'executou';
  exception
    when insufficient_privilege then
      v_denied := 'bloqueado';
  end;
  execute 'reset role';
  if v_denied is distinct from 'bloqueado' then
    raise exception 'authenticated executou a fila do CAC';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  v_day := (pg_catalog.now() at time zone 'America/Sao_Paulo')::date;
  v_report := public.admin_platform_cac_report(v_day, v_day);
  if (
    select coalesce(sum(assumed_cents), 0)
    from public.platform_cac_transfers
    where venue_id = v_venue
  ) <> 2500
    or (
      select coalesce(sum(amount_cents) filter (where status = 'paid'), 0)
      from public.platform_cac_transfers
      where venue_id = v_venue
    ) <> 1000
    or (
      select coalesce(sum(amount_cents) filter (where status = 'failed'), 0)
      from public.platform_cac_transfers
      where venue_id = v_venue
    ) <> 1000
  then
    raise exception 'o CAC da casa nao fechou';
  end if;
  if (v_report ->> 'assumed_cents')::integer
    < (
      select coalesce(sum(assumed_cents), 0)::integer
      from public.platform_cac_transfers
      where venue_id = v_venue
    )
  then
    raise exception 'o relatorio do CAC nao fechou o periodo %', v_report;
  end if;
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_report -> 'alerts') alert
    where alert ->> 'payment_charge_id' = v_waiting::text
      and alert ->> 'last_error' = 'estorno'
  ) then
    raise exception 'o relatorio nao mostrou o CAC que falhou %', v_report;
  end if;
end $$;

rollback;
