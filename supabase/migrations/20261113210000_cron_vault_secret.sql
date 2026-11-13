-- A função do cron lê o segredo no Vault quando a env da Edge Function
-- não existe. Só os dois nomes usados pelos crons. O valor sai só para
-- service_role. A prontidão continua devolvendo sim ou não.

create or replace function private.venue_withdrawals_vault_flags()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'vault_venue_withdrawals_url', exists (
      select 1
      from vault.decrypted_secrets s
      where s.name = 'venue_withdrawals_url'
        and pg_catalog.btrim(s.decrypted_secret) <> ''
    ),
    'vault_venue_withdrawals_secret', exists (
      select 1
      from vault.decrypted_secrets s
      where s.name = 'venue_withdrawals_secret'
        and pg_catalog.btrim(s.decrypted_secret) <> ''
    ),
    'vault_ledger_reconcile_secret', exists (
      select 1
      from vault.decrypted_secrets s
      where s.name = 'ledger_reconcile_secret'
        and pg_catalog.btrim(s.decrypted_secret) <> ''
    )
  );
$$;

revoke all on function private.venue_withdrawals_vault_flags()
  from public, anon, authenticated, service_role;

create or replace function public.admin_payments_readiness()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_flags jsonb;
  v_enabled boolean;
  v_failed boolean;
  v_code text;
  v_withdrawals boolean;
  v_ledger boolean;
begin
  perform private.admin_require();
  v_flags := private.venue_withdrawals_vault_flags();
  v_withdrawals := coalesce(
    (v_flags ->> 'vault_venue_withdrawals_secret')::boolean,
    false
  );
  v_ledger := coalesce(
    (v_flags ->> 'vault_ledger_reconcile_secret')::boolean,
    false
  );
  select enabled into v_enabled
  from public.venue_payouts_settings
  where id = 1;

  if exists (select 1 from pg_catalog.pg_namespace where nspname = 'cron') then
    begin
      execute $q$
        select d.status = 'failed',
          case
            when d.status <> 'failed' then null
            when d.return_message like '%venue_withdrawals_config_ausente%'
              then 'config_ausente'
            else 'cron_failed'
          end
        from cron.job_run_details d
        join cron.job j on j.jobid = d.jobid
        where j.jobname = 'venue-withdrawals'
        order by d.start_time desc
        limit 1
      $q$ into v_failed, v_code;
    exception
      when undefined_table or insufficient_privilege then
        v_failed := null;
        v_code := null;
    end;
  end if;

  return pg_catalog.jsonb_build_object(
    'vault_venue_withdrawals_url',
      coalesce((v_flags ->> 'vault_venue_withdrawals_url')::boolean, false),
    'vault_venue_withdrawals_secret', v_withdrawals,
    'vault_ledger_reconcile_secret', v_ledger,
    'venue_withdrawals_secret', v_withdrawals,
    'ledger_reconcile_secret', v_ledger,
    'venue_payouts_enabled', coalesce(v_enabled, false),
    'cron_last_failed', v_failed,
    'cron_failure_code', case when v_failed then v_code else null end
  );
end;
$$;

revoke all on function public.admin_payments_readiness()
  from public, anon, service_role;
grant execute on function public.admin_payments_readiness() to authenticated;

create or replace function public.cron_vault_secret(p_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  if p_name is distinct from 'venue_withdrawals_secret'
    and p_name is distinct from 'ledger_reconcile_secret'
  then
    return null;
  end if;
  select pg_catalog.btrim(s.decrypted_secret) into v_secret
  from vault.decrypted_secrets s
  where s.name = p_name
  limit 1;
  if v_secret is null or v_secret = '' then
    return null;
  end if;
  return v_secret;
end;
$$;

revoke all on function public.cron_vault_secret(text)
  from public, anon, authenticated;
grant execute on function public.cron_vault_secret(text) to service_role;

comment on function public.cron_vault_secret(text) is
  'Segredo do cron para a Edge Function. Só service_role. Não logar o retorno.';
