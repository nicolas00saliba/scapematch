-- Conta de repasse por provedor. Woovi (Pix) e Mercado Pago (cartão).
-- Não guarda segredo em texto: o token OAuth fica cifrado em private.
-- A NFS-e continua no Asaas e fica fora desta troca.
-- Esta migração não é aplicada em produção por este agente.

create table public.provider_payout_accounts (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id),
  provider text not null check (provider in ('woovi', 'mercadopago')),
  external_id text not null,
  pix_key text,
  status text not null default 'pending' check (
    status in ('pending', 'active', 'revoked')
  ),
  expires_at timestamptz,
  auto_withdraw boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (venue_id, provider)
);

comment on table public.provider_payout_accounts is
  'Conta de repasse da casa por provedor. A casa não abre a Woovi. NFS-e pendente, segue no Asaas.';

comment on column public.provider_payout_accounts.pix_key is
  'Chave Pix da subconta Woovi. O split e o saque usam esta chave.';

comment on column public.provider_payout_accounts.auto_withdraw is
  'Quando verdadeiro, a liquidação da sessão saca a parte da casa. O cron não varre o saldo.';

alter table public.provider_payout_accounts enable row level security;

revoke all on table public.provider_payout_accounts
  from public, anon, authenticated;
grant select, insert, update on table public.provider_payout_accounts
  to service_role;

alter table public.payment_charges
  add column if not exists provider_end_to_end_id text,
  add column if not exists house_pix_key text;

comment on column public.payment_charges.provider_end_to_end_id is
  'endToEndId do Pix na Woovi. O estorno usa este identificador.';

comment on column public.payment_charges.house_pix_key is
  'Pix da subconta que recebeu o split. O débito do estorno sai desta chave.';

create table public.provider_webhook_events (
  provider text not null check (provider in ('woovi', 'mercadopago')),
  event_id text not null,
  received_at timestamptz not null default pg_catalog.now(),
  primary key (provider, event_id)
);

alter table public.provider_webhook_events enable row level security;

revoke all on table public.provider_webhook_events
  from public, anon, authenticated;
grant select, insert on table public.provider_webhook_events to service_role;

create table private.provider_oauth_tokens (
  venue_id uuid not null references public.venues (id) on delete cascade,
  provider text not null check (provider = 'mercadopago'),
  access_token bytea not null,
  refresh_token bytea not null,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (venue_id, provider)
);

alter table private.provider_oauth_tokens enable row level security;

revoke all on table private.provider_oauth_tokens
  from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'provider_token_key'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'provider_token_key',
      'Chave dos tokens OAuth de repasse. Não é credencial de provedor.'
    );
  end if;
end $$;

create or replace function private.provider_token_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  select pg_catalog.btrim(s.decrypted_secret) into v_key
  from vault.decrypted_secrets s
  where s.name = 'provider_token_key'
  limit 1;
  if v_key is null or char_length(v_key) < 32 then
    raise exception 'chave de repasse ausente';
  end if;
  return v_key;
end;
$$;

revoke all on function private.provider_token_key()
  from public, anon, authenticated, service_role;

create or replace function public.provider_actor_can_manage(
  p_venue_id uuid,
  p_actor uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.venue_treasurer(p_venue_id, p_actor);
$$;

revoke all on function public.provider_actor_can_manage(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.provider_actor_can_manage(uuid, uuid)
  to service_role;

create or replace function public.provider_house_account(
  p_venue_id uuid,
  p_actor uuid,
  p_provider text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row public.provider_payout_accounts%rowtype;
begin
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  select * into v_row
  from public.provider_payout_accounts
  where venue_id = p_venue_id
    and provider = p_provider
    and status = 'active';
  if not found or v_row.pix_key is null or pg_catalog.btrim(v_row.pix_key) = '' then
    raise exception 'sem subconta' using errcode = '42501';
  end if;
  return pg_catalog.jsonb_build_object(
    'pix_key', v_row.pix_key,
    'external_id', v_row.external_id,
    'status', v_row.status,
    'auto_withdraw', v_row.auto_withdraw
  );
end;
$$;

revoke all on function public.provider_house_account(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.provider_house_account(uuid, uuid, text)
  to service_role;

create or replace function public.upsert_provider_payout_account(
  p_venue_id uuid,
  p_provider text,
  p_external_id text,
  p_pix_key text,
  p_status text,
  p_expires_at timestamptz,
  p_auto_withdraw boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_provider not in ('woovi', 'mercadopago') then
    raise exception 'valor' using errcode = '22023';
  end if;
  if p_status not in ('pending', 'active', 'revoked') then
    raise exception 'valor' using errcode = '22023';
  end if;
  insert into public.provider_payout_accounts (
    venue_id, provider, external_id, pix_key, status, expires_at, auto_withdraw
  ) values (
    p_venue_id,
    p_provider,
    pg_catalog.btrim(p_external_id),
    nullif(pg_catalog.btrim(coalesce(p_pix_key, '')), ''),
    p_status,
    p_expires_at,
    coalesce(p_auto_withdraw, false)
  )
  on conflict (venue_id, provider) do update
    set external_id = excluded.external_id,
        pix_key = coalesce(excluded.pix_key, provider_payout_accounts.pix_key),
        status = excluded.status,
        expires_at = excluded.expires_at,
        auto_withdraw = excluded.auto_withdraw,
        updated_at = pg_catalog.now()
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.upsert_provider_payout_account(
  uuid, text, text, text, text, timestamptz, boolean
) from public, anon, authenticated;
grant execute on function public.upsert_provider_payout_account(
  uuid, text, text, text, text, timestamptz, boolean
) to service_role;

create or replace function public.store_provider_oauth(
  p_venue_id uuid,
  p_provider text,
  p_access_token text,
  p_refresh_token text,
  p_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_provider is distinct from 'mercadopago' then
    raise exception 'valor' using errcode = '22023';
  end if;
  if p_access_token is null or char_length(p_access_token) < 20
    or p_refresh_token is null or char_length(p_refresh_token) < 20
  then
    raise exception 'token ausente' using errcode = '22023';
  end if;
  insert into private.provider_oauth_tokens (
    venue_id, provider, access_token, refresh_token
  ) values (
    p_venue_id,
    p_provider,
    extensions.pgp_sym_encrypt(p_access_token, private.provider_token_key()),
    extensions.pgp_sym_encrypt(p_refresh_token, private.provider_token_key())
  )
  on conflict (venue_id, provider) do update
    set access_token = excluded.access_token,
        refresh_token = excluded.refresh_token,
        updated_at = pg_catalog.now();
  update public.provider_payout_accounts
  set expires_at = p_expires_at,
      updated_at = pg_catalog.now()
  where venue_id = p_venue_id
    and provider = p_provider;
end;
$$;

revoke all on function public.store_provider_oauth(uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.store_provider_oauth(uuid, text, text, text, timestamptz)
  to service_role;

create or replace function public.read_provider_oauth(
  p_venue_id uuid,
  p_provider text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access text;
  v_refresh text;
  v_expires timestamptz;
begin
  if p_provider is distinct from 'mercadopago' then
    raise exception 'valor' using errcode = '22023';
  end if;
  select
    extensions.pgp_sym_decrypt(access_token, private.provider_token_key()),
    extensions.pgp_sym_decrypt(refresh_token, private.provider_token_key())
  into v_access, v_refresh
  from private.provider_oauth_tokens
  where venue_id = p_venue_id
    and provider = p_provider;
  if v_access is null then
    raise exception 'oauth ausente' using errcode = '42501';
  end if;
  select expires_at into v_expires
  from public.provider_payout_accounts
  where venue_id = p_venue_id
    and provider = p_provider;
  return pg_catalog.jsonb_build_object(
    'access_token', v_access,
    'refresh_token', v_refresh,
    'expires_at', v_expires
  );
end;
$$;

comment on function public.read_provider_oauth(uuid, text) is
  'Só a service role. O token não entra em log nem em resposta de app.';

revoke all on function public.read_provider_oauth(uuid, text)
  from public, anon, authenticated;
grant execute on function public.read_provider_oauth(uuid, text) to service_role;

create or replace function public.claim_provider_webhook(
  p_provider text,
  p_event_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if p_provider not in ('woovi', 'mercadopago')
    or p_event_id is null
    or char_length(pg_catalog.btrim(p_event_id)) < 4
  then
    raise exception 'valor' using errcode = '22023';
  end if;
  insert into public.provider_webhook_events (provider, event_id)
  values (p_provider, pg_catalog.btrim(p_event_id))
  on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

comment on function public.claim_provider_webhook(text, text) is
  'Verdadeiro na primeira entrega. Falso quando o evento já foi visto.';

revoke all on function public.claim_provider_webhook(text, text)
  from public, anon, authenticated;
grant execute on function public.claim_provider_webhook(text, text) to service_role;

create or replace function public.claim_provider_withdrawal(
  p_venue_id uuid,
  p_actor uuid,
  p_source text,
  p_period_key text,
  p_amount_cents integer,
  p_available_cents integer,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_period text;
  v_pending integer;
  v_blocked timestamptz;
begin
  perform private.venue_payouts_require();
  if p_provider is distinct from 'woovi' then
    raise exception 'valor' using errcode = '22023';
  end if;
  if p_source is distinct from 'manual' then
    raise exception 'valor' using errcode = '22023';
  end if;
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.provider_payout_accounts
    where venue_id = p_venue_id
      and provider = 'woovi'
      and status = 'active'
      and pix_key is not null
  ) then
    raise exception 'sem subconta' using errcode = '42501';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0
    or p_available_cents is null or p_amount_cents > p_available_cents
  then
    raise exception 'saldo' using errcode = '22023';
  end if;
  select withdrawals_blocked_until into v_blocked
  from public.venue_bank_accounts
  where venue_id = p_venue_id;
  if v_blocked is not null and v_blocked > pg_catalog.now() then
    raise exception 'bloqueado' using errcode = '42501';
  end if;
  select coalesce(pg_catalog.sum(amount_cents), 0)::integer into v_pending
  from public.venue_withdrawals
  where venue_id = p_venue_id
    and status = 'pending';
  if p_amount_cents + v_pending > p_available_cents then
    raise exception 'saldo' using errcode = '22023';
  end if;
  v_id := pg_catalog.gen_random_uuid();
  v_period := 'woovi:' || v_id::text;
  insert into public.venue_withdrawals (
    id, venue_id, amount_cents, status, source, period_key,
    external_reference, requested_by
  ) values (
    v_id, p_venue_id, p_amount_cents, 'pending', 'manual', v_period,
    v_id::text, p_actor
  );
  return pg_catalog.jsonb_build_object(
    'id', v_id,
    'amount_cents', p_amount_cents,
    'fresh', true
  );
end;
$$;

revoke all on function public.claim_provider_withdrawal(
  uuid, uuid, text, text, integer, integer, text
) from public, anon, authenticated;
grant execute on function public.claim_provider_withdrawal(
  uuid, uuid, text, text, integer, integer, text
) to service_role;
