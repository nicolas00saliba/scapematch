-- RECEIVED depois de REFUNDED não reabre a cobrança. A reserva do Pix
-- não troca um provider_ref que já existe. O índice único segura o livro.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'aa111111-1111-1111-1111-111111111111',
  'transicao@example.com',
  '{"display_name":"Transição"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'aa211111-1111-1111-1111-111111111111',
  'aa111111-1111-1111-1111-111111111111',
  'curitiba',
  'Casa Transição',
  'Centro',
  'Rua do Livro',
  '10',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '11222333000181',
  '41988880010',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'aa311111-1111-1111-1111-111111111111',
  'aa211111-1111-1111-1111-111111111111',
  'Sala Transição',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'aa411111-1111-1111-1111-111111111111',
  'aa311111-1111-1111-1111-111111111111',
  '2027-08-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'aa511111-1111-1111-1111-111111111111',
  'curitiba',
  'aa211111-1111-1111-1111-111111111111',
  'aa311111-1111-1111-1111-111111111111',
  'aa411111-1111-1111-1111-111111111111',
  '2027-08-01 18:00:00+00',
  4,
  2,
  10000,
  'aa111111-1111-1111-1111-111111111111'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'aa511111-1111-1111-1111-111111111111',
  'aa111111-1111-1111-1111-111111111111',
  'Transição',
  true,
  'released',
  'refunded',
  'group_did_not_close'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, paid_at, refunded_at
) values (
  'aa611111-1111-1111-1111-111111111111',
  'aa511111-1111-1111-1111-111111111111',
  'aa111111-1111-1111-1111-111111111111',
  'aa211111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'refunded',
  'pay_refunded',
  'idem-transicao-refunded',
  1000,
  '2026-11-05 12:00:00+00',
  '2026-11-05 13:00:00+00'
);

insert into public.ledger_entries (
  venue_id, group_id, user_id, account, direction, kind,
  amount_cents, payment_charge_id
) values (
  'aa211111-1111-1111-1111-111111111111',
  'aa511111-1111-1111-1111-111111111111',
  'aa111111-1111-1111-1111-111111111111',
  'house',
  'credit',
  'house_net',
  8995,
  'aa611111-1111-1111-1111-111111111111'
);

do $$
declare
  v_result jsonb;
  v_paid timestamptz;
  v_refunded timestamptz;
  v_debits integer;
  v_credits integer;
begin
  v_result := private.apply_payment_transition(
    'aa611111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  if v_result->>'status' <> 'refunded' or (v_result->>'applied')::boolean then
    raise exception 'RECEIVED reabriu cobrança estornada: %', v_result;
  end if;
  select paid_at, refunded_at
    into v_paid, v_refunded
  from public.payment_charges
  where id = 'aa611111-1111-1111-1111-111111111111';
  if v_paid <> '2026-11-05 12:00:00+00'
    or v_refunded <> '2026-11-05 13:00:00+00'
  then
    raise exception 'estorno reescreveu paid_at ou refunded_at';
  end if;
  select count(*) into v_debits
  from public.ledger_entries
  where payment_charge_id = 'aa611111-1111-1111-1111-111111111111'
    and direction = 'debit'
    and kind = 'house_refund';
  if v_debits <> 1 then
    raise exception 'estorno não gerou o débito do crédito que já existia: %', v_debits;
  end if;

  v_result := private.apply_payment_transition(
    'aa611111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  select count(*) into v_credits
  from public.ledger_entries
  where payment_charge_id = 'aa611111-1111-1111-1111-111111111111'
    and direction = 'credit';
  if v_credits <> 1 then
    raise exception 'cobrança estornada recebeu crédito: %', v_credits;
  end if;

  if not exists (
    select 1
    from public.group_members
    where group_id = 'aa511111-1111-1111-1111-111111111111'
      and user_id = 'aa111111-1111-1111-1111-111111111111'
      and payment_status = 'released'
      and refund_status = 'refunded'
      and refund_reason = 'group_did_not_close'
  ) then
    raise exception 'estorno marcou o membro como pago';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'aa711111-1111-1111-1111-111111111111',
  'pix-reserva@example.com',
  '{"display_name":"Pix"}'
);

insert into public.group_members (
  group_id, user_id, display_name, payment_status
) values (
  'aa511111-1111-1111-1111-111111111111',
  'aa711111-1111-1111-1111-111111111111',
  'Pix',
  'pending'
);

do $$
declare
  v_first jsonb;
  v_second jsonb;
  v_ref text;
  v_again text;
  v_paid timestamptz;
  v_replay timestamptz;
begin
  v_first := private.reserve_pix_charge(
    'aa511111-1111-1111-1111-111111111111',
    'aa711111-1111-1111-1111-111111111111',
    'aa211111-1111-1111-1111-111111111111',
    10000,
    'idem-pix-reserva',
    'wal_casa',
    1000
  );
  if (v_first->>'inserted')::boolean is not true
    or v_first->>'provider_ref' is not null
    or v_first->>'status' <> 'creating'
  then
    raise exception 'reserva inicial inesperada: %', v_first;
  end if;

  if v_first->>'attempt_id' is null then
    raise exception 'reserva não devolveu attempt_id';
  end if;

  v_ref := private.attach_pix_provider(
    (v_first->>'id')::uuid,
    'pay_primeiro',
    (v_first->>'attempt_id')::uuid
  );
  if v_ref <> 'pay_primeiro' then
    raise exception 'attach não gravou o primeiro id: %', v_ref;
  end if;

  v_again := private.attach_pix_provider(
    (v_first->>'id')::uuid,
    'pay_segundo',
    (v_first->>'attempt_id')::uuid
  );
  if v_again <> 'pay_primeiro' then
    raise exception 'attach sobrescreveu provider_ref: %', v_again;
  end if;

  v_again := private.attach_pix_provider(
    (v_first->>'id')::uuid,
    'pay_terceiro',
    gen_random_uuid()
  );
  if v_again <> 'pay_primeiro' then
    raise exception 'attempt errado gravou provider_ref: %', v_again;
  end if;

  v_second := private.reserve_pix_charge(
    'aa511111-1111-1111-1111-111111111111',
    'aa711111-1111-1111-1111-111111111111',
    'aa211111-1111-1111-1111-111111111111',
    10000,
    'idem-pix-reserva-2',
    'wal_casa',
    1000
  );
  if (v_second->>'inserted')::boolean
    or v_second->>'provider_ref' <> 'pay_primeiro'
  then
    raise exception 'segunda reserva criou ou trocou o Pix: %', v_second;
  end if;

  perform private.apply_payment_transition(
    (v_first->>'id')::uuid,
    'paid',
    true
  );
  select paid_at into v_paid
  from public.payment_charges
  where id = (v_first->>'id')::uuid;
  perform pg_catalog.pg_sleep(0.01);
  perform private.apply_payment_transition(
    (v_first->>'id')::uuid,
    'paid',
    true
  );
  select paid_at into v_replay
  from public.payment_charges
  where id = (v_first->>'id')::uuid;
  if v_paid is null or v_paid <> v_replay then
    raise exception 'replay reescreveu paid_at';
  end if;
end $$;

do $$
begin
  if has_function_privilege(
      'anon',
      'public.apply_payment_transition(uuid, text, boolean)',
      'execute'
    )
    or has_function_privilege(
      'authenticated',
      'public.apply_payment_transition(uuid, text, boolean)',
      'execute'
    )
    or has_function_privilege(
      'anon',
      'public.reserve_pix_charge(uuid, uuid, uuid, integer, text, text, integer)',
      'execute'
    )
    or not has_function_privilege(
      'service_role',
      'public.apply_payment_transition(uuid, text, boolean)',
      'execute'
    )
  then
    raise exception 'execute da transição não ficou só na service_role';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'aa811111-1111-1111-1111-111111111111',
  'comissao-alta@example.com',
  '{"display_name":"Alta"}'
);

insert into public.group_members (
  group_id, user_id, display_name, payment_status
) values (
  'aa511111-1111-1111-1111-111111111111',
  'aa811111-1111-1111-1111-111111111111',
  'Alta',
  'pending'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'aa821111-1111-1111-1111-111111111111',
  'lease@example.com',
  '{"display_name":"Lease"}'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, commission_bps
) values (
  'aa911111-1111-1111-1111-111111111111',
  'aa511111-1111-1111-1111-111111111111',
  'aa811111-1111-1111-1111-111111111111',
  'aa211111-1111-1111-1111-111111111111',
  800000,
  'PIX',
  'pending',
  'idem-comissao-alta',
  3000
);

do $$
declare
  v_fee integer;
  v_net integer;
  v_paid text;
  v_fresh uuid;
  v_stale uuid;
  v_orphan uuid;
begin
  perform private.apply_payment_transition(
    'aa911111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  select amount_cents into v_fee
  from public.ledger_entries
  where payment_charge_id = 'aa911111-1111-1111-1111-111111111111'
    and kind = 'commission'
    and direction = 'credit';
  select amount_cents into v_net
  from public.ledger_entries
  where payment_charge_id = 'aa911111-1111-1111-1111-111111111111'
    and kind = 'house_net'
    and direction = 'credit';
  if v_fee <> 240000 or v_net <> 560000 then
    raise exception 'comissão alta estourou ou saiu errada: fee % net %', v_fee, v_net;
  end if;
  select payment_status into v_paid
  from public.group_members
  where user_id = 'aa811111-1111-1111-1111-111111111111';
  if v_paid <> 'paid' then
    raise exception 'membro não ficou pago: %', v_paid;
  end if;

  update public.payment_charges
  set reserved_at = pg_catalog.now()
  where id = 'aa911111-1111-1111-1111-111111111111';
  -- a cobrança paga não está creating; o teste do lease usa uma linha creating.
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, reserved_at
  ) values (
    'aaa11111-1111-1111-1111-111111111111',
    'aa511111-1111-1111-1111-111111111111',
    'aa821111-1111-1111-1111-111111111111',
    'aa211111-1111-1111-1111-111111111111',
    1000,
    'PIX',
    'creating',
    'idem-lease-fresh',
    1000,
    pg_catalog.now()
  );
  v_fresh := private.claim_expired_pix_reservation(
    'aaa11111-1111-1111-1111-111111111111'
  );
  if v_fresh is not null then
    raise exception 'reserva fresca foi assumida';
  end if;
  update public.payment_charges
  set reserved_at = pg_catalog.now() - interval '3 minutes'
  where id = 'aaa11111-1111-1111-1111-111111111111';
  v_stale := private.claim_expired_pix_reservation(
    'aaa11111-1111-1111-1111-111111111111'
  );
  if v_stale is null then
    raise exception 'reserva vencida não foi assumida';
  end if;
  if private.claim_expired_pix_reservation(
    'aaa11111-1111-1111-1111-111111111111'
  ) is not null then
    raise exception 'reserva recém-assumida foi tomada de novo';
  end if;
  if private.release_pix_reservation(
    'aaa11111-1111-1111-1111-111111111111',
    gen_random_uuid()
  ) then
    raise exception 'release de outro attempt apagou a reserva';
  end if;
  if not private.release_pix_reservation(
    'aaa11111-1111-1111-1111-111111111111',
    v_stale
  ) then
    raise exception 'release do attempt dono não apagou';
  end if;

  if has_table_privilege('anon', 'private.orphan_payments', 'select')
    or has_table_privilege('authenticated', 'private.orphan_payments', 'select')
    or has_table_privilege('anon', 'private.orphan_payments', 'insert')
  then
    raise exception 'orphan_payments aberto ao público';
  end if;
  if not (
    select c.relrowsecurity
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'orphan_payments'
  ) then
    raise exception 'orphan_payments sem rls';
  end if;
  v_orphan := private.record_orphan_payment(
    'pay_orfao',
    null,
    v_stale,
    'PIX',
    'cancel_failed'
  );
  if v_orphan is null then
    raise exception 'órfão não foi gravado';
  end if;
end $$;

do $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  ) values (
    'aa211111-1111-1111-1111-111111111111',
    'aa511111-1111-1111-1111-111111111111',
    'aa111111-1111-1111-1111-111111111111',
    'house',
    'credit',
    'house_net',
    8995,
    'aa611111-1111-1111-1111-111111111111'
  );
  raise exception 'duplicata de ledger passou pelo índice';
exception
  when unique_violation then
    null;
end $$;
