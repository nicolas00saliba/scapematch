-- Conta PagBank e documento por dono; reativar cidade (20261127190000).
-- Mesmo dono: a mesma conta PagBank recebe por várias cidades (com CNPJs
-- diferentes) e o mesmo CNPJ vale em várias cidades. Donos diferentes:
-- continua bloqueado. O dono reativa a cidade que removeu, no estado de
-- antes. Tudo desfeito no fim.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e3a11111-1111-4111-8111-111111111111', 'dono-conta@example.com', '{"display_name":"Dono"}'),
  ('e3a22222-2222-4222-8222-222222222222', 'outro-conta@example.com', '{"display_name":"Outro"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  -- a1 e a2: mesmo dono, CNPJs diferentes (como Curitiba e Cascavel).
  ('e3a11111-1111-4111-8111-1111111111a1', 'e3a11111-1111-4111-8111-111111111111',
   'curitiba', 'Minos Teste Curitiba', 'Centro', 'Rua A', '1', '80020010',
   -25.43, -49.27, 5000, 'cnpj', '27190000000101', '41977780001', 'approved'),
  ('e3a11111-1111-4111-8111-1111111111a2', 'e3a11111-1111-4111-8111-111111111111',
   'curitiba', 'Minos Teste Cascavel', 'Centro', 'Rua B', '2', '80020011',
   -25.43, -49.27, 5000, 'cnpj', '27190000000202', '41977780002', 'approved'),
  ('e3a22222-2222-4222-8222-2222222222b1', 'e3a22222-2222-4222-8222-222222222222',
   'curitiba', 'Casa De Outro Dono', 'Centro', 'Rua D', '4', '80020013',
   -25.43, -49.27, 5000, 'cnpj', '27190000000404', '41977780004', 'approved');

-- a1 conecta pelo PagBank (fluxo normal, service_role).
select public.connect_venue_pagbank(
  'e3a11111-1111-4111-8111-1111111111a1', 'e3a11111-1111-4111-8111-111111111111',
  'ACCO_E3A00000-0000-4000-8000-00000000A1A1', 'acc-e3a', 'ref-e3a',
  now() + interval '1 hour'
);

-- 1. O dono usa a conta de a1 em a2.
select set_config('request.jwt.claim.sub', 'e3a11111-1111-4111-8111-111111111111', true);
set local role authenticated;
do $$
declare
  v_out jsonb;
  v_sources integer;
begin
  select count(*) into v_sources
  from public.my_pagbank_share_sources('e3a11111-1111-4111-8111-1111111111a2')
  where venue_id = 'e3a11111-1111-4111-8111-1111111111a1' and account_last4 = 'A1A1';
  if v_sources <> 1 then raise exception 'a1 não apareceu como origem'; end if;

  -- Update direto não liga a conta.
  update public.venues
  set pagbank_account_id = 'ACCO_E3A00000-0000-4000-8000-00000000A1A1',
      pagbank_token_venue_id = 'e3a11111-1111-4111-8111-1111111111a1'
  where id = 'e3a11111-1111-4111-8111-1111111111a2';
  if exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a2'
      and (pagbank_account_id is not null or pagbank_token_venue_id is not null)
  ) then
    raise exception 'update direto ligou a conta';
  end if;

  v_out := public.share_venue_pagbank_account(
    'e3a11111-1111-4111-8111-1111111111a2', 'e3a11111-1111-4111-8111-1111111111a1'
  );
  if (v_out ->> 'shared')::boolean is not true or v_out ->> 'account_last4' <> 'A1A1' then
    raise exception 'share devolveu %', v_out;
  end if;
  -- Repetir não quebra.
  v_out := public.share_venue_pagbank_account(
    'e3a11111-1111-4111-8111-1111111111a2', 'e3a11111-1111-4111-8111-1111111111a1'
  );
  if (v_out ->> 'already')::boolean is not true then
    raise exception 'repetir o share devolveu %', v_out;
  end if;

  v_out := public.venue_pagbank_account_view('e3a11111-1111-4111-8111-1111111111a2');
  if (v_out ->> 'connected')::boolean is not true
    or (v_out ->> 'shared')::boolean is not true
    or v_out ->> 'account_last4' <> 'A1A1'
    or v_out::text ~ 'ACCO_'
  then
    raise exception 'a2 não mostra a conta compartilhada: %', v_out;
  end if;

  -- Já tem conta: não oferece de novo.
  if exists (
    select 1 from public.my_pagbank_share_sources('e3a11111-1111-4111-8111-1111111111a2')
  ) then
    raise exception 'ofereceu conta para cidade que já tem';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 2. O token é lido pela unidade dona do token; nada foi copiado.
do $$
declare
  v_access text;
begin
  select access_token into v_access
  from public.read_venue_pagbank_tokens('e3a11111-1111-4111-8111-1111111111a2');
  if v_access is distinct from 'acc-e3a' then
    raise exception 'a2 não lê o token de a1';
  end if;
  if exists (
    select 1 from public.venue_pagbank_tokens
    where venue_id = 'e3a11111-1111-4111-8111-1111111111a2'
  ) then
    raise exception 'token foi copiado para a2';
  end if;
  -- Renovar por a2 grava em a1.
  perform public.store_venue_pagbank_tokens(
    'e3a11111-1111-4111-8111-1111111111a2', 'acc-e3a-2', 'ref-e3a-2',
    now() + interval '2 hours'
  );
  select access_token into v_access
  from public.read_venue_pagbank_tokens('e3a11111-1111-4111-8111-1111111111a1');
  if v_access is distinct from 'acc-e3a-2' then
    raise exception 'renovar por a2 não chegou em a1';
  end if;
  if public.venue_pagbank_binding('e3a11111-1111-4111-8111-1111111111a2') ->> 'state'
    is distinct from 'ok'
  then
    raise exception 'binding de a2 devia ser ok';
  end if;
end $$;

-- 3. Outro dono não usa a conta.
do $$
declare
  v_ok boolean := false;
  v_msg text;
begin
  begin
    perform public.connect_venue_pagbank(
      'e3a22222-2222-4222-8222-2222222222b1', 'e3a22222-2222-4222-8222-222222222222',
      'ACCO_E3A00000-0000-4000-8000-00000000A1A1', 'acc-b', 'ref-b',
      now() + interval '1 hour'
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_in_use';
  end;
  if not v_ok then raise exception 'outro dono conectou a mesma conta'; end if;

  -- Nem gravando direto (gatilho).
  v_ok := false;
  begin
    update public.venues
    set pagbank_account_id = 'ACCO_E3A00000-0000-4000-8000-00000000A1A1'
    where id = 'e3a22222-2222-4222-8222-2222222222b1';
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_in_use';
  end;
  if not v_ok then raise exception 'gatilho deixou outro dono usar a conta'; end if;
end $$;

select set_config('request.jwt.claim.sub', 'e3a22222-2222-4222-8222-222222222222', true);
set local role authenticated;
do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.share_venue_pagbank_account(
      'e3a22222-2222-4222-8222-2222222222b1', 'e3a11111-1111-4111-8111-1111111111a1'
    );
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'outro dono compartilhou a conta'; end if;

  v_ok := false;
  begin
    perform * from public.my_pagbank_share_sources('e3a11111-1111-4111-8111-1111111111a2');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'outro dono listou as origens'; end if;

  -- 4. Documento: outro dono não repete o CNPJ.
  v_ok := false;
  begin
    insert into public.venues (
      city_id, name, neighborhood, street_address, address_number,
      postal_code, latitude, longitude, income_value, document_kind,
      document_number, phone
    ) values (
      'curitiba', 'Copia De Outro', 'Centro', 'Rua E', '5', '80020014',
      -25.43, -49.27, 5000, 'cnpj', '27190000000101', '41977780005'
    );
  exception when unique_violation then
    v_ok := sqlerrm = 'duplicate document';
  end;
  if not v_ok then raise exception 'outro dono repetiu o CNPJ'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 4b. O mesmo dono repete o CNPJ em outra cidade. Com o login do dono, o
-- guard grava owner_id = dono e status = pending, como no app.
select set_config('request.jwt.claim.sub', 'e3a11111-1111-4111-8111-111111111111', true);
insert into public.venues (
  id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone
) values (
  'e3a11111-1111-4111-8111-1111111111a3',
  'curitiba', 'Minos Teste Terceira', 'Centro', 'Rua C', '3', '80020012',
  -25.43, -49.27, 5000, 'cnpj', '27190000000101', '41977780003'
);
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  if not exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a3'
      and owner_id = 'e3a11111-1111-4111-8111-111111111111'
      and status = 'pending'
  ) then
    raise exception 'o mesmo dono não repetiu o CNPJ';
  end if;
end $$;

-- 5. Desconectar: a origem não solta enquanto outra cidade usa a conta; a
-- cidade que usa só solta a ligação e o token continua em a1.
do $$
declare
  v_ok boolean := false;
  v_msg text;
  v_out jsonb;
begin
  begin
    perform public.disconnect_venue_pagbank(
      'e3a11111-1111-4111-8111-1111111111a1', 'e3a11111-1111-4111-8111-111111111111', true
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_shared';
  end;
  if not v_ok then raise exception 'origem desconectou com cidade usando a conta'; end if;

  v_out := public.disconnect_venue_pagbank(
    'e3a11111-1111-4111-8111-1111111111a2', 'e3a11111-1111-4111-8111-111111111111', true
  );
  if (v_out ->> 'shared')::boolean is not true
    or (v_out ->> 'disconnected')::boolean is not true
  then
    raise exception 'desconectar a2 devolveu %', v_out;
  end if;
  if exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a2'
      and (pagbank_account_id is not null or pagbank_token_venue_id is not null)
  ) then
    raise exception 'a2 ficou com a conta';
  end if;
  if not exists (
    select 1 from public.venue_pagbank_tokens
    where venue_id = 'e3a11111-1111-4111-8111-1111111111a1'
  ) then
    raise exception 'desconectar a2 apagou o token de a1';
  end if;

  v_out := public.disconnect_venue_pagbank(
    'e3a11111-1111-4111-8111-1111111111a1', 'e3a11111-1111-4111-8111-111111111111', true
  );
  if (v_out ->> 'disconnected')::boolean is not true or v_out ? 'shared' then
    raise exception 'desconectar a1 devolveu %', v_out;
  end if;
end $$;

-- 6. Reativar: a cidade volta como estava.
reset role;
select set_config('request.jwt.claim.sub', '', true);
update public.venues set suspended_at = now() - interval '1 day'
where id = 'e3a11111-1111-4111-8111-1111111111a2';  -- suspensa pelo Admin antes
select set_config('request.jwt.claim.sub', 'e3a11111-1111-4111-8111-111111111111', true);
set local role authenticated;
do $$
declare
  v_out jsonb;
begin
  perform public.deactivate_my_unit('e3a11111-1111-4111-8111-1111111111a3');
  perform public.deactivate_my_unit('e3a11111-1111-4111-8111-1111111111a2');

  -- Update direto não reativa.
  update public.venues set deactivated_at = null, suspended_at = null
  where id = 'e3a11111-1111-4111-8111-1111111111a3';
  if not exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a3' and deactivated_at is not null
  ) then
    raise exception 'update direto reativou';
  end if;

  v_out := public.reactivate_my_unit('e3a11111-1111-4111-8111-1111111111a3');
  if v_out ->> 'status' <> 'pending' then
    raise exception 'reativar devolveu %', v_out;
  end if;
  if not exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a3'
      and status = 'pending'
      and deactivated_at is null
      and suspended_at is null
  ) then
    raise exception 'pendente não voltou em análise e visível no Parceiro';
  end if;

  perform public.reactivate_my_unit('e3a11111-1111-4111-8111-1111111111a2');
  if not exists (
    select 1 from public.venues
    where id = 'e3a11111-1111-4111-8111-1111111111a2'
      and status = 'approved'
      and deactivated_at is null
      and suspended_at is not null
  ) then
    raise exception 'suspensa pelo Admin não continuou suspensa';
  end if;

  -- Repetir não quebra.
  v_out := public.reactivate_my_unit('e3a11111-1111-4111-8111-1111111111a3');
  if (v_out ->> 'already')::boolean is not true then
    raise exception 'repetir reativar devolveu %', v_out;
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Aprovada sem suspensão: volta para o jogador.
select set_config('request.jwt.claim.sub', 'e3a11111-1111-4111-8111-111111111111', true);
set local role authenticated;
select public.deactivate_my_unit('e3a11111-1111-4111-8111-1111111111a1');
select public.reactivate_my_unit('e3a11111-1111-4111-8111-1111111111a1');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  if not exists (
    select 1 from public.venues where id = 'e3a11111-1111-4111-8111-1111111111a1'
  ) then
    raise exception 'aprovada reativada não voltou para o jogador';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Outro dono não reativa.
select set_config('request.jwt.claim.sub', 'e3a11111-1111-4111-8111-111111111111', true);
set local role authenticated;
select public.deactivate_my_unit('e3a11111-1111-4111-8111-1111111111a3');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.sub', 'e3a22222-2222-4222-8222-222222222222', true);
set local role authenticated;
do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.reactivate_my_unit('e3a11111-1111-4111-8111-1111111111a3');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'outro dono reativou'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- anon não chama as funções novas.
do $$
begin
  if has_function_privilege('anon', 'public.share_venue_pagbank_account(uuid,uuid)', 'execute')
    or has_function_privilege('anon', 'public.reactivate_my_unit(uuid)', 'execute')
    or has_function_privilege('anon', 'public.my_pagbank_share_sources(uuid)', 'execute')
  then
    raise exception 'anon executa função nova';
  end if;
end $$;

rollback;
