-- Conta real continua bloqueada entre si no documento e na conta PagBank.
-- Conta is_test cria a casa e não bloqueia a casa real nos dois sentidos.
-- Usuário comum não vira teste.
-- supabase/migrations/20261124223000_test_account_duplicate_exception.sql

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('f1a11111-1111-4111-8111-111111111111', 'real-dono@example.com', '{"display_name":"Dono Real"}'),
  ('f1a22222-2222-4222-8222-222222222222', 'real-outra@example.com', '{"display_name":"Outra Real"}'),
  ('f1a33333-3333-4333-8333-333333333333', 'tester-casa@example.com', '{"display_name":"Tester Casa"}'),
  ('f1a44444-4444-4444-8444-444444444444', 'comum-casa@example.com', '{"display_name":"Comum Casa"}');

update public.profiles set is_test = true
where id = 'f1a33333-3333-4333-8333-333333333333';

begin;
select set_config('request.jwt.claim.sub', 'f1a11111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone
) values (
  'f1b11111-1111-4111-8111-111111111111',
  'f1a11111-1111-4111-8111-111111111111',
  'curitiba', 'Casa Real Centro', 'Centro', 'Rua Real', '10',
  '80010010', -25.43, -49.27, 5000, 'cpf', '41414141414', '41911110001'
);
reset role;
commit;

-- Perfil oficial: aprovado e ainda sem dono que tenha reivindicado.
update public.venues
set status = 'approved', claimed_at = null
where id = 'f1b11111-1111-4111-8111-111111111111';

-- Conta real: mesma mensagem e a mesma reivindicação.
begin;
select set_config('request.jwt.claim.sub', 'f1a22222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_found jsonb;
  v_type text;
  v_name text;
begin
  v_found := public.find_claimable_venue('414.141.414-14');
  if v_found ->> 'path' is distinct from 'manual'
    or v_found ->> 'name' is distinct from 'Casa Real Centro'
  then
    raise exception 'conta real não recebeu a reivindicação: %', v_found;
  end if;

  select found.conflict_type, found.venue_name
    into v_type, v_name
  from public.check_venue_duplicates(
    '41414141414', 'Outra Casa', 'curitiba', '01310000', '9'
  ) found
  where found.conflict_type = 'documento';
  if v_type is distinct from 'documento' or v_name is distinct from 'Casa Real Centro' then
    raise exception 'conta real não viu o documento repetido';
  end if;

  begin
    insert into public.venues (
      id, owner_id, city_id, name, neighborhood, street_address, address_number,
      postal_code, latitude, longitude, income_value, document_kind,
      document_number, phone, is_test
    ) values (
      'f1b22222-2222-4222-8222-222222222222',
      'f1a22222-2222-4222-8222-222222222222',
      'curitiba', 'Casa Real Duplicada', 'Centro', 'Rua Real', '11',
      '80010011', -25.43, -49.27, 5000, 'cpf', '41414141414', '41911110002',
      true
    );
    raise exception 'conta real criou casa com documento repetido';
  exception
    when unique_violation then
      if sqlerrm is distinct from 'duplicate document' then
        raise exception 'conta real recebeu outra mensagem: %', sqlerrm;
      end if;
  end;
end $$;
reset role;
commit;

do $$
begin
  if exists (
    select 1 from public.venues where id = 'f1b22222-2222-4222-8222-222222222222'
  ) or exists (
    select 1 from public.profiles
    where id = 'f1a22222-2222-4222-8222-222222222222' and is_test
  ) then
    raise exception 'conta real gravou casa ou virou teste';
  end if;
end $$;

-- Conta de teste: a checagem some e a casa nasce marcada.
begin;
select set_config('request.jwt.claim.sub', 'f1a33333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_found jsonb;
  v_rows integer;
begin
  v_found := public.find_claimable_venue('41414141414');
  if v_found is distinct from '{"path":"none"}'::jsonb then
    raise exception 'conta de teste ainda oferece reivindicação: %', v_found;
  end if;

  select count(*)
    into v_rows
  from public.check_venue_duplicates(
    '41414141414', 'Casa Real Centro', 'curitiba', '80010010', '10'
  );
  if v_rows <> 0 then
    raise exception 'conta de teste ainda recebe dedupe';
  end if;

  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone
  ) values (
    'f1b33333-3333-4333-8333-333333333333',
    'f1a33333-3333-4333-8333-333333333333',
    'curitiba', 'Casa Teste Nova', 'Centro', 'Rua do Teste', '12',
    '80010012', -25.43, -49.27, 5000, 'cpf', '41414141414', '41911110003'
  );
end $$;
reset role;
commit;

do $$
begin
  if not (
    select is_test from public.venues where id = 'f1b33333-3333-4333-8333-333333333333'
  ) then
    raise exception 'casa da conta de teste não nasceu marcada';
  end if;
end $$;

-- Documento que só a casa de teste usa não bloqueia a casa real
-- e não aparece para reivindicar.
begin;
select set_config('request.jwt.claim.sub', 'f1a33333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone
) values (
  'f1b44444-4444-4444-8444-444444444444',
  'f1a33333-3333-4333-8333-333333333333',
  'curitiba', 'Casa Teste Sozinha', 'Centro', 'Rua do Teste', '13',
  '80010013', -25.43, -49.27, 5000, 'cpf', '42424242424', '41911110004'
);
reset role;
commit;

update public.venues
set status = 'approved', claimed_at = null
where id = 'f1b44444-4444-4444-8444-444444444444';

-- Trocar o documento da casa real para o da casa de teste também passa.
update public.venues
set document_number = '42424242424'
where id = 'f1b11111-1111-4111-8111-111111111111';
update public.venues
set document_number = '41414141414'
where id = 'f1b11111-1111-4111-8111-111111111111';

begin;
select set_config('request.jwt.claim.sub', 'f1a22222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_found jsonb;
  v_rows integer;
begin
  v_found := public.find_claimable_venue('42424242424');
  if v_found is distinct from '{"path":"none"}'::jsonb then
    raise exception 'conta real recebeu oferta da casa de teste: %', v_found;
  end if;

  select count(*)
    into v_rows
  from public.check_venue_duplicates(
    '42424242424', 'Casa Teste Sozinha', 'curitiba', '80010013', '13'
  );
  if v_rows <> 0 then
    raise exception 'conta real ainda vê a casa de teste no dedupe';
  end if;
end $$;
reset role;
commit;

update public.venues
set claimed_at = now()
where id = 'f1b44444-4444-4444-8444-444444444444';

begin;
select set_config('request.jwt.claim.sub', 'f1a22222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_found jsonb;
begin
  v_found := public.find_claimable_venue('42424242424');
  if v_found is distinct from '{"path":"none"}'::jsonb then
    raise exception 'conta real recebeu already_claimed da casa de teste: %', v_found;
  end if;

  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone
  ) values (
    'f1b55555-5555-4555-8555-555555555555',
    'f1a22222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Real no CPF de teste', 'Centro', 'Rua Real', '14',
    '80010014', -25.43, -49.27, 5000, 'cpf', '42424242424', '41911110005'
  );
end $$;
reset role;
commit;

do $$
begin
  if (
    select is_test from public.venues where id = 'f1b55555-5555-4555-8555-555555555555'
  ) is distinct from false
  or (
    select is_test from public.venues where id = 'f1b44444-4444-4444-8444-444444444444'
  ) is distinct from true
  then
    raise exception 'a casa real nasceu como teste ou a casa de teste sumiu';
  end if;
end $$;

-- Com as duas casas no mesmo documento, a conta real reivindica a casa real.
update public.venues
set status = 'approved', claimed_at = null
where id = 'f1b55555-5555-4555-8555-555555555555';

begin;
select set_config('request.jwt.claim.sub', 'f1a44444-4444-4444-8444-444444444444', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_found jsonb;
  v_type text;
  v_name text;
begin
  v_found := public.find_claimable_venue('42424242424');
  if v_found ->> 'path' is distinct from 'manual'
    or v_found ->> 'name' is distinct from 'Casa Real no CPF de teste'
  then
    raise exception 'conta real não reivindicou a casa real: %', v_found;
  end if;

  select found.conflict_type, found.venue_name
    into v_type, v_name
  from public.check_venue_duplicates(
    '42424242424', 'Outra Casa', 'curitiba', '01310000', '9'
  ) found
  where found.conflict_type = 'documento';
  if v_type is distinct from 'documento'
    or v_name is distinct from 'Casa Real no CPF de teste'
  then
    raise exception 'dedupe apontou para a casa de teste: % / %', v_type, v_name;
  end if;

  begin
    insert into public.venues (
      id, owner_id, city_id, name, neighborhood, street_address, address_number,
      postal_code, latitude, longitude, income_value, document_kind,
      document_number, phone
    ) values (
      'f1b88888-8888-4888-8888-888888888888',
      'f1a44444-4444-4444-8444-444444444444',
      'curitiba', 'Segunda Real no CPF', 'Centro', 'Rua Real', '15',
      '80010015', -25.43, -49.27, 5000, 'cpf', '42424242424', '41911110008'
    );
    raise exception 'segunda conta real passou no documento da casa real';
  exception
    when unique_violation then
      if sqlerrm is distinct from 'duplicate document' then
        raise exception 'mensagem mudou entre casas reais: %', sqlerrm;
      end if;
  end;
end $$;
reset role;
commit;

-- Usuário comum não vira teste, nem pelo perfil nem pela casa.
begin;
select set_config('request.jwt.claim.sub', 'f1a44444-4444-4444-8444-444444444444', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  begin
    update public.profiles set is_test = true
    where id = 'f1a44444-4444-4444-8444-444444444444';
    raise exception 'usuário comum gravou is_test';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    insert into public.venues (
      id, owner_id, city_id, name, neighborhood, street_address, address_number,
      postal_code, latitude, longitude, income_value, document_kind,
      document_number, phone, is_test
    ) values (
      'f1b66666-6666-4666-8666-666666666666',
      'f1a44444-4444-4444-8444-444444444444',
      'curitiba', 'Casa Comum', 'Centro', 'Rua Comum', '15',
      '80010015', -25.43, -49.27, 5000, 'cpf', '41414141414', '41911110006',
      true
    );
    raise exception 'usuário comum criou casa com documento repetido';
  exception
    when unique_violation then
      if sqlerrm is distinct from 'duplicate document' then
        raise exception 'usuário comum escapou com outra mensagem: %', sqlerrm;
      end if;
  end;
end $$;
reset role;
commit;

do $$
declare
  v_document text;
  v_pagbank text;
begin
  if exists (
    select 1 from public.profiles
    where id = 'f1a44444-4444-4444-8444-444444444444' and is_test
  ) then
    raise exception 'usuário comum ficou com is_test';
  end if;

  -- Desde 20261127190000 o bloqueio entre donos diferentes é feito por
  -- gatilho com trava, não por índice único (o mesmo dono pode repetir
  -- documento e conta PagBank entre cidades).
  v_document := pg_get_functiondef('private.venues_normalize()'::regprocedure);
  if v_document not ilike '%duplicate document%'
    or v_document not ilike '%not venue.is_test%'
    or v_document not ilike '%rejected%'
    or v_document not ilike '%pg_advisory_xact_lock%'
  then
    raise exception 'checagem do documento afrouxou casa real';
  end if;

  v_pagbank := pg_get_functiondef('private.venues_pagbank_account_one_owner()'::regprocedure);
  if v_pagbank not ilike '%pagbank_account_in_use%'
    or v_pagbank not ilike '%not o.is_test%'
    or not exists (
      select 1 from pg_trigger
      where tgrelid = 'public.venues'::regclass
        and tgname = 'venues_pagbank_account_one_owner'
        and not tgisinternal
    )
  then
    raise exception 'checagem PagBank afrouxou casa real';
  end if;

  if pg_get_functiondef('public.find_claimable_venue(text)'::regprocedure)
    ilike '%p_is_test%'
    or pg_get_functiondef('private.check_venue_duplicates(text,text,text,text,text)'::regprocedure)
      ilike '%p_is_test%'
  then
    raise exception 'a exceção aceita parâmetro do cliente';
  end if;
end $$;

-- A mesma conta PagBank cabe na casa de teste e não cabe em outra casa real.
update public.venues
set pagbank_account_id = 'ACCO_compartilhada'
where id = 'f1b11111-1111-4111-8111-111111111111';

update public.venues
set pagbank_account_id = 'ACCO_compartilhada'
where id = 'f1b33333-3333-4333-8333-333333333333';

do $$
begin
  if (
    select pagbank_account_id from public.venues
    where id = 'f1b33333-3333-4333-8333-333333333333'
  ) is distinct from 'ACCO_compartilhada'
  then
    raise exception 'casa de teste não repetiu a conta PagBank';
  end if;
end $$;

-- Segunda casa de teste também repete a mesma conta.
update public.venues
set pagbank_account_id = 'ACCO_compartilhada'
where id = 'f1b44444-4444-4444-8444-444444444444';

begin;
select set_config('request.jwt.claim.sub', 'f1a22222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone
) values (
  'f1b77777-7777-4777-8777-777777777777',
  'f1a22222-2222-4222-8222-222222222222',
  'curitiba', 'Segunda Casa Real', 'Batel', 'Rua Outra', '20',
  '80010020', -25.44, -49.28, 5000, 'cnpj', '61616161000161', '41911110007'
);
reset role;
commit;

do $$
begin
  begin
    update public.venues
    set pagbank_account_id = 'ACCO_compartilhada'
    where id = 'f1b77777-7777-4777-8777-777777777777';
    raise exception 'casa real repetiu a conta PagBank';
  exception
    when unique_violation then
      null;
  end;
  if (
    select pagbank_account_id from public.venues
    where id = 'f1b77777-7777-4777-8777-777777777777'
  ) is not null then
    raise exception 'casa real ficou com a conta PagBank repetida';
  end if;
end $$;

delete from public.venues where id in (
  'f1b11111-1111-4111-8111-111111111111',
  'f1b33333-3333-4333-8333-333333333333',
  'f1b44444-4444-4444-8444-444444444444',
  'f1b55555-5555-4555-8555-555555555555',
  'f1b77777-7777-4777-8777-777777777777'
);
delete from auth.users where id in (
  'f1a11111-1111-4111-8111-111111111111',
  'f1a22222-2222-4222-8222-222222222222',
  'f1a33333-3333-4333-8333-333333333333',
  'f1a44444-4444-4444-8444-444444444444'
);
