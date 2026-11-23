-- A função lê o segredo do cron no Vault. O valor não sai na prontidão.

\set ON_ERROR_STOP on

do $$
begin
  if has_function_privilege(
    'anon', 'public.cron_vault_secret(text)', 'execute'
  ) or has_function_privilege(
    'authenticated', 'public.cron_vault_secret(text)', 'execute'
  ) or not has_function_privilege(
    'service_role', 'public.cron_vault_secret(text)', 'execute'
  ) then
    raise exception 'grant do segredo do cron saiu do combinado';
  end if;
end $$;

do $$
begin
  set local role anon;
  perform public.cron_vault_secret('venue_withdrawals_secret');
  raise exception 'anon leu o segredo do vault';
exception
  when insufficient_privilege then
    null;
end $$;

do $$
begin
  set local role authenticated;
  perform public.cron_vault_secret('ledger_reconcile_secret');
  raise exception 'authenticated leu o segredo do vault';
exception
  when insufficient_privilege then
    null;
end $$;

update vault.secrets
set secret = 'segredo-cron-nao-vazar'
where name = 'venue_withdrawals_secret';

do $$
declare
  v_secret text;
begin
  set local role service_role;
  v_secret := public.cron_vault_secret('venue_withdrawals_secret');
  if v_secret is distinct from 'segredo-cron-nao-vazar' then
    raise exception 'service_role não leu o segredo de saque';
  end if;
  if public.cron_vault_secret('asaas_subaccount_key') is not null then
    raise exception 'a função leu outro item do vault';
  end if;
  if public.cron_vault_secret('ledger_reconcile_secret') is not null then
    raise exception 'segredo ausente não voltou nulo';
  end if;
  if public.cron_vault_secret('   ') is not null then
    raise exception 'nome em branco leu o vault';
  end if;
end $$;

do $$
declare
  v_report jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_report := public.admin_payments_readiness();
  if v_report ->> 'venue_withdrawals_secret' is distinct from 'true'
    or v_report ->> 'vault_venue_withdrawals_secret' is distinct from 'true'
    or v_report ->> 'ledger_reconcile_secret' is distinct from 'false'
  then
    raise exception 'a prontidão não refletiu o vault: %', v_report;
  end if;
  if v_report::text like '%segredo-cron-nao-vazar%'
    or v_report::text like '%decrypted%'
  then
    raise exception 'a prontidão devolveu valor de segredo';
  end if;
end $$;

select vault.create_secret(
  'segredo-livro-nao-vazar',
  'ledger_reconcile_secret',
  'teste'
);

do $$
declare
  v_secret text;
  v_report jsonb;
begin
  set local role service_role;
  v_secret := public.cron_vault_secret('ledger_reconcile_secret');
  if v_secret is distinct from 'segredo-livro-nao-vazar' then
    raise exception 'service_role não leu o segredo da conciliação';
  end if;
  reset role;
  perform set_config(
    'request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_report := public.admin_payments_readiness();
  if v_report ->> 'ledger_reconcile_secret' is distinct from 'true' then
    raise exception 'o segredo da conciliação não contou como presente';
  end if;
  if v_report::text like '%segredo-livro-nao-vazar%' then
    raise exception 'a prontidão devolveu o segredo da conciliação';
  end if;
end $$;

delete from vault.secrets where name = 'ledger_reconcile_secret';

update vault.secrets
set secret = ''
where name = 'venue_withdrawals_secret';
