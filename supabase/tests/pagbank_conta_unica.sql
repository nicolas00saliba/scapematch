-- Uma conta PagBank por casa, gravada no servidor.
-- Dois logins da mesma casa (dois aparelhos) veem a mesma conta; uma segunda
-- conta é recusada (PB409); trocar é desconectar e conectar de novo; o
-- repasse confere conta e token e marca ambiguidade sem escolher.
-- Conta e documento só saem mascarados.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('d1000001-0000-4000-8000-000000000001', 'unica-dono@example.com', '{"display_name":"Dono Unica"}'),
  ('d1000001-0000-4000-8000-000000000002', 'unica-estranho@example.com', '{"display_name":"Estranho"}'),
  ('d1000001-0000-4000-8000-000000000003', 'unica-admin@example.com', '{"display_name":"Admin Unica"}');

insert into public.admins (user_id)
values ('d1000001-0000-4000-8000-000000000003');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'd2000001-0000-4000-8000-000000000001',
  'd1000001-0000-4000-8000-000000000001',
  'curitiba', 'Casa Unica', 'Centro', 'Rua da Conta', '11', '80010011',
  -25.43, -49.27, 5000, 'cnpj', '19000000000195', '41900001119', 'approved'
);

-- 1. Conecta: conta e token mudam juntos e ficam na casa.
do $$
declare
  v_out jsonb;
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
begin
  v_out := public.connect_venue_pagbank(
    v_venue, 'd1000001-0000-4000-8000-000000000001',
    'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA', 'acc-1', 'ref-1',
    now() + interval '1 hour'
  );
  if v_out ->> 'account_last4' is distinct from '13CA'
    or (v_out ->> 'renewed')::boolean
  then
    raise exception 'conectar devolveu %', v_out;
  end if;
  if (select pagbank_account_id from public.venues where id = v_venue)
    is distinct from 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
  then
    raise exception 'a conta não ficou na casa';
  end if;
  if (select account_id from public.venue_pagbank_tokens where venue_id = v_venue)
    is distinct from 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
  then
    raise exception 'o token não guardou a conta';
  end if;
  if public.venue_pagbank_binding(v_venue) ->> 'state' is distinct from 'ok' then
    raise exception 'binding devia ser ok';
  end if;
  if (select count(*) from public.admin_audit_log
      where action = 'connect_pagbank' and target_id = v_venue::text) <> 1
  then
    raise exception 'sem auditoria do connect';
  end if;
  if (select (after_state ->> 'account_last4') from public.admin_audit_log
      where action = 'connect_pagbank' and target_id = v_venue::text) <> '13CA'
    or (select after_state::text from public.admin_audit_log
        where action = 'connect_pagbank' and target_id = v_venue::text) ~ 'ACCO_'
  then
    raise exception 'a auditoria do connect guardou conta inteira';
  end if;
end $$;

-- 2. Dois logins da mesma casa (dois aparelhos, sessões diferentes) leem a
-- mesma conta, mascarada. Estranho não lê. Admin lê só com aal2.
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_phone jsonb;
  v_laptop jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'd1000001-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  perform set_config('request.jwt.claim.session_id', 'aparelho-celular', true);
  set local role authenticated;
  v_phone := public.venue_pagbank_account_view(v_venue);
  perform set_config('request.jwt.claim.session_id', 'aparelho-notebook', true);
  v_laptop := public.venue_pagbank_account_view(v_venue);
  reset role;
  if v_phone is distinct from v_laptop then
    raise exception 'os dois logins não veem a mesma conta: % / %', v_phone, v_laptop;
  end if;
  if v_phone ->> 'connected' <> 'true'
    or v_phone ->> 'house_name' <> 'Casa Unica'
    or v_phone ->> 'bank' <> 'PagBank'
    or v_phone ->> 'account_last4' <> '13CA'
    or v_phone ->> 'document_masked' <> '**.***.***/****-95'
    or v_phone ->> 'verified' <> 'true'
    or v_phone ->> 'can_disconnect' <> 'true'
  then
    raise exception 'a conta mostrada saiu errada: %', v_phone;
  end if;
  if v_phone::text ~ 'ACCO_|19000000000195' then
    raise exception 'a tela recebeu conta ou documento inteiro: %', v_phone;
  end if;
end $$;

do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_ok boolean := false;
begin
  perform set_config('request.jwt.claim.sub', 'd1000001-0000-4000-8000-000000000002', true);
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  begin
    perform public.venue_pagbank_account_view(v_venue);
  exception when others then
    v_ok := sqlerrm = 'not owner';
  end;
  reset role;
  if not v_ok then raise exception 'estranho leu a conta da casa'; end if;

  v_ok := false;
  perform set_config('request.jwt.claim.sub', 'd1000001-0000-4000-8000-000000000003', true);
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  begin
    perform public.venue_pagbank_account_view(v_venue);
  exception when others then
    v_ok := sqlerrm = 'not owner';
  end;
  reset role;
  if not v_ok then raise exception 'admin sem aal2 leu a conta'; end if;

  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  if public.venue_pagbank_account_view(v_venue) ->> 'account_last4' <> '13CA' then
    raise exception 'admin aal2 não leu a conta';
  end if;
  reset role;
end $$;

-- 3. Segunda conta diferente: recusada, nada muda. Mesma conta só renova.
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_state text;
  v_msg text;
  v_out jsonb;
begin
  begin
    perform public.connect_venue_pagbank(
      v_venue, 'd1000001-0000-4000-8000-000000000001',
      'ACCO_BBBBBBBB-0000-4000-8000-000000009999', 'acc-2', 'ref-2',
      now() + interval '1 hour'
    );
    raise exception 'a segunda conta foi aceita';
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'pagbank_account_exists' then
      raise exception 'mensagem do 409: %', v_msg;
    end if;
  end;
  if (select pagbank_account_id from public.venues where id = v_venue)
    <> 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
    or (select account_id from public.venue_pagbank_tokens where venue_id = v_venue)
    <> 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
  then
    raise exception 'a recusa mexeu na conta ou no token';
  end if;
  if (select count(*) from public.venue_pagbank_tokens where venue_id = v_venue) <> 1 then
    raise exception 'mais de um token para a casa';
  end if;

  v_out := public.connect_venue_pagbank(
    v_venue, 'd1000001-0000-4000-8000-000000000001',
    'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA', 'acc-3', 'ref-3',
    now() + interval '2 hours'
  );
  if not (v_out ->> 'renewed')::boolean then
    raise exception 'mesma conta devia só renovar';
  end if;
end $$;

-- 4. O banco recusa trocar a conta por UPDATE direto e token de outra conta.
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_ok boolean := false;
begin
  begin
    update public.venues
    set pagbank_account_id = 'ACCO_CCCCCCCC-0000-4000-8000-000000007777'
    where id = v_venue;
  exception when sqlstate 'PB409' then
    v_ok := true;
  end;
  if not v_ok then raise exception 'update direto trocou a conta'; end if;

  v_ok := false;
  begin
    update public.venue_pagbank_tokens
    set account_id = 'ACCO_CCCCCCCC-0000-4000-8000-000000007777'
    where venue_id = v_venue;
  exception when sqlstate 'PB409' then
    v_ok := true;
  end;
  if not v_ok then raise exception 'token de outra conta foi aceito'; end if;
end $$;

-- 5. Ambiguidade: o binding marca e o repasse para. Os estados são forçados
-- sem os triggers, só aqui, e desfeitos em seguida.
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
begin
  set local session_replication_role = replica;
  update public.venue_pagbank_tokens
  set account_id = 'ACCO_CCCCCCCC-0000-4000-8000-000000007777'
  where venue_id = v_venue;
  if public.venue_pagbank_binding(v_venue) ->> 'state' <> 'ambiguous'
    or public.venue_pagbank_binding(v_venue) ->> 'reason' <> 'tokens_other_account'
  then
    raise exception 'token de outra conta não ficou ambíguo: %',
      public.venue_pagbank_binding(v_venue);
  end if;
  if public.venue_pagbank_binding(v_venue)::text ~ 'ACCO_' then
    raise exception 'o binding devolveu conta';
  end if;
  update public.venue_pagbank_tokens
  set account_id = null
  where venue_id = v_venue;
  if public.venue_pagbank_binding(v_venue) ->> 'state' <> 'unverified' then
    raise exception 'token antigo devia ser unverified';
  end if;
  update public.venues set pagbank_account_id = null where id = v_venue;
  if public.venue_pagbank_binding(v_venue) ->> 'reason' <> 'tokens_without_account' then
    raise exception 'token sem conta devia ser ambíguo';
  end if;
  update public.venues
  set pagbank_account_id = 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
  where id = v_venue;
  update public.venue_pagbank_tokens
  set account_id = 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
  where venue_id = v_venue;
  set local session_replication_role = origin;
  if public.venue_pagbank_binding(v_venue) ->> 'state' <> 'ok' then
    raise exception 'não voltou ao normal';
  end if;
end $$;

-- 6. Desconectar: estranho não; dinheiro a caminho trava; depois libera.
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_owner constant uuid := 'd1000001-0000-4000-8000-000000000001';
  v_ok boolean := false;
  v_out jsonb;
  v_view jsonb;
begin
  begin
    perform public.disconnect_venue_pagbank(
      v_venue, 'd1000001-0000-4000-8000-000000000002', false
    );
  exception when others then
    v_ok := sqlerrm = 'not owner';
  end;
  if not v_ok then raise exception 'estranho desconectou a casa'; end if;

  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key, external_reference
  ) values (
    'd3000001-0000-4000-8000-000000000001', v_venue, 1000, 'pending',
    'manual', 'manual:teste-unica', 'ref-unica-1'
  );
  v_ok := false;
  begin
    perform public.disconnect_venue_pagbank(v_venue, v_owner, false);
  exception when sqlstate 'PB409' then
    v_ok := sqlerrm = 'pagbank_in_flight';
  end;
  if not v_ok then raise exception 'desconectou com saque pendente'; end if;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  v_view := public.venue_pagbank_account_view(v_venue);
  reset role;
  -- A função roda com a chave de serviço, sem usuário na sessão.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.aal', '', true);
  if v_view ->> 'can_disconnect' <> 'false' then
    raise exception 'a tela devia saber que há dinheiro a caminho';
  end if;
  if (select pagbank_account_id from public.venues where id = v_venue) is null then
    raise exception 'a recusa apagou a conta';
  end if;
  update public.venue_withdrawals set status = 'done'
  where id = 'd3000001-0000-4000-8000-000000000001';

  v_out := public.disconnect_venue_pagbank(v_venue, v_owner, false);
  if not (v_out ->> 'disconnected')::boolean or v_out ->> 'account_last4' <> '13CA' then
    raise exception 'desconectar devolveu %', v_out;
  end if;
  if (select pagbank_account_id from public.venues where id = v_venue) is not null
    or exists (select 1 from public.venue_pagbank_tokens where venue_id = v_venue)
  then
    raise exception 'a casa ficou com conta ou token';
  end if;
  if public.venue_pagbank_binding(v_venue) ->> 'state' <> 'none' then
    raise exception 'casa sem conta devia ser none';
  end if;
  if not exists (
    select 1 from public.admin_audit_log
    where action = 'disconnect_pagbank' and target_id = v_venue::text
      and before_state ->> 'account_last4' = '13CA'
  ) then
    raise exception 'sem auditoria do disconnect';
  end if;
  if (select string_agg(before_state::text || after_state::text, '')
      from public.admin_audit_log where target_id = v_venue::text) ~ 'ACCO_'
  then
    raise exception 'a auditoria guardou conta inteira';
  end if;
end $$;

-- 7. Depois de desconectar, a conta conectada em seguida é a que recebe o
-- repasse da casa (venue_payout_wallet e venue_finance_ready leem o servidor).
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
begin
  if public.venue_payout_wallet(v_venue) is not null then
    raise exception 'casa sem conta ainda tem wallet';
  end if;
  perform public.connect_venue_pagbank(
    v_venue, 'd1000001-0000-4000-8000-000000000001',
    'ACCO_BBBBBBBB-0000-4000-8000-000000009999', 'acc-4', 'ref-4',
    now() + interval '1 hour'
  );
  if public.venue_payout_wallet(v_venue)
    is distinct from 'ACCO_BBBBBBBB-0000-4000-8000-000000009999'
  then
    raise exception 'o repasse não aponta para a conta nova';
  end if;
  if public.venue_pagbank_binding(v_venue) ->> 'state' <> 'ok' then
    raise exception 'conta nova devia conferir com o token';
  end if;
  -- e segue única
  begin
    perform public.connect_venue_pagbank(
      v_venue, 'd1000001-0000-4000-8000-000000000001',
      'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA', 'acc-5', 'ref-5',
      now() + interval '1 hour'
    );
    raise exception 'a conta antiga voltou por cima da nova';
  exception when sqlstate 'PB409' then
    null;
  end;
end $$;

-- 8. Só service_role chama conectar, desconectar e conferir.
do $$
declare
  v_fn text;
begin
  foreach v_fn in array array[
    'public.connect_venue_pagbank(uuid, uuid, text, text, text, timestamptz)',
    'public.disconnect_venue_pagbank(uuid, uuid, boolean)',
    'public.venue_pagbank_binding(uuid)'
  ] loop
    if has_function_privilege('authenticated', v_fn, 'execute')
      or has_function_privilege('anon', v_fn, 'execute')
    then
      raise exception 'authenticated ou anon executa %', v_fn;
    end if;
    if not has_function_privilege('service_role', v_fn, 'execute') then
      raise exception 'service_role não executa %', v_fn;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.venue_pagbank_account_view(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.venue_pagbank_account_view(uuid)', 'execute')
  then
    raise exception 'grant da leitura da conta saiu errado';
  end if;
end $$;

-- 9. A mesma conta não liga a duas casas reais (409). Casa de teste fica de fora.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('d1000001-0000-4000-8000-000000000004', 'unica-dono2@example.com', '{"display_name":"Dono Dois"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'd2000001-0000-4000-8000-000000000002',
  'd1000001-0000-4000-8000-000000000004',
  'curitiba', 'Casa Dois', 'Centro', 'Rua Dois', '22', '80010022',
  -25.43, -49.27, 5000, 'cnpj', '45723174000110', '41900001120', 'approved'
);

do $$
declare
  v_two constant uuid := 'd2000001-0000-4000-8000-000000000002';
  v_msg text;
  v_ok boolean := false;
begin
  begin
    perform public.connect_venue_pagbank(
      v_two, 'd1000001-0000-4000-8000-000000000004',
      'ACCO_BBBBBBBB-0000-4000-8000-000000009999', 'acc-6', 'ref-6',
      now() + interval '1 hour'
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_in_use';
  end;
  if not v_ok then raise exception 'a mesma conta ligou a duas casas'; end if;
  if (select pagbank_account_id from public.venues where id = v_two) is not null
    or exists (select 1 from public.venue_pagbank_tokens where venue_id = v_two)
  then
    raise exception 'a recusa deixou rastro na segunda casa';
  end if;
end $$;

-- 10. Casa sem split ou já liquidada não trava o desconectar; com split e
-- custódia aberta trava; reserva aberta trava. O trigger recusa reserva
-- com a conta velha (corrida com o disconnect).
do $$
declare
  v_venue constant uuid := 'd2000001-0000-4000-8000-000000000001';
  v_owner constant uuid := 'd1000001-0000-4000-8000-000000000001';
  v_wallet constant text := 'ACCO_BBBBBBBB-0000-4000-8000-000000009999';
  v_ok boolean;
  v_msg text;
begin
  set local session_replication_role = replica;
  alter table public.payment_charges enable always trigger charge_wallet_matches_venue;

  -- paga sem split: não conta
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, wallet_id, paid_at
  ) values (
    'd4000001-0000-4000-8000-000000000001', gen_random_uuid(), gen_random_uuid(),
    v_venue, 5000, 'PIX', 'paid', 'unica-sem-split', 2500, v_wallet, now()
  );
  -- paga com split, mas já liquidada: não conta
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, wallet_id, paid_at, provider_split_id,
    custody_released_at
  ) values (
    'd4000001-0000-4000-8000-000000000002', gen_random_uuid(), gen_random_uuid(),
    v_venue, 5000, 'PIX', 'paid', 'unica-liquidada', 2500, v_wallet, now(),
    'SPLI_X', now()
  );
  -- pendente velha: não conta
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, wallet_id, created_at
  ) values (
    'd4000001-0000-4000-8000-000000000003', gen_random_uuid(), gen_random_uuid(),
    v_venue, 5000, 'PIX', 'pending', 'unica-velha', 2500, v_wallet,
    now() - interval '3 days'
  );
  if private.venue_pagbank_in_flight(v_venue) <> 0 then
    raise exception 'cobrança sem split, liquidada ou velha trava a troca: %',
      private.venue_pagbank_in_flight(v_venue);
  end if;

  -- paga com split e custódia aberta: conta
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, wallet_id, paid_at, provider_split_id
  ) values (
    'd4000001-0000-4000-8000-000000000004', gen_random_uuid(), gen_random_uuid(),
    v_venue, 5000, 'PIX', 'paid', 'unica-aberta', 2500, v_wallet, now(),
    'SPLI_Y'
  );
  if private.venue_pagbank_in_flight(v_venue) <> 1 then
    raise exception 'custódia aberta devia contar';
  end if;
  v_ok := false;
  begin
    perform public.disconnect_venue_pagbank(v_venue, v_owner, false);
  exception when sqlstate 'PB409' then
    v_ok := sqlerrm = 'pagbank_in_flight';
  end;
  if not v_ok then raise exception 'desconectou com custódia aberta'; end if;
  update public.payment_charges
  set custody_released_at = now()
  where id = 'd4000001-0000-4000-8000-000000000004';

  -- reserva com a conta velha é recusada, a com a conta atual passa
  v_ok := false;
  begin
    insert into public.payment_charges (
      group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, commission_bps, wallet_id
    ) values (
      gen_random_uuid(), gen_random_uuid(), v_venue, 5000, 'PIX', 'creating',
      'unica-conta-velha', 2500, 'ACCO_AAAAAAAA-0000-4000-8000-0000000013CA'
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_changed';
  end;
  if not v_ok then raise exception 'reserva com a conta velha foi aceita'; end if;

  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, commission_bps, wallet_id
  ) values (
    'd4000001-0000-4000-8000-000000000005', gen_random_uuid(), gen_random_uuid(),
    v_venue, 5000, 'PIX', 'creating', 'unica-conta-atual', 2500, v_wallet
  );
  if private.venue_pagbank_in_flight(v_venue) <> 1 then
    raise exception 'reserva aberta devia contar';
  end if;
  v_ok := false;
  begin
    perform public.disconnect_venue_pagbank(v_venue, v_owner, false);
  exception when sqlstate 'PB409' then
    v_ok := sqlerrm = 'pagbank_in_flight';
  end;
  if not v_ok then raise exception 'desconectou com reserva aberta'; end if;
  update public.payment_charges set status = 'cancelled'
  where id = 'd4000001-0000-4000-8000-000000000005';

  -- desconectado: reserva com qualquer conta é recusada
  perform public.disconnect_venue_pagbank(v_venue, v_owner, false);
  v_ok := false;
  begin
    insert into public.payment_charges (
      group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, commission_bps, wallet_id
    ) values (
      gen_random_uuid(), gen_random_uuid(), v_venue, 5000, 'PIX', 'creating',
      'unica-sem-conta', 2500, v_wallet
    );
  exception when sqlstate 'PB409' then
    v_ok := true;
  end;
  if not v_ok then raise exception 'reserva em casa sem conta foi aceita'; end if;

  alter table public.payment_charges enable trigger charge_wallet_matches_venue;
  set local session_replication_role = origin;
end $$;
