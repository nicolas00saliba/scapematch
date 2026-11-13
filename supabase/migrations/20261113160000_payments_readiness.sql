-- Prontidão dos saques e falha alta do cron venue-withdrawals.
-- Sem os dois itens do Vault, o cron antigo retornava e o job ficava
-- succeeded. Agora a função levanta venue_withdrawals_config_ausente
-- e o pg_cron grava status failed. A mensagem cita o nome do item,
-- nunca o valor.
-- admin_payments_readiness devolve só booleanos e um código curto.
-- anon e service_role não executam. O corpo exige admin com aal2.

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
begin
  perform private.admin_require();
  v_flags := private.venue_withdrawals_vault_flags();
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
    'vault_venue_withdrawals_secret',
      coalesce((v_flags ->> 'vault_venue_withdrawals_secret')::boolean, false),
    'venue_payouts_enabled', coalesce(v_enabled, false),
    'cron_last_failed', v_failed,
    'cron_failure_code', case when v_failed then v_code else null end
  );
end;
$$;

revoke all on function public.admin_payments_readiness()
  from public, anon, service_role;
grant execute on function public.admin_payments_readiness() to authenticated;

create or replace function private.invoke_venue_withdrawals()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_flags jsonb;
  v_missing text := '';
begin
  v_flags := private.venue_withdrawals_vault_flags();
  if coalesce((v_flags ->> 'vault_venue_withdrawals_url')::boolean, false)
    is not true
  then
    v_missing := v_missing || 'venue_withdrawals_url ';
  end if;
  if coalesce((v_flags ->> 'vault_venue_withdrawals_secret')::boolean, false)
    is not true
  then
    v_missing := v_missing || 'venue_withdrawals_secret ';
  end if;
  if v_missing <> '' then
    raise exception 'venue_withdrawals_config_ausente: %',
      pg_catalog.btrim(v_missing)
      using errcode = 'P0001';
  end if;

  select pg_catalog.btrim(s.decrypted_secret) into v_url
  from vault.decrypted_secrets s
  where s.name = 'venue_withdrawals_url'
  limit 1;
  select pg_catalog.btrim(s.decrypted_secret) into v_secret
  from vault.decrypted_secrets s
  where s.name = 'venue_withdrawals_secret'
  limit 1;
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    raise exception 'venue_withdrawals_config_ausente: venue_withdrawals_url venue_withdrawals_secret'
      using errcode = 'P0001';
  end if;

  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'x-venue-withdrawals-secret', v_secret
    ),
    timeout_milliseconds := 90000
  );
end;
$$;

revoke all on function private.invoke_venue_withdrawals()
  from public, anon, authenticated, service_role;

do $cron$
begin
  if exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    if exists (
      select 1 from cron.job where jobname = 'venue-withdrawals'
    ) then
      perform cron.unschedule('venue-withdrawals');
    end if;
    perform cron.schedule(
      'venue-withdrawals',
      '20 11 * * *',
      'select private.invoke_venue_withdrawals()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; venue-withdrawals não foi agendado';
  end if;
end
$cron$;
