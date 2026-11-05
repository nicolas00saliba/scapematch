-- Cifra saved_cards.credit_card_token em repouso.
-- A chave nasce dentro do vault e não é gravada no repositório.
-- Quem grava e lê o token são funções em private, executadas só pela
-- service role. O app continua vendo só id, last4 e bandeira.

create schema if not exists extensions;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    create extension pgcrypto with schema extensions;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'card_token_key'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'card_token_key',
      'Chave dos tokens de cartão. Fica no vault e não sai do banco.'
    );
  end if;
end $$;

create or replace function private.card_token_key()
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
  where s.name = 'card_token_key'
  limit 1;
  if v_key is null or char_length(v_key) < 32 then
    raise exception 'chave do cartão ausente';
  end if;
  return v_key;
end;
$$;

revoke all on function private.card_token_key()
  from public, anon, authenticated, service_role;

drop index if exists public.saved_cards_user_token;

do $$
declare
  v_name text;
begin
  for v_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.saved_cards'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%credit_card_token%'
  loop
    execute format(
      'alter table public.saved_cards drop constraint %I',
      v_name
    );
  end loop;
end $$;

alter table public.saved_cards
  alter column credit_card_token type bytea
  using extensions.pgp_sym_encrypt(credit_card_token, private.card_token_key());

create or replace function private.insert_saved_card(
  p_user_id uuid,
  p_customer_id text,
  p_token text,
  p_last4 text,
  p_brand text,
  p_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if p_user_id is null
    or p_customer_id is null
    or char_length(p_customer_id) < 1
    or char_length(p_customer_id) > 80
    or p_token is null
    or char_length(p_token) < 8
    or char_length(p_token) > 200
    or p_token ~ '^[0-9]{13,19}$'
    or p_last4 is null
    or p_last4 !~ '^[0-9]{4}$'
    or p_brand is null
    or char_length(p_brand) < 1
    or char_length(p_brand) > 32
  then
    raise exception 'token inválido';
  end if;
  insert into public.saved_cards (
    id, user_id, asaas_customer_id, credit_card_token, last4, brand
  )
  values (
    v_id,
    p_user_id,
    p_customer_id,
    extensions.pgp_sym_encrypt(p_token, private.card_token_key()),
    p_last4,
    p_brand
  );
  return v_id;
end;
$$;

create or replace function private.load_owned_card(
  p_user_id uuid,
  p_customer_id text,
  p_card_id uuid
) returns table (
  id uuid,
  token text,
  last4 text,
  brand text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select
    c.id,
    extensions.pgp_sym_decrypt(c.credit_card_token, private.card_token_key()),
    c.last4,
    c.brand
  from public.saved_cards c
  where c.id = p_card_id
    and c.user_id = p_user_id
    and c.asaas_customer_id = p_customer_id;
end;
$$;

revoke all on function private.insert_saved_card(uuid, text, text, text, text, uuid)
  from public, anon, authenticated;
revoke all on function private.load_owned_card(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function private.insert_saved_card(uuid, text, text, text, text, uuid)
  to service_role;
grant execute on function private.load_owned_card(uuid, text, uuid)
  to service_role;

create or replace function public.insert_saved_card(
  p_user_id uuid,
  p_customer_id text,
  p_token text,
  p_last4 text,
  p_brand text,
  p_id uuid default null
) returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.insert_saved_card(
    p_user_id, p_customer_id, p_token, p_last4, p_brand, p_id
  );
$$;

create or replace function public.load_owned_card(
  p_user_id uuid,
  p_customer_id text,
  p_card_id uuid
) returns table (
  id uuid,
  token text,
  last4 text,
  brand text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select id, token, last4, brand
  from private.load_owned_card(p_user_id, p_customer_id, p_card_id);
$$;

revoke all on function public.insert_saved_card(uuid, text, text, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.load_owned_card(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.insert_saved_card(uuid, text, text, text, text, uuid)
  to service_role;
grant execute on function public.load_owned_card(uuid, text, uuid)
  to service_role;

revoke select, insert, update, delete on table public.saved_cards from service_role;
grant select (id, user_id, asaas_customer_id, last4, brand, created_at)
  on table public.saved_cards to service_role;
