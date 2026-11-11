-- Cartão do dono, comissão só de admin, grupo sem subconta e
-- wrappers de casa. Roda depois das migrations.

\set ON_ERROR_STOP on

do $$
declare
  v_name text;
  v_private text[] := array[
    'private.check_venue_duplicates(text,text,text,text,text)',
    'private.request_venue_claim(uuid,text,uuid)',
    'private.review_venue(uuid,text,uuid)',
    'private.review_venue_claim(uuid,text)'
  ];
  v_public text[] := array[
    'public.check_venue_duplicates(text,text,text,text,text)',
    'public.request_venue_claim(uuid,text,uuid)',
    'public.review_venue(uuid,text,uuid)',
    'public.review_venue_claim(uuid,text)'
  ];
begin
  foreach v_name in array v_private loop
    if has_function_privilege('authenticated', v_name, 'execute')
      or has_function_privilege('anon', v_name, 'execute')
    then
      raise exception 'authenticated ou anon executa %', v_name;
    end if;
    if not has_function_privilege('service_role', v_name, 'execute') then
      raise exception 'service_role perdeu %', v_name;
    end if;
  end loop;
  foreach v_name in array v_public loop
    if not has_function_privilege('authenticated', v_name, 'execute') then
      raise exception 'authenticated não executa o wrapper %', v_name;
    end if;
  end loop;
  if not (
    select bool_and(p.prosecdef)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'check_venue_duplicates',
        'request_venue_claim',
        'review_venue',
        'review_venue_claim'
      )
  ) then
    raise exception 'wrapper de casa não é security definer';
  end if;

  if not has_function_privilege('authenticated', 'public.deactivate_my_saved_card(uuid)', 'execute')
    or has_function_privilege('anon', 'public.deactivate_my_saved_card(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.my_payments()', 'execute')
    or has_function_privilege('anon', 'public.my_payments()', 'execute')
    or has_function_privilege('authenticated', 'public.commission_bps_for_venue(uuid)', 'execute')
    or not has_function_privilege('service_role', 'public.commission_bps_for_venue(uuid)', 'execute')
  then
    raise exception 'grants de carteira ou comissão saíram do combinado';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_platform_commission'
      and p.prosecdef
      and 'search_path=""' = any (p.proconfig)
  ) or not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_venue_commission'
      and p.prosecdef
      and 'search_path=""' = any (p.proconfig)
  ) then
    raise exception 'RPC de comissão sem security definer ou search_path vazio';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f1111111-1111-1111-1111-111111111111', 'dona-cartao@example.com', '{"display_name":"Dona"}'),
  ('f2222222-2222-2222-2222-222222222222', 'outro-cartao@example.com', '{"display_name":"Outro"}'),
  ('f3333333-3333-3333-3333-333333333333', 'admin-comissao@example.com', '{"display_name":"Admin"}');

update public.profiles
set asaas_customer_id = 'cus_dona'
where id = 'f1111111-1111-1111-1111-111111111111';
update public.profiles
set asaas_customer_id = 'cus_outro'
where id = 'f2222222-2222-2222-2222-222222222222';

insert into public.admins (user_id)
values ('f3333333-3333-3333-3333-333333333333');

select private.insert_saved_card(
  'f1111111-1111-1111-1111-111111111111',
  'cus_dona',
  'tok_dona_wallet',
  '4242',
  'VISA',
  'f4111111-1111-1111-1111-111111111111'
);
select private.insert_saved_card(
  'f2222222-2222-2222-2222-222222222222',
  'cus_outro',
  'tok_outro_wallet',
  '5555',
  'MASTERCARD',
  'f4222222-2222-2222-2222-222222222222'
);

begin;
select set_config('request.jwt.claim.sub', 'f2222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_removed boolean;
  v_count integer;
begin
  perform * from private.check_venue_duplicates('1', 'a', 'curitiba', '80010000', '1');
  raise exception 'authenticated executou private.check_venue_duplicates';
exception
  when insufficient_privilege then
    if sqlerrm ilike '%not admin%' or sqlerrm ilike '%venue not%' then
      raise exception 'a chamada private não foi recusada por privilégio: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform private.request_venue_claim(
    'f0000000-0000-0000-0000-000000000099', '', null
  );
  raise exception 'authenticated executou private.request_venue_claim';
exception
  when insufficient_privilege then
    if sqlerrm ilike '%venue not%' then
      raise exception 'private.request_venue_claim rodou: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform * from private.review_venue(
    'f0000000-0000-0000-0000-000000000099', 'approved', null
  );
  raise exception 'authenticated executou private.review_venue';
exception
  when insufficient_privilege then
    if sqlerrm ilike '%not admin%' then
      raise exception 'private.review_venue rodou: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform * from private.review_venue_claim(
    'f0000000-0000-0000-0000-000000000099', 'approved'
  );
  raise exception 'authenticated executou private.review_venue_claim';
exception
  when insufficient_privilege then
    if sqlerrm ilike '%not admin%' then
      raise exception 'private.review_venue_claim rodou: %', sqlerrm;
    end if;
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.check_venue_duplicates('1', 'Casa Solta', 'curitiba', '01310000', '9');
  if v_count < 0 then
    raise exception 'wrapper check_venue_duplicates não rodou';
  end if;
  perform public.request_venue_claim(
    'f0000000-0000-0000-0000-000000000099', 'oi', null
  );
  raise exception 'wrapper aceitou casa inexistente';
exception
  when sqlstate 'P0002' then
    if sqlerrm not ilike '%venue not approved%' then
      raise exception 'wrapper request_venue_claim: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform * from public.review_venue(
    'f0000000-0000-0000-0000-000000000099', 'approved', null
  );
  raise exception 'não admin revisou pelo wrapper';
exception
  when insufficient_privilege then
    if sqlerrm not ilike '%not admin%' then
      raise exception 'wrapper review_venue não chegou no corpo: %', sqlerrm;
    end if;
end $$;

do $$
begin
  perform * from public.review_venue_claim(
    'f0000000-0000-0000-0000-000000000099', 'rejected'
  );
  raise exception 'não admin revisou pedido pelo wrapper';
exception
  when insufficient_privilege then
    if sqlerrm not ilike '%not admin%' then
      raise exception 'wrapper review_venue_claim não chegou no corpo: %', sqlerrm;
    end if;
end $$;

do $$
declare
  v_removed boolean;
  v_count integer;
begin
  select public.deactivate_my_saved_card('f4111111-1111-1111-1111-111111111111')
    into v_removed;
  if v_removed then
    raise exception 'outro desativou o cartão da dona';
  end if;
  select public.deactivate_my_saved_card('f4222222-2222-2222-2222-222222222222')
    into v_removed;
  if not v_removed then
    raise exception 'outro não desativou o próprio cartão';
  end if;
  select count(*) into v_count from public.my_saved_cards();
  if v_count <> 0 then
    raise exception 'cartão desativado ainda aparece: %', v_count;
  end if;
end $$;

reset role;
commit;

begin;
select set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
declare
  v_last4 text;
  v_count integer;
begin
  select count(*) into v_count from public.my_saved_cards();
  if v_count <> 1 then
    raise exception 'dona viu % cartões', v_count;
  end if;
  select last4 into v_last4 from public.my_saved_cards();
  if v_last4 <> '4242' then
    raise exception 'dona não viu o próprio final';
  end if;
end $$;

reset role;
commit;

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'f5111111-1111-1111-1111-111111111111',
  'f1111111-1111-1111-1111-111111111111',
  'curitiba',
  'Casa Sem Subconta',
  'Centro',
  'Rua Sem Carteira',
  '15',
  '80030000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '55666777000155',
  '41988880055',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'f6111111-1111-1111-1111-111111111111',
  'f5111111-1111-1111-1111-111111111111',
  'Sala Sem Subconta',
  '',
  6,
  2,
  60,
  'medium',
  8000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'f7111111-1111-1111-1111-111111111111',
  'f6111111-1111-1111-1111-111111111111',
  '2027-06-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'f8111111-1111-1111-1111-111111111111',
  'curitiba',
  'f5111111-1111-1111-1111-111111111111',
  'f6111111-1111-1111-1111-111111111111',
  'f7111111-1111-1111-1111-111111111111',
  '2027-06-01 18:00:00+00',
  4,
  2,
  8000,
  'f1111111-1111-1111-1111-111111111111'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, commission_bps, refunded_at
) values
  (
    'f9111111-1111-1111-1111-111111111111',
    'f8111111-1111-1111-1111-111111111111',
    'f1111111-1111-1111-1111-111111111111',
    'f5111111-1111-1111-1111-111111111111',
    8000,
    'PIX',
    'paid',
    'idem-dona-wallet',
    1000,
    null
  ),
  (
    'f9222222-2222-2222-2222-222222222222',
    'f8111111-1111-1111-1111-111111111111',
    'f2222222-2222-2222-2222-222222222222',
    'f5111111-1111-1111-1111-111111111111',
    4000,
    'CREDIT_CARD',
    'refunded',
    'idem-outro-wallet',
    1000,
    '2026-11-02 12:00:00+00'
  );

begin;
select set_config('request.jwt.claim.sub', 'f2222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_count integer;
  v_room text;
  v_refunded boolean;
  v_amount integer;
begin
  select count(*) into v_count from public.my_payments();
  if v_count <> 1 then
    raise exception 'outro viu % pagamentos', v_count;
  end if;
  select room_name, refunded, amount_cents
    into v_room, v_refunded, v_amount
  from public.my_payments();
  if v_room <> 'Sala Sem Subconta' or not v_refunded or v_amount <> 4000 then
    raise exception 'pagamento do outro saiu errado: % % %', v_room, v_refunded, v_amount;
  end if;
  if exists (
    select 1 from public.payment_charges
    where user_id = 'f1111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'outro leu a cobrança da dona pela tabela';
  end if;
end $$;

do $$
begin
  perform public.set_platform_commission(1500);
  raise exception 'jogador alterou a comissão';
exception
  when insufficient_privilege then
    if sqlerrm not ilike '%not admin%' then
      raise exception 'comissão do jogador: %', sqlerrm;
    end if;
end $$;

reset role;
commit;

begin;
select set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
begin
  perform public.create_group(
    'f7111111-1111-1111-1111-111111111111',
    4,
    ''
  );
  raise exception 'grupo nasceu sem subconta';
exception
  when sqlstate 'P0001' then
    if sqlerrm not ilike '%conta de recebimento pendente%' then
      raise exception 'erro do grupo: %', sqlerrm;
    end if;
end $$;

reset role;
commit;

update public.venues
set asaas_wallet_id = 'wal_casa_sem'
where id = 'f5111111-1111-1111-1111-111111111111';

begin;
select set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
declare
  v_id uuid;
begin
  -- Já existe grupo nesse horário, criado sem JWT no fixture.
  -- A subconta libera a trava; a duplicata prova que o insert chegou lá.
  perform public.create_group(
    'f7111111-1111-1111-1111-111111111111',
    4,
    ''
  );
  raise exception 'duplicata não barrou o segundo grupo';
exception
  when unique_violation then
    null;
end $$;

reset role;
commit;

-- Sessão livre, com subconta, para o create_group concluir.
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'f7222222-2222-2222-2222-222222222222',
  'f6111111-1111-1111-1111-111111111111',
  '2027-06-02 18:00:00+00',
  'partner_grid'
);

begin;
select set_config('request.jwt.claim.sub', 'f1111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
declare
  v_id uuid;
begin
  v_id := public.create_group(
    'f7222222-2222-2222-2222-222222222222',
    4,
    ''
  );
  if v_id is null then
    raise exception 'grupo com subconta não nasceu';
  end if;
end $$;

reset role;
commit;

begin;
select set_config('request.jwt.claim.sub', 'f3333333-3333-3333-3333-333333333333', true);
set local role authenticated;

do $$
declare
  v_bps integer;
  v_actor uuid;
  v_venue integer;
  v_other integer;
begin
  perform public.set_platform_commission(3001);
  raise exception 'aceitou comissão acima de 30%%';
exception
  when invalid_parameter_value then
    null;
end $$;

do $$
declare
  v_bps integer;
  v_actor uuid;
begin
  perform public.set_platform_commission(1500);
  select s.commission_bps, s.updated_by
    into v_bps, v_actor
  from public.platform_settings s
  where s.id = 1;
  if v_bps <> 1500 or v_actor <> 'f3333333-3333-3333-3333-333333333333' then
    raise exception 'plataforma não gravou quem mudou: % %', v_bps, v_actor;
  end if;

  perform public.set_venue_commission(
    'f5111111-1111-1111-1111-111111111111',
    800
  );
  if not exists (
    select 1 from public.commission_board()
    where venue_id is null and commission_bps = 1500
  ) or not exists (
    select 1 from public.commission_board()
    where venue_id = 'f5111111-1111-1111-1111-111111111111'
      and commission_bps = 800
      and is_override
      and updated_by = 'f3333333-3333-3333-3333-333333333333'
  ) then
    raise exception 'painel de comissão incompleto';
  end if;
end $$;

reset role;

do $$
declare
  v_changes integer;
begin
  select count(*) into v_changes
  from public.commission_changes
  where actor_id = 'f3333333-3333-3333-3333-333333333333'
    and venue_id is null
    and before_bps = 2500
    and after_bps = 1500;
  if v_changes <> 1 then
    raise exception 'auditoria da plataforma: %', v_changes;
  end if;
end $$;

commit;

-- commission_bps_for_venue é da service role. O admin autenticado não chama.
begin;
select set_config('request.jwt.claim.sub', 'f3333333-3333-3333-3333-333333333333', true);
set local role authenticated;
do $$
begin
  perform public.commission_bps_for_venue('f5111111-1111-1111-1111-111111111111');
  raise exception 'authenticated leu commission_bps_for_venue';
exception
  when insufficient_privilege then
    null;
end $$;
reset role;
commit;

set role service_role;
do $$
declare
  v_bps integer;
begin
  select public.commission_bps_for_venue('f5111111-1111-1111-1111-111111111111')
    into v_bps;
  if v_bps <> 800 then
    raise exception 'service role não leu o override: %', v_bps;
  end if;
end $$;
reset role;
