-- Conciliação diária Asaas x livro. O job só lê. Não aplica migration sozinho.
-- Sem pg_cron/pg_net o agendamento é ignorado e a migration não falha.

create table public.payment_reconcile_runs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  started_at timestamptz not null default pg_catalog.now(),
  payment_count integer not null default 0 check (payment_count >= 0),
  transfer_count integer not null default 0 check (transfer_count >= 0),
  divergence_count integer not null default 0 check (divergence_count >= 0),
  truncated boolean not null default false
);

create table public.payment_divergences (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  run_id uuid not null references public.payment_reconcile_runs (id) on delete cascade,
  kind text not null check (kind in (
    'charge_missing_local',
    'charge_missing_asaas',
    'charge_status',
    'charge_amount',
    'ledger_missing',
    'ledger_refund_missing',
    'transfer_missing_local',
    'transfer_missing_asaas',
    'transfer_status',
    'transfer_amount',
    'asaas_truncated'
  )),
  provider_ref text not null default '' check (char_length(provider_ref) <= 80),
  local_id text not null default '' check (char_length(local_id) <= 80),
  expected text not null default '' check (char_length(expected) <= 40),
  actual text not null default '' check (char_length(actual) <= 40),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.payment_divergences is
  'Diferença entre o Asaas e o livro. Sem nome, documento, QR ou chave.';

create index payment_divergences_by_run
  on public.payment_divergences (run_id, created_at desc);

alter table public.payment_reconcile_runs enable row level security;
alter table public.payment_divergences enable row level security;

revoke all on table public.payment_reconcile_runs
  from public, anon, authenticated, service_role;
revoke all on table public.payment_divergences
  from public, anon, authenticated, service_role;

create or replace function public.ledger_reconcile_snapshot(
  p_since timestamptz,
  p_payment_ids text[],
  p_transfer_ids text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_charges jsonb;
  v_withdrawals jsonb;
  v_charge_count integer;
  v_withdrawal_count integer;
begin
  select count(*) into v_charge_count
  from public.payment_charges c
  where c.provider = 'asaas'
    and (
      c.created_at >= p_since
      or c.paid_at >= p_since
      or c.refunded_at >= p_since
      or c.provider_ref = any (coalesce(p_payment_ids, array[]::text[]))
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into v_charges
  from (
    select
      c.id,
      coalesce(c.provider_ref, '') as provider_ref,
      c.status,
      c.amount_cents,
      coalesce((
        select pg_catalog.jsonb_agg(distinct e.kind)
        from public.ledger_entries e
        where e.payment_charge_id = c.id
      ), '[]'::jsonb) as ledger_kinds
    from public.payment_charges c
    where c.provider = 'asaas'
      and (
        c.created_at >= p_since
        or c.paid_at >= p_since
        or c.refunded_at >= p_since
        or c.provider_ref = any (coalesce(p_payment_ids, array[]::text[]))
      )
    order by c.created_at desc
    limit 500
  ) s;

  select count(*) into v_withdrawal_count
  from public.venue_withdrawals w
  where w.created_at >= p_since
    or w.updated_at >= p_since
    or w.asaas_transfer_id = any (coalesce(p_transfer_ids, array[]::text[]))
    or w.external_reference = any (coalesce(p_transfer_ids, array[]::text[]));

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into v_withdrawals
  from (
    select
      w.id,
      w.external_reference,
      coalesce(w.asaas_transfer_id, '') as asaas_transfer_id,
      w.status,
      w.amount_cents
    from public.venue_withdrawals w
    where w.created_at >= p_since
      or w.updated_at >= p_since
      or w.asaas_transfer_id = any (coalesce(p_transfer_ids, array[]::text[]))
      or w.external_reference = any (coalesce(p_transfer_ids, array[]::text[]))
    order by w.created_at desc
    limit 500
  ) s;

  return pg_catalog.jsonb_build_object(
    'charges', v_charges,
    'withdrawals', v_withdrawals,
    'capped', v_charge_count > 500 or v_withdrawal_count > 500
  );
end;
$$;

revoke all on function public.ledger_reconcile_snapshot(timestamptz, text[], text[])
  from public, anon, authenticated;
grant execute on function public.ledger_reconcile_snapshot(timestamptz, text[], text[])
  to service_role;

create or replace function public.record_payment_divergences(
  p_payment_count integer,
  p_transfer_count integer,
  p_truncated boolean,
  p_rows jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run uuid;
  v_count integer := 0;
  v_row jsonb;
  v_kind text;
  v_provider text;
  v_local text;
  v_expected text;
  v_actual text;
begin
  if p_payment_count < 0 or p_transfer_count < 0 then
    raise exception 'contagem' using errcode = '22023';
  end if;
  insert into public.payment_reconcile_runs (
    payment_count, transfer_count, truncated
  ) values (
    p_payment_count, p_transfer_count, coalesce(p_truncated, false)
  )
  returning id into v_run;

  if pg_catalog.jsonb_typeof(p_rows) = 'array' then
    for v_row in select value from pg_catalog.jsonb_array_elements(p_rows)
    loop
      v_kind := pg_catalog.btrim(coalesce(v_row ->> 'kind', ''));
      v_provider := pg_catalog.left(coalesce(v_row ->> 'providerRef', ''), 80);
      v_local := pg_catalog.left(coalesce(v_row ->> 'localId', ''), 80);
      v_expected := pg_catalog.left(coalesce(v_row ->> 'expected', ''), 40);
      v_actual := pg_catalog.left(coalesce(v_row ->> 'actual', ''), 40);
      if v_kind not in (
        'charge_missing_local', 'charge_missing_asaas', 'charge_status',
        'charge_amount', 'ledger_missing', 'ledger_refund_missing',
        'transfer_missing_local', 'transfer_missing_asaas', 'transfer_status',
        'transfer_amount', 'asaas_truncated'
      ) then
        continue;
      end if;
      insert into public.payment_divergences (
        run_id, kind, provider_ref, local_id, expected, actual
      ) values (
        v_run, v_kind, v_provider, v_local, v_expected, v_actual
      );
      v_count := v_count + 1;
    end loop;
  end if;

  update public.payment_reconcile_runs
  set divergence_count = v_count
  where id = v_run;
  return v_run;
end;
$$;

revoke all on function public.record_payment_divergences(integer, integer, boolean, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_payment_divergences(integer, integer, boolean, jsonb)
  to service_role;

create or replace function public.admin_payment_divergences()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run public.payment_reconcile_runs%rowtype;
  v_rows jsonb;
begin
  perform private.admin_require();
  select * into v_run
  from public.payment_reconcile_runs
  order by started_at desc
  limit 1;
  if v_run.id is null then
    return pg_catalog.jsonb_build_object('run', null, 'rows', '[]'::jsonb);
  end if;
  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select d.kind, d.provider_ref, d.local_id, d.expected, d.actual, d.created_at
    from public.payment_divergences d
    where d.run_id = v_run.id
    order by d.created_at desc
    limit 100
  ) s;
  return pg_catalog.jsonb_build_object(
    'run', pg_catalog.jsonb_build_object(
      'id', v_run.id,
      'started_at', v_run.started_at,
      'payment_count', v_run.payment_count,
      'transfer_count', v_run.transfer_count,
      'divergence_count', v_run.divergence_count,
      'truncated', v_run.truncated
    ),
    'rows', v_rows
  );
end;
$$;

revoke all on function public.admin_payment_divergences()
  from public, anon, service_role;
grant execute on function public.admin_payment_divergences() to authenticated;

create or replace function private.invoke_ledger_reconcile()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_missing text := '';
begin
  select pg_catalog.btrim(s.decrypted_secret) into v_url
  from vault.decrypted_secrets s
  where s.name = 'ledger_reconcile_url'
  limit 1;
  select pg_catalog.btrim(s.decrypted_secret) into v_secret
  from vault.decrypted_secrets s
  where s.name = 'ledger_reconcile_secret'
  limit 1;
  if v_url is null or v_url = '' then
    v_missing := v_missing || 'ledger_reconcile_url ';
  end if;
  if v_secret is null or v_secret = '' then
    v_missing := v_missing || 'ledger_reconcile_secret ';
  end if;
  if v_missing <> '' then
    raise exception 'ledger_reconcile_config_ausente: %',
      pg_catalog.btrim(v_missing)
      using errcode = 'P0001';
  end if;
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'x-ledger-reconcile-secret', v_secret
    ),
    timeout_milliseconds := 90000
  );
end;
$$;

revoke all on function private.invoke_ledger_reconcile()
  from public, anon, authenticated, service_role;

do $cron$
begin
  if exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    if exists (
      select 1 from cron.job where jobname = 'ledger-reconcile'
    ) then
      perform cron.unschedule('ledger-reconcile');
    end if;
    perform cron.schedule(
      'ledger-reconcile',
      '30 11 * * *',
      'select private.invoke_ledger_reconcile()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; ledger-reconcile não foi agendado';
  end if;
end
$cron$;
