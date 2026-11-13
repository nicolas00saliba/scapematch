-- Alerta de config do cron de saques, uma vez por execução.
-- schedule-venue-withdrawals não verifica JWT. O alerta não sai de lá:
-- cada chamada anônima gastaria cota no Sentry.
-- Este job só faz o POST. O job venue-withdrawals continua falhando
-- na mesma hora quando falta item do Vault. São dois jobs porque o
-- pg_net só envia o pedido depois do commit, e a falha desfaz a transação.
-- O corpo não leva DSN nem valor de segredo. Fingerprint fixo.

create or replace function private.notify_venue_withdrawals_config()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_flags jsonb;
  v_missing text := '';
  v_dsn text;
  v_key text;
  v_host text;
  v_project text;
  v_event text;
  v_payload jsonb;
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
  v_missing := pg_catalog.btrim(v_missing);
  if v_missing = '' then
    return;
  end if;

  select pg_catalog.btrim(s.decrypted_secret) into v_dsn
  from vault.decrypted_secrets s
  where s.name = 'sentry_dsn'
  limit 1;
  if v_dsn is null
    or v_dsn !~ '^https://[A-Za-z0-9]{8,}@[A-Za-z0-9.-]+\.ingest(\.us|\.de)?\.sentry\.io/[0-9]+/?$'
  then
    return;
  end if;

  v_key := substring(v_dsn from 'https://([A-Za-z0-9]+)@');
  v_host := substring(v_dsn from '@([A-Za-z0-9.-]+)/');
  v_project := substring(v_dsn from '/([0-9]+)/?$');
  if v_key is null or v_host is null or v_project is null
    or v_host !~ '^[A-Za-z0-9.-]+\.ingest(\.us|\.de)?\.sentry\.io$'
  then
    return;
  end if;

  v_event := replace(pg_catalog.gen_random_uuid()::text, '-', '');
  v_payload := pg_catalog.jsonb_build_object(
    'event_id', v_event,
    'level', 'error',
    'platform', 'javascript',
    'message', 'schedule-venue-withdrawals: venue_withdrawals_config_ausente',
    'fingerprint', pg_catalog.jsonb_build_array('venue_withdrawals_config_ausente'),
    'tags', pg_catalog.jsonb_build_object(
      'scope', 'schedule-venue-withdrawals',
      'code', 'venue_withdrawals_config_ausente',
      'missing', v_missing
    )
  );
  if v_payload::text like '%' || v_key || '%' then
    return;
  end if;

  begin
    perform net.http_post(
      url := 'https://' || v_host || '/api/' || v_project || '/store/',
      body := v_payload,
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'X-Sentry-Auth',
        'Sentry sentry_version=7, sentry_key=' || v_key || ', sentry_client=escapematch-ops/1'
      ),
      timeout_milliseconds := 5000
    );
  exception
    when undefined_function then
      return;
  end;
end;
$$;

revoke all on function private.notify_venue_withdrawals_config()
  from public, anon, authenticated, service_role;

do $cron$
begin
  if exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    if exists (
      select 1 from cron.job where jobname = 'venue-withdrawals-config'
    ) then
      perform cron.unschedule('venue-withdrawals-config');
    end if;
    perform cron.schedule(
      'venue-withdrawals-config',
      '20 11 * * *',
      'select private.notify_venue_withdrawals_config()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; venue-withdrawals-config não foi agendado';
  end if;
end
$cron$;
