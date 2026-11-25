-- O espelho saiu. A reserva grava pagbank, o default da cobrança é
-- pagbank e o saque só tem o id da PagBank. As funções tocadas
-- continuam com search_path vazio.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email)
values (
  'c2700000-0000-4000-8000-000000000001',
  'search-path-casa@example.com'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'c2720000-0000-4000-8000-000000000001',
  'c2700000-0000-4000-8000-000000000001',
  'curitiba',
  'Casa Search Path',
  'Centro',
  'Rua do Caminho',
  '77',
  '80020999',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '55667788000155',
  '41977770099',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'c2730000-0000-4000-8000-000000000001',
  'c2720000-0000-4000-8000-000000000001',
  'Sala Search Path',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'c2740000-0000-4000-8000-000000000001',
  'c2730000-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'c2710000-0000-4000-8000-000000000001',
  'curitiba',
  'c2720000-0000-4000-8000-000000000001',
  'c2730000-0000-4000-8000-000000000001',
  'c2740000-0000-4000-8000-000000000001',
  '2027-09-01 18:00:00+00',
  4,
  2,
  10000,
  'c2700000-0000-4000-8000-000000000001'
);

do $$
declare
  v_user uuid := 'c2701000-0000-4000-8000-000000000001';
  v_payer uuid := 'c2701000-0000-4000-8000-000000000002';
  v_charge uuid := 'c2750000-0000-4000-8000-000000000001';
  v_group uuid := 'c2710000-0000-4000-8000-000000000001';
  v_venue uuid := 'c2720000-0000-4000-8000-000000000001';
  v_provider text;
  v_fee integer;
  v_default text;
  v_transfer text;
  v_reserved jsonb;
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname like 'sync_pagbank_%'
  ) or exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    where not t.tgisinternal
      and cn.nspname = 'public'
      and t.tgname like 'sync_pagbank_%'
  ) then
    raise exception 'o gatilho de espelho ainda existe';
  end if;

  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname, p.proname) in (
      ('private', 'pagbank_token_key'),
      ('private', 'venues_guard'),
      ('private', 'profiles_guard'),
      ('private', 'reserve_with_subsidy')
    )
      and 'search_path=""' = any (p.proconfig)
  ) <> 4 then
    raise exception 'função PagBank sem search_path vazio';
  end if;

  if char_length(private.pagbank_token_key()) < 32 then
    raise exception 'chave dos tokens curta';
  end if;

  select pg_get_expr(d.adbin, d.adrelid)
    into v_default
  from pg_attrdef d
  join pg_attribute a
    on a.attrelid = d.adrelid
   and a.attnum = d.adnum
  join pg_class c on c.oid = d.adrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'payment_charges'
    and a.attname = 'provider';
  if v_default is distinct from '''pagbank''::text' then
    raise exception 'default da cobrança não é pagbank: %', v_default;
  end if;

  if pg_get_functiondef(
    'private.reserve_with_subsidy(uuid,uuid,uuid,integer,text,text,integer,text,integer,integer,integer,numeric)'::regprocedure
  ) not like '%''pagbank''%' then
    raise exception 'a reserva não grava pagbank';
  end if;

  insert into auth.users (id, email)
  values (v_user, 'search-path-1@example.com');

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type,
    idempotency_key, commission_bps, provider_fee_cents
  ) values (
    v_charge, v_group, v_user, v_venue, 10000, 'PIX',
    'idem-search-path-1', 1000, 150
  );
  select provider, provider_fee_cents
    into v_provider, v_fee
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'pagbank' or v_fee is distinct from 150 then
    raise exception 'insert sem provedor ficou % / %', v_provider, v_fee;
  end if;

  update public.payment_charges
  set provider = 'stripe', provider_fee_cents = 200
  where id = v_charge;
  select provider, provider_fee_cents
    into v_provider, v_fee
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 200 then
    raise exception 'update da cobrança reescreveu % / %', v_provider, v_fee;
  end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, pagbank_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000001',
    v_venue, 100, 'pending', 'manual', 'manual-sp-01',
    'ext-search-path-01', 'TR-1'
  );
  update public.venue_withdrawals
  set pagbank_transfer_id = 'TR-2', amount_cents = 250, status = 'done'
  where id = 'c2760000-0000-4000-8000-000000000001';
  select pagbank_transfer_id
    into v_transfer
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_transfer is distinct from 'TR-2' then
    raise exception 'o id do saque não permaneceu: %', v_transfer;
  end if;

  insert into auth.users (id, email)
  values (v_payer, 'search-path-reserva@example.com');
  v_reserved := private.reserve_with_subsidy(
    v_group,
    v_payer,
    v_venue,
    10000,
    'idem-reserva-pagbank',
    null,
    1000,
    'PIX',
    null,
    0,
    0,
    null
  );
  select provider
    into v_provider
  from public.payment_charges
  where id = (v_reserved ->> 'id')::uuid;
  if v_provider is distinct from 'pagbank' then
    raise exception 'a reserva gravou %', v_provider;
  end if;
end $$;

rollback;
