-- Agenda a Edge Function reconcile-payments a cada 5 minutos.
-- Sem pg_cron e pg_net (o Postgres do CI), a migração não agenda e não falha.
-- No projeto, crie no vault, fora do git:
--   reconcile_payments_url = https://<ref>.supabase.co/functions/v1/reconcile-payments
--   reconcile_payments_authorization = Bearer <service_role>
-- A função não faz nada enquanto um dos dois segredos estiver vazio.

do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    execute $fn$
      create or replace function private.invoke_reconcile_payments()
      returns void
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_url text;
        v_auth text;
      begin
        select btrim(s.decrypted_secret) into v_url
        from vault.decrypted_secrets s
        where s.name = 'reconcile_payments_url'
        limit 1;
        select btrim(s.decrypted_secret) into v_auth
        from vault.decrypted_secrets s
        where s.name = 'reconcile_payments_authorization'
        limit 1;
        if v_url is null or v_url = '' or v_auth is null or v_auth = '' then
          return;
        end if;
        perform net.http_post(
          url := v_url,
          body := '{}'::jsonb,
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', v_auth
          ),
          timeout_milliseconds := 5000
        );
      end;
      $body$;
    $fn$;
    revoke all on function private.invoke_reconcile_payments()
      from public, anon, authenticated;
    grant execute on function private.invoke_reconcile_payments() to service_role;
    if exists (
      select 1 from cron.job where jobname = 'reconcile-payments'
    ) then
      perform cron.unschedule('reconcile-payments');
    end if;
    perform cron.schedule(
      'reconcile-payments',
      '*/5 * * * *',
      'select private.invoke_reconcile_payments()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; reconcile-payments não foi agendado';
  end if;
end
$cron$;
