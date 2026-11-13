-- Painel de pagamentos do admin. Não liga o Asaas e não publica função.
-- A chave de saques continua em admin_set_venue_payouts_enabled, que já audita.
-- Erros de webhook guardam só origem, código e referência. Sem payload.

create table public.payment_webhook_errors (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  source text not null check (
    source in ('asaas-webhook', 'asaas-transfer-webhook')
  ),
  code text not null check (code ~ '^[a-z0-9_]{1,48}$'),
  provider_ref text not null default '' check (
    provider_ref = '' or provider_ref ~ '^[A-Za-z0-9_-]{1,64}$'
  ),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.payment_webhook_errors is
  'Falha recente do webhook do Asaas. Só origem, código e referência. Sem corpo e sem segredo.';

create index payment_webhook_errors_by_created
  on public.payment_webhook_errors (created_at desc);

alter table public.payment_webhook_errors enable row level security;

revoke all on table public.payment_webhook_errors
  from public, anon, authenticated, service_role;

create or replace function public.note_webhook_error(
  p_source text,
  p_code text,
  p_provider_ref text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text := pg_catalog.btrim(coalesce(p_source, ''));
  v_code text := pg_catalog.btrim(coalesce(p_code, ''));
  v_ref text := pg_catalog.btrim(coalesce(p_provider_ref, ''));
begin
  if v_source not in ('asaas-webhook', 'asaas-transfer-webhook') then
    return;
  end if;
  if v_code !~ '^[a-z0-9_]{1,48}$' then
    v_code := 'unknown';
  end if;
  if v_ref !~ '^[A-Za-z0-9_-]{1,64}$' then
    v_ref := '';
  end if;
  insert into public.payment_webhook_errors (source, code, provider_ref)
  values (v_source, v_code, v_ref);
end;
$$;

revoke all on function public.note_webhook_error(text, text, text)
  from public, anon, authenticated;
grant execute on function public.note_webhook_error(text, text, text)
  to service_role;

create or replace function public.admin_payments_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ready jsonb;
  v_charges jsonb;
  v_refunds jsonb;
  v_withdrawals jsonb;
  v_errors jsonb;
begin
  perform private.admin_require();
  v_ready := public.admin_payments_readiness();

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_charges
  from (
    select
      c.id,
      c.status,
      c.billing_type,
      c.amount_cents,
      coalesce(c.provider_ref, '') as provider_ref,
      c.created_at,
      v.name as venue_name
    from public.payment_charges c
    join public.venues v on v.id = c.venue_id
    order by c.created_at desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_refunds
  from (
    select
      c.id,
      c.status,
      c.billing_type,
      c.amount_cents,
      coalesce(c.provider_ref, '') as provider_ref,
      coalesce(c.refunded_at, c.created_at) as created_at,
      v.name as venue_name
    from public.payment_charges c
    join public.venues v on v.id = c.venue_id
    where c.status = 'refunded'
    order by coalesce(c.refunded_at, c.created_at) desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_withdrawals
  from (
    select
      w.id,
      w.status,
      w.source,
      w.amount_cents,
      coalesce(w.asaas_transfer_id, '') as asaas_transfer_id,
      w.created_at,
      v.name as venue_name
    from public.venue_withdrawals w
    join public.venues v on v.id = w.venue_id
    order by w.created_at desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_errors
  from (
    select e.id, e.source, e.code, e.provider_ref, e.created_at
    from public.payment_webhook_errors e
    order by e.created_at desc
    limit 20
  ) s;

  return pg_catalog.jsonb_build_object(
    'readiness', v_ready,
    'charges', v_charges,
    'refunds', v_refunds,
    'withdrawals', v_withdrawals,
    'webhook_errors', v_errors
  );
end;
$$;

revoke all on function public.admin_payments_board()
  from public, anon, service_role;
grant execute on function public.admin_payments_board() to authenticated;
