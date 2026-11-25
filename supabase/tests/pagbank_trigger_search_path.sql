-- search_path vazio nos gatilhos de cobrança e saque PagBank.
-- A normalização continua a mesma: provedor antigo vira pagbank,
-- a taxa copia dos dois lados e o id do saque só segue do PagBank
-- para a coluna antiga.

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
  v_case record;
  v_user uuid;
  v_charge uuid;
  v_provider text;
  v_fee integer;
  v_asaas integer;
  v_group uuid := 'c2710000-0000-4000-8000-000000000001';
  v_venue uuid := 'c2720000-0000-4000-8000-000000000001';
  v_src text;
  v_bare text;
begin
  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('sync_pagbank_charge', 'sync_pagbank_withdrawal')
      and p.pronargs = 0
      and not p.prosecdef
      and 'search_path=""' = any (p.proconfig)
  ) <> 2 then
    raise exception 'gatilho PagBank sem search_path vazio';
  end if;

  select p.prosrc
    into v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'sync_pagbank_charge'
    and p.pronargs = 0;
  v_bare := replace(v_src, 'pg_catalog.lower', '');
  if (length(v_src) - length(v_bare)) / length('pg_catalog.lower') <> 2
    or v_bare like '%lower(%'
  then
    raise exception 'sync_pagbank_charge sem as duas chamadas pg_catalog.lower';
  end if;

  select p.prosrc
    into v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'sync_pagbank_withdrawal'
    and p.pronargs = 0;
  if v_src like '%lower(%'
    or v_src not like '%new.asaas_transfer_id := new.pagbank_transfer_id%'
  then
    raise exception 'sync_pagbank_withdrawal mudou a cópia do id';
  end if;

  if (
    select count(*)
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace cn on cn.oid = c.relnamespace
    where not t.tgisinternal
      and pn.nspname = 'private'
      and (
        (
          t.tgname = 'sync_pagbank_charge'
          and cn.nspname = 'public'
          and c.relname = 'payment_charges'
          and p.proname = 'sync_pagbank_charge'
          and pg_get_triggerdef(t.oid) ilike '%before insert or update%for each row%private.sync_pagbank_charge()%'
        )
        or (
          t.tgname = 'sync_pagbank_withdrawal'
          and cn.nspname = 'public'
          and c.relname = 'venue_withdrawals'
          and p.proname = 'sync_pagbank_withdrawal'
          and pg_get_triggerdef(t.oid) ilike '%before insert or update%for each row%private.sync_pagbank_withdrawal()%'
        )
      )
  ) <> 2 then
    raise exception 'trigger PagBank desconectado da função';
  end if;

  for v_case in
    select *
    from (
      values
        (1, 'ASAAS'::text, false, null::integer, null::integer, 'pagbank'::text, null::integer, null::integer),
        (2, 'Woovi', false, null, null, 'pagbank', null, null),
        (3, 'OPENPIX', false, null, null, 'pagbank', null, null),
        (4, 'MercadoPago', false, null, null, 'pagbank', null, null),
        (5, 'mercado_pago', false, null, null, 'pagbank', null, null),
        (6, 'pagbank', false, null, null, 'pagbank', null, null),
        (7, 'stripe', false, null, null, 'stripe', null, null),
        (8, 'PAGBANK', false, null, null, 'PAGBANK', null, null),
        (9, ' asaas', false, null, null, ' asaas', null, null),
        (10, '', false, null, null, '', null, null),
        (11, null, false, null, null, 'pagbank', null, null),
        (12, null, true, null, null, 'pagbank', null, null),
        (13, 'stripe', false, 150, null, 'stripe', 150, 150),
        (14, 'stripe', false, null, 40, 'stripe', 40, 40),
        (15, 'stripe', false, 10, 99, 'stripe', 10, 10),
        (16, 'stripe', false, 0, 12, 'stripe', 0, 0)
    ) as seed (
      n, provider, omit_provider, fee, asaas,
      expect_provider, expect_fee, expect_asaas
    )
  loop
    v_user := (
      'c2701000-0000-4000-8000-' || lpad(v_case.n::text, 12, '0')
    )::uuid;
    v_charge := (
      'c2750000-0000-4000-8000-' || lpad(v_case.n::text, 12, '0')
    )::uuid;
    insert into auth.users (id, email)
    values (v_user, 'search-path-' || v_case.n || '@example.com');
    if v_case.omit_provider then
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type,
        idempotency_key, commission_bps, provider_fee_cents, asaas_fee_cents
      ) values (
        v_charge, v_group, v_user, v_venue, 10000, 'PIX',
        'idem-search-path-' || v_case.n, 1000, v_case.fee, v_case.asaas
      );
    else
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type,
        idempotency_key, commission_bps, provider, provider_fee_cents,
        asaas_fee_cents
      ) values (
        v_charge, v_group, v_user, v_venue, 10000, 'PIX',
        'idem-search-path-' || v_case.n, 1000, v_case.provider,
        v_case.fee, v_case.asaas
      );
    end if;
    select provider, provider_fee_cents, asaas_fee_cents
      into v_provider, v_fee, v_asaas
    from public.payment_charges
    where id = v_charge;
    if v_provider is distinct from v_case.expect_provider
      or v_fee is distinct from v_case.expect_fee
      or v_asaas is distinct from v_case.expect_asaas
    then
      raise exception
        'insert %: provider [%] taxa % asaas %, esperado [%] / % / %',
        v_case.n, v_provider, v_fee, v_asaas,
        v_case.expect_provider, v_case.expect_fee, v_case.expect_asaas;
    end if;
  end loop;

  v_charge := 'c2750000-0000-4000-8000-000000000015';

  update public.payment_charges
  set provider = 'Woovi'
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'pagbank' or v_fee is distinct from 10
    or v_asaas is distinct from 10
  then
    raise exception 'update Woovi reescreveu a cobrança: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set provider = 'stripe'
  where id = v_charge;
  update public.payment_charges
  set provider_fee_cents = 200
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 200
    or v_asaas is distinct from 200
  then
    raise exception 'taxa do provedor não copiou para a coluna antiga: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set asaas_fee_cents = 7
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 7
    or v_asaas is distinct from 7
  then
    raise exception 'taxa antiga não copiou para o provedor: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set provider_fee_cents = 8, asaas_fee_cents = 9
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 8
    or v_asaas is distinct from 8
  then
    raise exception 'as duas taxas no mesmo update não deram prioridade ao provedor: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set status = 'authorized'
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 8
    or v_asaas is distinct from 8
  then
    raise exception 'update de status reescreveu provedor ou taxa: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set provider = null
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'pagbank' or v_fee is distinct from 8
    or v_asaas is distinct from 8
  then
    raise exception 'provider nulo no update não virou pagbank: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set provider = 'Mercado_Pago'
  where id = v_charge;
  select provider into v_provider
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'pagbank' then
    raise exception 'Mercado_Pago no update ficou %', v_provider;
  end if;

  update public.payment_charges
  set provider = 'stripe', asaas_fee_cents = 3
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'stripe' or v_fee is distinct from 3
    or v_asaas is distinct from 3
  then
    raise exception 'troca de provedor com taxa antiga não copiou a taxa: % % %',
      v_provider, v_fee, v_asaas;
  end if;

  update public.payment_charges
  set provider = 'asaas', provider_fee_cents = 5, asaas_fee_cents = 6
  where id = v_charge;
  select provider, provider_fee_cents, asaas_fee_cents
    into v_provider, v_fee, v_asaas
  from public.payment_charges
  where id = v_charge;
  if v_provider is distinct from 'pagbank' or v_fee is distinct from 5
    or v_asaas is distinct from 5
  then
    raise exception 'update com asaas e as duas taxas mudou o resultado: % % %',
      v_provider, v_fee, v_asaas;
  end if;
end $$;

do $$
declare
  v_venue uuid := 'c2720000-0000-4000-8000-000000000001';
  v_pagbank text;
  v_asaas text;
begin
  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, pagbank_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000001',
    v_venue, 100, 'pending', 'manual', 'manual-sp-01',
    'ext-search-path-01', 'TR-1'
  );
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_pagbank is distinct from 'TR-1' or v_asaas is distinct from 'TR-1' then
    raise exception 'insert do saque não copiou o id PagBank: % / %',
      v_pagbank, v_asaas;
  end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, asaas_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000002',
    v_venue, 100, 'pending', 'manual', 'manual-sp-02',
    'ext-search-path-02', 'TR-ONLY'
  );
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000002';
  if v_pagbank is not null or v_asaas is distinct from 'TR-ONLY' then
    raise exception 'insert só com id antigo criou id PagBank: % / %',
      v_pagbank, v_asaas;
  end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, pagbank_transfer_id, asaas_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000003',
    v_venue, 100, 'pending', 'manual', 'manual-sp-03',
    'ext-search-path-03', 'TR-B', 'TR-OLD'
  );
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000003';
  if v_pagbank is distinct from 'TR-B' or v_asaas is distinct from 'TR-B' then
    raise exception 'insert com os dois ids não priorizou o PagBank: % / %',
      v_pagbank, v_asaas;
  end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, pagbank_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000004',
    v_venue, 100, 'pending', 'manual', 'manual-sp-04',
    'ext-search-path-04', 'Tr-AbC'
  );
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000004';
  if v_pagbank is distinct from 'Tr-AbC' or v_asaas is distinct from 'Tr-AbC' then
    raise exception 'o id do saque mudou de caixa: % / %', v_pagbank, v_asaas;
  end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, pagbank_transfer_id
  ) values (
    'c2760000-0000-4000-8000-000000000005',
    v_venue, 100, 'pending', 'manual', 'manual-sp-05',
    'ext-search-path-05', ''
  );
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000005';
  if v_pagbank is distinct from '' or v_asaas is distinct from '' then
    raise exception 'id vazio do saque não copiou: [%] / [%]', v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set asaas_transfer_id = 'TR-OTHER'
  where id = 'c2760000-0000-4000-8000-000000000001';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_pagbank is distinct from 'TR-1' or v_asaas is distinct from 'TR-OTHER' then
    raise exception 'update só da coluna antiga mexeu no PagBank: % / %',
      v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set pagbank_transfer_id = 'TR-1', asaas_transfer_id = 'TR-KEEP'
  where id = 'c2760000-0000-4000-8000-000000000001';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_pagbank is distinct from 'TR-1' or v_asaas is distinct from 'TR-KEEP' then
    raise exception 'o mesmo id PagBank reescreveu a coluna antiga: % / %',
      v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set pagbank_transfer_id = 'TR-2'
  where id = 'c2760000-0000-4000-8000-000000000001';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_pagbank is distinct from 'TR-2' or v_asaas is distinct from 'TR-2' then
    raise exception 'id PagBank novo não copiou: % / %', v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set pagbank_transfer_id = null
  where id = 'c2760000-0000-4000-8000-000000000001';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000001';
  if v_pagbank is not null or v_asaas is distinct from 'TR-2' then
    raise exception 'limpar o id PagBank apagou a coluna antiga: % / %',
      v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set amount_cents = 250, status = 'done'
  where id = 'c2760000-0000-4000-8000-000000000003';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000003';
  if v_pagbank is distinct from 'TR-B' or v_asaas is distinct from 'TR-B' then
    raise exception 'update de valor reescreveu o id do saque: % / %',
      v_pagbank, v_asaas;
  end if;

  update public.venue_withdrawals
  set pagbank_transfer_id = 'TR-NEW'
  where id = 'c2760000-0000-4000-8000-000000000002';
  select pagbank_transfer_id, asaas_transfer_id
    into v_pagbank, v_asaas
  from public.venue_withdrawals
  where id = 'c2760000-0000-4000-8000-000000000002';
  if v_pagbank is distinct from 'TR-NEW' or v_asaas is distinct from 'TR-NEW' then
    raise exception 'id PagBank que nasceu nulo não copiou no update: % / %',
      v_pagbank, v_asaas;
  end if;
end $$;

rollback;
