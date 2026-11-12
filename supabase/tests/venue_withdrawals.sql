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
    'public.venue_payout_snapshot(uuid,uuid,boolean)',
    'public.list_venue_subaccounts()',
    'public.list_stale_pending_withdrawals(integer)',
    'public.venue_weekly_attempt_key(uuid,timestamptz)'
  ];
begin
  if public.venue_payouts_enabled() then
    raise exception 'a flag de saque nasceu ligada';
  end if;
  if has_table_privilege('anon', 'public.venue_bank_accounts', 'select')
    or has_table_privilege('authenticated', 'public.venue_bank_accounts', 'select')
    or has_table_privilege('service_role', 'public.venue_bank_accounts', 'select')
  then
    raise exception 'a conta bancaria continua legivel pela API';
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
    null, 'automatic', 'auto:2026-W10', 4000, 9000
  );
  perform public.save_venue_payout_schedule(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    true, 'weekly', 4, 1000
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
  true, 'weekly', 4, 1000
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
    null, 'automatic', 'auto:2026-W10', 4000, 9000
  );
  v_second := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', 'auto:2026-W10', 4000, 9000
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
    and period_key = 'auto:2026-W10';
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
    100, 'pending', 'automatic', 'auto:2026-W10',
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
  -- O Asaas já tirou o pendente do saldo disponível. 6000 cabe em 9000
  -- mesmo com outro saque pendente de 4000. Somar de novo recusaria este.
  v_manual := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 6000, 9000
  );
  if v_manual ->> 'fresh' <> 'true' then
    raise exception 'o saldo disponivel recusou um saque que cabe';
  end if;
end $$;

do $$
begin
  perform public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'manual', '', 10000, 9000
  );
  raise exception 'o manual passou do saldo disponivel';
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
  ) is not null then
    raise exception 'o diario ainda tem periodo';
  end if;
  if public.venue_payout_period_key(
    'weekly', '2026-11-12 02:00:00+00'
  ) <> 'auto:2026-W46' then
    raise exception 'o periodo semanal nao usou America/Sao_Paulo';
  end if;
  if pg_catalog.date_part(
    'dow', timestamptz '2026-11-12 02:00:00+00' at time zone 'America/Sao_Paulo'
  ) <> 3 then
    raise exception 'o fuso nao recuou para quarta';
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

insert into public.venue_bank_accounts (
  venue_id, destination, bank_code, agency, account_number, account_digit,
  owner_name, owner_document, operation_type, updated_by
) values (
  'b2222222-2222-4222-8222-222222222222',
  'bank', '341', '1234', '123456789', '0',
  'Outra Casa', '66778899000100', 'PIX',
  'a4444444-4444-4444-8444-444444444444'
);

do $$
declare
  v_user text;
  v_snap text;
  v_value text;
  v_column text;
  v_users text[] := array[
    'a1111111-1111-4111-8111-111111111111',
    'a2222222-2222-4222-8222-222222222222',
    'a5555555-5555-4555-8555-555555555555'
  ];
  v_columns text[] := array['pix_key', 'account_number', 'owner_document'];
begin
  perform set_config(
    'request.jwt.claim.sub', 'a4444444-4444-4444-8444-444444444444', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_snap := public.my_venue_payouts(
    'b2222222-2222-4222-8222-222222222222'
  )::text;
  if v_snap like '%123456789%' or v_snap like '%66778899000100%' then
    raise exception 'o snapshot devolveu conta ou documento inteiro';
  end if;
  if v_snap not like '%6789%' then
    raise exception 'o snapshot nao mascarou a conta';
  end if;

  foreach v_user in array v_users loop
    perform set_config('request.jwt.claim.sub', v_user, true);
    perform set_config('request.jwt.claim.aal', 'aal2', true);
    foreach v_column in array v_columns loop
      begin
        execute format(
          'select %I from public.venue_bank_accounts limit 1', v_column
        ) into v_value;
        raise exception '% leu %: %', v_user, v_column, v_value;
      exception
        when insufficient_privilege then
          if sqlerrm not like 'permission denied%' then
            raise;
          end if;
      end;
    end loop;
  end loop;
end $$;

do $$
declare
  v_old uuid;
  v_count integer;
begin
  insert into public.venue_withdrawals (
    venue_id, amount_cents, status, source, period_key,
    external_reference, asaas_transfer_id, updated_at
  ) values (
    'b2222222-2222-4222-8222-222222222222',
    100, 'pending', 'manual', 'manual:velho',
    'ref-velho-pendente', 'tra_velho_pendente',
    pg_catalog.now() - interval '7 hours'
  ) returning id into v_old;

  select count(*) into v_count
  from public.list_stale_pending_withdrawals(6)
  where id = v_old;
  if v_count <> 1 then
    raise exception 'o pendente antigo nao entrou na reconciliacao';
  end if;

  update public.venue_withdrawals
  set updated_at = pg_catalog.now()
  where id = v_old;
  select count(*) into v_count
  from public.list_stale_pending_withdrawals(6)
  where id = v_old;
  if v_count <> 0 then
    raise exception 'o pendente recente entrou na reconciliacao';
  end if;
end $$;

do $$
begin
  perform public.list_stale_pending_withdrawals(0);
  raise exception 'a reconciliacao aceitou prazo invalido';
exception
  when others then
    if sqlerrm <> 'valor' then
      raise;
    end if;
end $$;

do $$
declare
  v_base text;
  v_key text;
  v_id uuid;
  v_retry integer;
  v_count integer;
  v_claim jsonb;
  v_dispatch boolean;
  v_now timestamptz := pg_catalog.now();
begin
  if pg_catalog.pg_get_functiondef('public.list_due_venue_payouts()'::regprocedure)
    not like '%venue_weekly_attempt_key%'
  then
    raise exception 'a lista semanal nao usa a retentativa';
  end if;

  update public.venue_payout_schedules
  set frequency = 'weekly',
      weekday = pg_catalog.date_part(
        'dow', v_now at time zone 'America/Sao_Paulo'
      )::smallint
  where venue_id = 'b1111111-1111-4111-8111-111111111111';

  v_base := public.venue_payout_period_key('weekly', v_now);
  v_key := public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  );
  if v_key is distinct from v_base then
    raise exception 'o semanal do dia nao abriu a primeira tentativa: %', v_key;
  end if;

  insert into public.venue_withdrawals (
    venue_id, amount_cents, status, source, period_key,
    external_reference, retry_count, created_at, updated_at
  ) values (
    'b1111111-1111-4111-8111-111111111111',
    4000, 'failed', 'automatic', v_base,
    'ref-semana-base', 0,
    v_now - interval '1 day', v_now - interval '1 day'
  ) returning id into v_id;

  v_key := public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  );
  if v_key is distinct from v_base then
    raise exception 'a falha sem id nao reaproveitou a linha';
  end if;

  v_dispatch := public.begin_withdrawal_dispatch(v_id);
  if v_dispatch is not true then
    raise exception 'a primeira retentativa sem id nao saiu';
  end if;
  perform public.fail_venue_withdrawal(v_id, 'erro');
  update public.venue_withdrawals
  set updated_at = v_now - interval '1 day'
  where id = v_id;
  v_dispatch := public.begin_withdrawal_dispatch(v_id);
  if v_dispatch is not true then
    raise exception 'a segunda retentativa sem id nao saiu';
  end if;
  perform public.fail_venue_withdrawal(v_id, 'erro');
  update public.venue_withdrawals
  set updated_at = v_now - interval '1 day'
  where id = v_id;
  select retry_count into v_retry
  from public.venue_withdrawals
  where id = v_id;
  if v_retry <> 2 then
    raise exception 'o limite de retentativa nao ficou em 2: %', v_retry;
  end if;
  if public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  ) is not null then
    raise exception 'a terceira retentativa ainda foi oferecida';
  end if;
  if public.begin_withdrawal_dispatch(v_id) then
    raise exception 'a terceira retentativa sem id duplicou o envio';
  end if;

  update public.venue_withdrawals
  set status = 'failed',
      asaas_transfer_id = 'tra_semana_base',
      retry_count = 0,
      dispatch_started_at = null,
      updated_at = v_now
  where id = v_id;
  if public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  ) is not null then
    raise exception 'a retentativa saiu no mesmo dia da falha';
  end if;
  if public.begin_withdrawal_dispatch(v_id) then
    raise exception 'reabriu uma transferencia que o Asaas ja conhece';
  end if;

  update public.venue_withdrawals
  set updated_at = v_now - interval '1 day'
  where id = v_id;
  v_key := public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  );
  if v_key is distinct from v_base || '-r1' then
    raise exception 'o dia seguinte nao abriu a primeira retentativa: %', v_key;
  end if;

  v_claim := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', v_key, 4000, 9000
  );
  if v_claim ->> 'fresh' <> 'true' then
    raise exception 'a retentativa nao criou o saque';
  end if;
  v_claim := public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', v_key, 4000, 9000
  );
  if v_claim ->> 'fresh' <> 'false' then
    raise exception 'a mesma retentativa criou outro saque';
  end if;
  select count(*) into v_count
  from public.venue_withdrawals
  where venue_id = 'b1111111-1111-4111-8111-111111111111'
    and period_key = v_base || '-r1';
  if v_count <> 1 then
    raise exception 'a retentativa duplicou a linha: %', v_count;
  end if;
  if public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  ) is not null then
    raise exception 'abriu outra retentativa com a anterior pendente';
  end if;

  update public.venue_withdrawals
  set status = 'failed',
      asaas_transfer_id = 'tra_semana_r1',
      updated_at = v_now - interval '1 day'
  where period_key = v_base || '-r1'
    and venue_id = 'b1111111-1111-4111-8111-111111111111';
  v_key := public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  );
  if v_key is distinct from v_base || '-r2' then
    raise exception 'a segunda retentativa da semana nao abriu: %', v_key;
  end if;

  insert into public.venue_withdrawals (
    venue_id, amount_cents, status, source, period_key,
    external_reference, asaas_transfer_id, created_at, updated_at
  ) values (
    'b1111111-1111-4111-8111-111111111111',
    4000, 'failed', 'automatic', v_base || '-r2',
    'ref-semana-r2', 'tra_semana_r2',
    v_now - interval '1 day', v_now - interval '1 day'
  );
  if public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  ) is not null then
    raise exception 'a semana passou de duas retentativas';
  end if;

  begin
    perform public.claim_venue_withdrawal(
      'b1111111-1111-4111-8111-111111111111',
      null, 'automatic', v_base || '-r3', 4000, 9000
    );
    raise exception 'aceitou uma terceira retentativa';
  exception
    when others then
      if sqlerrm <> 'valor' then
        raise;
      end if;
  end;

  update public.venue_withdrawals
  set status = 'done'
  where venue_id = 'b1111111-1111-4111-8111-111111111111'
    and period_key in (v_base, v_base || '-r1', v_base || '-r2');
  if public.venue_weekly_attempt_key(
    'b1111111-1111-4111-8111-111111111111', v_now
  ) is not null then
    raise exception 'a semana concluida foi tentada de novo';
  end if;
end $$;

do $$
begin
  perform public.save_venue_payout_schedule(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    true, 'daily', null, 1000
  );
  raise exception 'aceitou saque diario';
exception
  when others then
    if sqlerrm <> 'valor' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.claim_venue_withdrawal(
    'b1111111-1111-4111-8111-111111111111',
    null, 'automatic', 'auto:2026-11-12', 1000, 9000
  );
  raise exception 'aceitou periodo diario';
exception
  when others then
    if sqlerrm <> 'valor' then
      raise;
    end if;
end $$;

do $$
begin
  perform public.save_venue_bank_account(
    'b1111111-1111-4111-8111-111111111111',
    'a1111111-1111-4111-8111-111111111111',
    'bank', null, null, '341', '0001', '12345', '6',
    'Casa do Saque', '55667788000199', 'TED'
  );
  raise exception 'aceitou ted';
exception
  when others then
    if sqlerrm <> 'sem pix' then
      raise;
    end if;
end $$;
