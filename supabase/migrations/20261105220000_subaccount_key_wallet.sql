-- Cifra venue_asaas_keys.api_key em repouso. O segredo
-- asaas_subaccount_key tem de já existir no Vault. Esta migração não
-- cria a chave e não cifra com null. A resposta ao cliente não leva wallet_id.

create schema if not exists extensions;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    create extension pgcrypto with schema extensions;
  end if;
end $$;

do $$
declare
  v_key text;
begin
  select btrim(s.decrypted_secret) into v_key
  from vault.decrypted_secrets s
  where s.name = 'asaas_subaccount_key'
  limit 1;
  if v_key is null or char_length(v_key) < 32 then
    raise exception 'asaas_subaccount_key ausente no vault'
      using errcode = 'P0001';
  end if;
end $$;

create or replace function private.asaas_subaccount_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  select btrim(s.decrypted_secret) into v_key
  from vault.decrypted_secrets s
  where s.name = 'asaas_subaccount_key'
  limit 1;
  if v_key is null or char_length(v_key) < 32 then
    raise exception 'chave da subconta ausente';
  end if;
  return v_key;
end;
$$;

revoke all on function private.asaas_subaccount_key()
  from public, anon, authenticated, service_role;

alter table public.venue_asaas_keys
  alter column api_key type bytea
  using extensions.pgp_sym_encrypt(api_key, private.asaas_subaccount_key());

create or replace function private.store_venue_asaas_key(
  p_venue_id uuid,
  p_api_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_api_key is null or char_length(btrim(p_api_key)) = 0 then
    raise exception 'api_key ausente' using errcode = '22023';
  end if;
  insert into public.venue_asaas_keys (venue_id, api_key)
  values (
    p_venue_id,
    extensions.pgp_sym_encrypt(p_api_key, private.asaas_subaccount_key())
  )
  on conflict (venue_id) do update
  set api_key = excluded.api_key;
end;
$$;

create or replace function private.read_venue_asaas_key(p_venue_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  select extensions.pgp_sym_decrypt(k.api_key, private.asaas_subaccount_key())
  into v_key
  from public.venue_asaas_keys k
  where k.venue_id = p_venue_id;
  return v_key;
end;
$$;

revoke all on function private.store_venue_asaas_key(uuid, text)
  from public, anon, authenticated;
revoke all on function private.read_venue_asaas_key(uuid)
  from public, anon, authenticated;
grant execute on function private.store_venue_asaas_key(uuid, text) to service_role;
grant execute on function private.read_venue_asaas_key(uuid) to service_role;

create or replace function public.store_venue_asaas_key(
  p_venue_id uuid,
  p_api_key text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.store_venue_asaas_key(p_venue_id, p_api_key);
end;
$$;

create or replace function public.read_venue_asaas_key(p_venue_id uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select private.read_venue_asaas_key(p_venue_id);
$$;

revoke all on function public.store_venue_asaas_key(uuid, text)
  from public, anon, authenticated;
revoke all on function public.read_venue_asaas_key(uuid)
  from public, anon, authenticated;
grant execute on function public.store_venue_asaas_key(uuid, text) to service_role;
grant execute on function public.read_venue_asaas_key(uuid) to service_role;

-- Wallet sai da resposta do dono e do admin. O app não seleciona a coluna.
-- Revogar uma coluna não tira o SELECT da tabela inteira, então a cobrança
-- passa a liberar coluna por coluna, sem wallet_id.
revoke select (asaas_wallet_id) on table public.venues from anon, authenticated;
revoke select on table public.payment_charges from anon, authenticated;
grant select (
  id,
  group_id,
  user_id,
  venue_id,
  amount_cents,
  billing_type,
  status,
  provider,
  provider_ref,
  qr_code,
  qr_code_base64,
  idempotency_key,
  commission_bps,
  created_at,
  paid_at,
  refunded_at,
  reserved_at,
  attempt_id
) on table public.payment_charges to authenticated;

drop function public.venue_private(uuid);

create function public.venue_private(p_venue_id uuid)
returns table (
  document_number text,
  phone text,
  income_value numeric,
  referred_by uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not (private.owns_venue(p_venue_id) or private.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return query
    select
      v.document_number,
      v.phone,
      v.income_value,
      v.referred_by
    from public.venues v
    where v.id = p_venue_id;
end;
$$;

revoke all on function public.venue_private(uuid) from public, anon;
grant execute on function public.venue_private(uuid) to authenticated, service_role;
