-- Cadastro PagBank: sem CPF na tabela, sonda conservadora, admin aal2.

\set ON_ERROR_STOP on

insert into auth.users (id, email)
values
  ('7a111111-1111-4111-8111-111111111701', 'casa-signup@example.com'),
  ('7a222222-2222-4222-8222-222222222702', 'outra-signup@example.com'),
  ('7a333333-3333-4333-8333-333333333703', 'admin-signup@example.com');

insert into public.admins (user_id)
values ('7a333333-3333-4333-8333-333333333703');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    '7a444444-4444-4444-8444-444444444704',
    '7a111111-1111-4111-8111-111111111701',
    'curitiba', 'Casa Signup', 'Centro', 'Rua do Cadastro', '10',
    '80010010', -25.43, -49.27, 5000, 'cpf', '00123456797', '41988880031',
    'approved'
  ),
  (
    '7a555555-5555-4555-8555-555555555705',
    '7a222222-2222-4222-8222-222222222702',
    'curitiba', 'Outra Signup', 'Batel', 'Rua da Outra', '20',
    '80010020', -25.44, -49.28, 5000, 'cnpj', '98765432000198', '41988880032',
    'approved'
  );

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'venue_pagbank_signups'
      and column_name in (
        'document_number', 'tax_id', 'cpf', 'cnpj', 'email', 'phone',
        'birth_date', 'street', 'postal_code'
      )
  ) then
    raise exception 'a jornada guardou dado pessoal';
  end if;
  if has_table_privilege('anon', 'public.venue_pagbank_signups', 'select')
    or has_table_privilege('authenticated', 'public.venue_pagbank_signups', 'select')
    or has_table_privilege('service_role', 'public.venue_pagbank_signups', 'select')
    or has_table_privilege('anon', 'public.pagbank_signup_settings', 'select')
    or has_table_privilege('authenticated', 'public.pagbank_signup_events', 'select')
  then
    raise exception 'tabela de cadastro ficou legível pela API';
  end if;
  if has_function_privilege(
    'authenticated', 'public.apply_pagbank_signup_probe(integer, text, boolean)', 'execute'
  ) or has_function_privilege(
    'anon', 'public.save_venue_pagbank_signup(uuid, text, text, text, text)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.pagbank_signup_api_enabled()', 'execute'
  ) or not has_function_privilege(
    'authenticated', 'public.record_pagbank_signup_guide(uuid, text, text)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.apply_pagbank_signup_probe(integer, text, boolean)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.venue_pagbank_signup_gate(uuid)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.venue_pagbank_signup_gate(uuid)', 'execute'
  ) or has_function_privilege(
    'anon', 'private.invoke_pagbank_signup_probe()', 'execute'
  ) or has_function_privilege(
    'service_role', 'private.invoke_pagbank_signup_probe()', 'execute'
  ) then
    raise exception 'grant do cadastro saiu do combinado';
  end if;
end $$;

do $$
declare
  v_state jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', '7a111111-1111-4111-8111-111111111701', true
  );
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  v_state := public.record_pagbank_signup_guide(
    '7a444444-4444-4444-8444-444444444704',
    'cpf',
    'ENTERTAINMENT'
  );
  if v_state ->> 'api_enabled' is distinct from 'false'
    or v_state -> 'signup' ->> 'mode' is distinct from 'manual'
    or v_state -> 'signup' ->> 'account_status' is distinct from 'guided'
    or v_state::text ~ '[0-9]{11}'
  then
    raise exception 'o guia manual guardou coisa demais: %', v_state;
  end if;
  begin
    perform public.record_pagbank_signup_guide(
      '7a555555-5555-4555-8555-555555555705',
      'cpf',
      'ENTERTAINMENT'
    );
    raise exception 'outra casa gravou o guia';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'not owner' then
        raise;
      end if;
  end;
  begin
    perform public.record_pagbank_signup_guide(
      '7a444444-4444-4444-8444-444444444704',
      'cpf',
      'NAO_EXISTE'
    );
    raise exception 'categoria inválida passou';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'categoria' then
        raise;
      end if;
  end;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', '7a333333-3333-4333-8333-333333333703', true
  );
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  perform public.admin_disable_pagbank_signup();
  raise exception 'admin sem aal2 desligou o cadastro';
exception
  when insufficient_privilege then
    if sqlerrm <> 'mfa obrigatorio' then
      raise;
    end if;
end $$;

do $$
declare
  v_state jsonb;
  v_probe jsonb;
begin
  set local role service_role;
  v_probe := public.apply_pagbank_signup_probe(400, '40002', true);
  if v_probe ->> 'enabled' is distinct from 'false'
    or v_probe ->> 'changed' is distinct from 'false'
    or v_probe ->> 'streak' is distinct from '1'
  then
    raise exception 'a primeira sonda ligou sozinha: %', v_probe;
  end if;
  v_probe := public.apply_pagbank_signup_probe(401, 'http_401', true);
  if v_probe ->> 'enabled' is distinct from 'false'
    or v_probe ->> 'streak' is distinct from '0'
  then
    raise exception '401 não zerou a contagem: %', v_probe;
  end if;
  v_probe := public.apply_pagbank_signup_probe(400, '40001', true);
  if v_probe ->> 'enabled' is distinct from 'false'
    or v_probe ->> 'streak' is distinct from '1'
  then
    raise exception 'a contagem não recomeçou: %', v_probe;
  end if;
  v_probe := public.apply_pagbank_signup_probe(400, '40002', true);
  if v_probe ->> 'enabled' is distinct from 'true'
    or v_probe ->> 'changed' is distinct from 'true'
    or v_probe ->> 'streak' is distinct from '2'
  then
    raise exception 'a segunda sonda seguida não ligou: %', v_probe;
  end if;
  v_probe := public.apply_pagbank_signup_probe(400, '40001', true);
  if v_probe ->> 'changed' is distinct from 'false'
    or v_probe ->> 'enabled' is distinct from 'true'
  then
    raise exception 'a sonda seguinte avisaria de novo: %', v_probe;
  end if;
  v_probe := public.apply_pagbank_signup_probe(201, 'probe_criou_conta', true);
  if v_probe ->> 'enabled' is distinct from 'true' then
    raise exception 'um acidente desligou a flag já ligada';
  end if;

  perform set_config(
    'request.jwt.claim.sub', '7a333333-3333-4333-8333-333333333703', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_state := public.admin_disable_pagbank_signup();
  if v_state ->> 'api_enabled' is distinct from 'false'
    or v_state ->> 'held_off' is distinct from 'true'
    or v_state ->> 'unequivocal_streak' is distinct from '0'
  then
    raise exception 'o interruptor não travou: %', v_state;
  end if;
  set local role service_role;
  v_probe := public.apply_pagbank_signup_probe(400, '40001', true);
  perform public.apply_pagbank_signup_probe(400, '40002', true);
  v_probe := public.apply_pagbank_signup_probe(400, '40001', true);
  if v_probe ->> 'enabled' is distinct from 'false'
    or v_probe ->> 'changed' is distinct from 'false'
    or v_probe ->> 'held_off' is distinct from 'true'
    or v_probe ->> 'streak' is distinct from '0'
  then
    raise exception 'a sonda ligou com a trava: %', v_probe;
  end if;
  set local role authenticated;
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  v_state := public.admin_release_pagbank_signup_hold();
  if v_state ->> 'api_enabled' is distinct from 'true'
    or v_state ->> 'held_off' is distinct from 'false'
  then
    raise exception 'o admin não religou: %', v_state;
  end if;
end $$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.pagbank_signup_events
  where kind = 'probe_enabled' and code = '40002';
  if v_count <> 1 then
    raise exception 'evento de liberação: %', v_count;
  end if;
  if (
    select count(*)
    from public.pagbank_signup_events
    where kind = 'probe_confirming'
  ) <> 2 then
    raise exception 'a primeira sonda de cada par não ficou registrada';
  end if;
  if (
    select count(*)
    from public.pagbank_signup_events
    where kind = 'admin_release' and code = 'api_enabled'
  ) <> 1 then
    raise exception 'o religar manual não ficou registrado';
  end if;
  if exists (
    select 1
    from public.pagbank_signup_events
    where code ~ '[0-9]{11}' or kind like '%token%'
  ) then
    raise exception 'evento com dado pessoal';
  end if;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', '7a111111-1111-4111-8111-111111111701', true
  );
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  perform public.record_pagbank_signup_guide(
    '7a444444-4444-4444-8444-444444444704',
    'cpf',
    'ENTERTAINMENT'
  );
  raise exception 'guia manual com a API ligada';
exception
  when sqlstate 'P0001' then
    if sqlerrm <> 'modo_api' then
      raise;
    end if;
end $$;

do $$
begin
  set local role service_role;
  perform public.save_venue_pagbank_signup(
    '7a444444-4444-4444-8444-444444444704',
    'cnpj',
    'ENTERTAINMENT',
    'ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36',
    'pending_activation'
  );
  if public.venue_pagbank_account_id('7a444444-4444-4444-8444-444444444704')
    is distinct from 'ACCO_F74B8490-77C0-4F9C-88EA-E98735B4CB36'
  then
    raise exception 'o id ACCO_ não ficou';
  end if;
  begin
    perform public.save_venue_pagbank_signup(
      '7a444444-4444-4444-8444-444444444704',
      'cpf',
      'ENTERTAINMENT',
      '00123456797',
      'pending_activation'
    );
    raise exception 'CPF entrou como id de conta';
  exception
    when sqlstate 'P0001' then
      if sqlerrm <> 'conta' then
        raise;
      end if;
  end;
end $$;

do $$
declare
  v_gate jsonb;
begin
  set local role service_role;
  perform public.save_venue_pagbank_signup(
    '7a555555-5555-4555-8555-555555555705',
    'cnpj',
    'ENTERTAINMENT',
    null,
    'exists'
  );
  v_gate := public.venue_pagbank_signup_gate(
    '7a555555-5555-4555-8555-555555555705'
  );
  if v_gate ->> 'account_status' is distinct from 'exists'
    or v_gate ->> 'account_id' is not null
  then
    raise exception 'conta existente sem ACCO_ não ficou: %', v_gate;
  end if;
end $$;

do $$
begin
  perform private.invoke_pagbank_signup_probe();
  if not exists (
    select 1
    from public.pagbank_signup_events
    where code = 'config_ausente'
  ) then
    raise exception 'vault vazio não registrou a sonda';
  end if;
end $$;

select vault.create_secret(
  'https://evil.example/functions/v1/pagbank-signup-probe',
  'pagbank_signup_probe_url',
  'URL recusada. Não é produção.'
);

select vault.create_secret(
  'segredo-da-sonda-nao-vazar',
  'pagbank_signup_probe_secret',
  'Segredo de teste. Não é produção.'
);

do $$
begin
  perform private.invoke_pagbank_signup_probe();
  if not exists (
    select 1
    from public.pagbank_signup_events
    where code = 'probe_url_recusada'
  ) then
    raise exception 'URL fora do Supabase foi aceita';
  end if;
  if exists (
    select 1
    from public.pagbank_signup_events
    where code like '%segredo%'
      or kind like '%segredo%'
  ) then
    raise exception 'o segredo da sonda entrou no evento';
  end if;
end $$;

delete from vault.secrets
where name in ('pagbank_signup_probe_url', 'pagbank_signup_probe_secret');
