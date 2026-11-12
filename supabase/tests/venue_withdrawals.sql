-- Saque da casa: RLS, titularidade, bloqueio de 24h e um automático por período.
-- Roda depois das migrations. Não fala com o Asaas.

\set ON_ERROR_STOP on

do $$
declare
  v_name text;
  v_hidden text[] := array[
    'public.save_venue_bank_account(uuid,uuid,text,text,text,text,text,text,text,text,text,text)',
    'public.save_venue_payout_schedule(uuid,uuid,boolean,text,integer,integer)',
    'public.claim_venue_withdrawal(uuid,uuid,text,text,integer,integer)',
    'public.begin_withdrawal_dispatch(uuid)',
    'public.attach_venue_transfer(uuid,text,text,text)',
    'public.fail_venue_withdrawal(uuid,text)',
    'public.apply_transfer_event(text,text,text,text,text)',
    'public.list_due_venue_payouts()',
    'public.venue_payout_wallet(uuid)',
    'public.venue_bank_for_transfer(uuid)',
    'public.venue_payout_snapshot(uuid,uuid,boolean)'
  ];
begin
  if public.venue_payouts_enabled() then
    raise exception 'a flag de saque nasceu ligada';
  end if;
  foreach v_name in array v_hidden loop
    if has_function_privilege('authenticated', v_name, 'execute')
      or has_function_privilege('anon', v_name, 'execute')
    then
      raise exception 'authenticated ou anon executa %', v_name;
    end if;
    if not has_function_privilege('service_role', v_name, 'execute') then
      raise exception 'service_role perdeu %', v_name;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.my_venue_payouts(uuid)', 'execute')
    or has_function_privilege('anon', 'public.my_venue_payouts(uuid)', 'execute')
    or not has_function_privilege(
      'authenticated', 'public.admin_list_venue_withdrawals()', 'execute'
    )
  then
    raise exception 'grants de leitura de saque saíram do combinado';
  end if;
end $$;

insert into auth.users (id, email)
values
  ('a1111111-1111-4111-8111-111111111111', 'dona-saque@example.com'),
  ('a2222222-2222-4222-8222-222222222222', 'socio-saque@example.com'),
  ('a3333333-3333-4333-8333-333333333333', 'equipe-saque@example.com'),
  ('a4444444-4444-4444-8444-444444444444', 'outra-saque@example.com'),
  ('a5555555-5555-4555-8555-555555555555', 'admin-saque@example.com');

insert into public.admins (user_id)
values ('a5555555-5555-4555-8555-555555555555');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, asaas_wallet_id
) values
  (
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'curitiba', 'Casa do Saque', 'Centro', 'Rua do Pix', '10',
    '80010000', -25.43, -49.27, 8000, 'cnpj', '55667788000199',
    '41988880011', 'approved', 'wal_casa_saque'
  ),
  (
    'b2222222-2222-4222-8222-222222222222',
    'a4444444-4444-4444-8444-444444444444',
    'curitiba', 'Outra Casa', 'Batel', 'Rua Dois', '20',
    '80020000', -25.44, -49.28, 8000, 'cnpj', '66778899000100',
    '41988880022', 'approved', 'wal_outra_casa'
  );

insert into public.venue_staff (venue_id, user_id, role, status, accepted_at)
values
  (
    'b1111111-1111-4111-8111-111111111111',
    'a2222222-2222-4222-8222-222222222222',
    'partner', 'accepted', pg_catalog.now()
  ),
  (
    'b1111111-1111-4111-8111-111111111111',
    'a3333333-3333-4333-8333-333333333333',
    'staff', 'accepted', pg_catalog.now()
  );

do $$
begin
  perform public.save_venue_bank_account(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'pix', '55667788000199', 'CNPJ', null, null, null, null,
    'Casa do Saque', '55667788000199', 'PIX'
  );
  raise exception 'salvou conta com a flag desligada';
exception
  when others then
    if sqlerrm <> 'saques desligados' then
      raise;
    end if;
end $$;

update public.venue_payouts_settings set enabled = true where id = 1;

do $$
begin
  perform public.save_venue_bank_account(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'pix', '39053344705', 'CPF', null, null, null, null,
    'Pessoa Errada', '39053344705', 'PIX'
  );
  raise exception 'aceitou titularidade diferente';
exception
  when others then
    if sqlerrm <> 'titularidade' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.save_venue_bank_account(
    'b1111111-1111-4111-8111-111111111111',
    'a3333333-3333-4333-8333-333333333333',
    'pix', '55667788000199', 'CNPJ', null, null, null, null,
    'Casa do Saque', '55667788000199', 'PIX'
  );
  raise exception 'equipe gravou a conta';
exception
  when others then
    if sqlerrm <> 'not owner' then
      raise;
    end if;
end $$;

select public.save_venue_bank_account(
  'b1111111-1111-4111-8111-111111111111',
  'a2222222-2222-4222-8222-222222222222',
  'pix', '55.667.788/0001-99', 'CNPJ', null, null, null, null,
  'Casa do Saque', '55.667.788/0001-99', 'PIX'
);

do $$
declare
  v_blocked timestamptz;
  v_key text;
begin
  select withdrawals_blocked_until, pix_key
    into v_blocked, v_key
  from public.venue_bank_accounts
  where venue_id = 'b1111111-1111-4111-8111-111111111111';
  if v_key <> '55667788000199' then
    raise exception 'a chave pix nao ficou so com digitos';
  end if;
  if v_blocked is null or v_blocked < pg_catalog.now() + interval '23 hours' then
    raise exception 'trocar a conta nao bloqueou 24h';
  end if;
  if not exists (
    select 1 from public.venue_payout_audit
    where venue_id = 'b1111111-1111-4111-8111-111111111111'
      and actor_id = 'a2222222-2222-4222-8222-222222222222'
      and action = 'save_bank_account'
      and summary = 'destino pix'
  ) then
    raise exception 'a auditoria nao registrou quem trocou a conta';
  end if;
  if exists (
    select 1 from public.venue_payout_audit
    where summary like '%55667788000199%'
  ) then
    raise exception 'a auditoria guardou a chave';
  end if;
  if not exists (
    select 1 from public.venue_payout_notices
    where venue_id = 'b1111111-1111-4111-8111-111111111111'
      and owner_id = 'a1111111-1111-4111-8111-111111111111'
      and kind = 'bank_changed'
      and sent_at is null
  ) then
    raise exception 'o dono nao foi avisado da troca';
  end if;
end $$;

do $$
begin
  perform public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 1000, 5000
  );
  raise exception 'sacou dentro do bloqueio';
exception
  when others then
    if sqlerrm <> 'bloqueado' then
      raise;
    end if;
end $$;

update public.venue_bank_accounts
set withdrawals_blocked_until = pg_catalog.now() - interval '1 minute'
where venue_id = 'b1111111-1111-4111-8111-111111111111';

do $$
declare
  v_kept timestamptz;
  v_notice uuid;
begin
  select withdrawals_blocked_until into v_kept
  from public.venue_bank_accounts
  where venue_id = 'b1111111-1111-4111-8111-111111111111';
  v_notice := public.save_venue_bank_account(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'pix', '55667788000199', 'CNPJ', null, null, null, null,
    'Casa do Saque', '55667788000199', 'PIX'
  );
  if v_notice is not null then
    raise exception 'gravar a mesma conta gerou aviso';
  end if;
  if (
    select withdrawals_blocked_until
    from public.venue_bank_accounts
    where venue_id = 'b1111111-1111-4111-8111-111111111111'
  ) is distinct from v_kept then
    raise exception 'a mesma conta reiniciou o bloqueio';
  end if;
end $$;

do $$
declare
  v_first jsonb;
  v_second jsonb;
  v_count integer;
begin
  v_first := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', 'auto:2026-11-12', 4000, 9000
  );
  perform public.save_venue_payout_schedule(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    true, 'daily', null, 1000
  );
  if v_first is not null then
    raise exception 'automatico sem agenda criou saque';
  end if;
exception
  when others then
    if sqlerrm <> 'agenda' then
      raise;
    end if;
end $$;

select public.save_venue_payout_schedule(
  'b1111111-1111-4111-8111-111111111111',
  'a1111111-1111-4111-8111-111111111111',
  true, 'daily', null, 1000
);

do $$
declare
  v_first jsonb;
  v_second jsonb;
  v_count integer;
  v_dispatch boolean;
begin
  v_first := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', 'auto:2026-11-12', 4000, 9000
  );
  v_second := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', 'auto:2026-11-12', 4000, 9000
  );
  if v_first ->> 'fresh' <> 'true' or v_second ->> 'fresh' <> 'false' then
    raise exception 'o segundo automatico do periodo nao reaproveitou a linha';
  end if;
  if (v_first ->> 'id') is distinct from (v_second ->> 'id') then
    raise exception 'o periodo automatico criou dois saques';
  end if;
  select count(*) into v_count
  from public.venue_withdrawals
  where venue_id = 'b1111111-1111-4111-8111-111111111111'
    and period_key = 'auto:2026-11-12';
  if v_count <> 1 then
    raise exception 'indice unico do periodo falhou: %', v_count;
  end if;
  v_dispatch := public.begin_withdrawal_dispatch((v_first ->> 'id')::uuid);
  if v_dispatch is not true then
    raise exception 'o primeiro envio nao foi autorizado';
  end if;
  v_dispatch := public.begin_withdrawal_dispatch((v_first ->> 'id')::uuid);
  if v_dispatch then
    raise exception 'o envio duplicou dentro da janela';
  end if;
  if not exists (
    select 1 from public.venue_payout_audit
    where withdrawal_id = (v_first ->> 'id')::uuid
      and action = 'automatic_withdrawal'
      and actor_id is null
  ) then
    raise exception 'o automatico nao entrou na auditoria';
  end if;
end $$;

do $$
begin
  insert into public.venue_withdrawals (
    venue_id, amount_cents, status, source, period_key, external_reference
  ) values (
    'b1111111-1111-4111-8111-111111111111',
    100, 'pending', 'automatic', 'auto:2026-11-12',
    'outra-referencia-unica'
  );
  raise exception 'o indice unico aceitou o segundo automatico';
exception
  when unique_violation then
    null;
end $$;

do $$
declare
  v_manual jsonb;
begin
  v_manual := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 6000, 9000
  );
  if v_manual is not null then
    raise exception 'o manual passou do saldo com pendente';
  end if;
exception
  when others then
    if sqlerrm <> 'saldo' then
      raise;
    end if;
end $$;

do $$
declare
  v_manual jsonb;
  v_done jsonb;
begin
  v_manual := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 1000, 9000
  );
  if v_manual ->> 'fresh' <> 'true' then
    raise exception 'o dono nao sacou';
  end if;
  if not exists (
    select 1 from public.venue_payout_audit
    where actor_id = 'a1111111-1111-4111-8111-111111111111'
      and action = 'request_withdrawal'
      and withdrawal_id = (v_manual ->> 'id')::uuid
  ) then
    raise exception 'a auditoria nao registrou quem sacou';
  end if;
  perform public.attach_venue_transfer(
    (v_manual ->> 'id')::uuid, 'tra_teste_01', 'pending', null
  );
  v_done := public.apply_transfer_event(
    v_manual ->> 'id', 'tra_teste_01', 'done',
    'https://example.com/comprovante', null
  );
  if v_done ->> 'changed' <> 'true' or v_done ->> 'status' <> 'done' then
    raise exception 'o webhook nao concluiu o saque';
  end if;
  v_done := public.apply_transfer_event(
    v_manual ->> 'id', 'tra_teste_01', 'failed', null, 'tarde'
  );
  if v_done ->> 'changed' <> 'false' then
    raise exception 'um evento atrasado desfez o saque concluido';
  end if;
end $$;

do $$
declare
  v_snap jsonb;
  v_count integer;
begin
  if public.venue_payout_period_key(
    'daily', '2026-11-12 02:00:00+00'
  ) <> 'auto:2026-11-11' then
    raise exception 'o periodo diario nao usou America/Sao_Paulo';
  end if;

  perform set_config(
    'request.jwt.claim.sub', 'a3333333-3333-4333-8333-333333333333', true
  );
  set local role authenticated;
  select count(*) into v_count from public.venue_withdrawals;
  if v_count <> 0 then
    raise exception 'a equipe leu saque';
  end if;
  v_snap := public.my_venue_payouts('b1111111-1111-4111-8111-111111111111');
  if v_snap ->> 'can_withdraw' <> 'false' or v_snap ->> 'role' <> 'staff' then
    raise exception 'a equipe apareceu como quem saca';
  end if;
  if v_snap::text like '%55667788000199%' or v_snap ? 'withdrawals' then
    raise exception 'a equipe viu chave ou historico';
  end if;
end $$;

do $$
declare
  v_count integer;
  v_snap jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true
  );
  set local role authenticated;
  select count(*) into v_count
  from public.venue_withdrawals
  where venue_id = 'b1111111-1111-4111-8111-111111111111';
  if v_count < 2 then
    raise exception 'o dono nao leu os proprios saques: %', v_count;
  end if;
  select count(*) into v_count
  from public.venue_withdrawals
  where venue_id = 'b2222222-2222-4222-8222-222222222222';
  if v_count <> 0 then
    raise exception 'o dono leu saque de outra casa';
  end if;
  v_snap := public.my_venue_payouts('b1111111-1111-4111-8111-111111111111');
  if v_snap ->> 'can_withdraw' <> 'true' then
    raise exception 'o dono nao pode sacar';
  end if;
  if v_snap::text like '%55667788000199%' then
    raise exception 'o snapshot devolveu a chave inteira';
  end if;
  if v_snap::text not like '%0199%' then
    raise exception 'o snapshot nao mascarou a chave';
  end if;
end $$;

do $$
declare
  v_count integer;
begin
  perform set_config(
    'request.jwt.claim.sub', 'a2222222-2222-4222-8222-222222222222', true
  );
  set local role authenticated;
  select count(*) into v_count from public.venue_withdrawals;
  if v_count < 2 then
    raise exception 'o admin da casa nao leu os saques';
  end if;
end $$;

do $$
declare
  v_count integer;
begin
  perform set_config(
    'request.jwt.claim.sub', 'a4444444-4444-4444-8444-444444444444', true
  );
  set local role authenticated;
  select count(*) into v_count from public.venue_withdrawals;
  if v_count <> 0 then
    raise exception 'outra casa leu o saque';
  end if;
  begin
    perform public.my_venue_payouts('b1111111-1111-4111-8111-111111111111');
    raise exception 'outra casa leu o snapshot';
  exception
    when others then
      if sqlerrm <> 'not owner' then
        raise;
      end if;
  end;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'a5555555-5555-4555-8555-555555555555', true
  );
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  begin
    perform public.admin_list_venue_withdrawals();
    raise exception 'admin sem aal2 listou saques';
  exception
    when others then
      if sqlerrm <> 'mfa obrigatorio' then
        raise;
      end if;
  end;
  if (select count(*) from public.venue_withdrawals) <> 0 then
    raise exception 'admin sem aal2 leu a tabela';
  end if;
end $$;

do $$
declare
  v_count integer;
begin
  perform set_config(
    'request.jwt.claim.sub', 'a5555555-5555-4555-8555-555555555555', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  select count(*) into v_count from public.admin_list_venue_withdrawals();
  if v_count < 2 then
    raise exception 'admin aal2 nao viu os saques: %', v_count;
  end if;
  if (select count(*) from public.venue_withdrawals) < 2 then
    raise exception 'admin aal2 nao leu a tabela';
  end if;
  perform public.admin_set_venue_payouts_enabled(false);
  if public.venue_payouts_enabled() then
    raise exception 'admin aal2 nao desligou a flag';
  end if;
  perform public.admin_set_venue_payouts_enabled(true);
end $$;

do $$
begin
  set local role anon;
  perform 1 from public.venue_withdrawals;
  raise exception 'anon leu saques';
exception
  when insufficient_privilege then
    if sqlerrm not like 'permission denied%' then
      raise;
    end if;
end $$;

do $$
begin
  set local role authenticated;
  perform public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 100, 9000
  );
  raise exception 'authenticated chamou o claim direto';
exception
  when insufficient_privilege then
    if sqlerrm not like 'permission denied%' then
      raise;
    end if;
end $$;
