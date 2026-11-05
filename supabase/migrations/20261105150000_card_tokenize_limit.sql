-- Teto de 5 cartões e 5 tentativas de tokenização por hora.
-- A decisão fica em private e só a service role executa. O schema private
-- não entra na API; public.claim_card_tokenize_attempt só encaminha a chamada
-- para a Edge Function, também sem execute para anon nem authenticated.

create table public.card_tokenize_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index card_tokenize_attempts_user_time
  on public.card_tokenize_attempts (user_id, created_at);

alter table public.card_tokenize_attempts enable row level security;

revoke all on table public.card_tokenize_attempts
  from public, anon, authenticated, service_role;

create or replace function private.claim_card_tokenize_attempt(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts bigint;
  v_cards bigint;
begin
  if p_user_id is null then
    return false;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('card_tokenize'),
    pg_catalog.hashtext(p_user_id::text)
  );
  delete from public.card_tokenize_attempts
  where user_id = p_user_id
    and created_at <= pg_catalog.now() - interval '1 hour';
  insert into public.card_tokenize_attempts (user_id)
  values (p_user_id);
  select count(*) into v_attempts
  from public.card_tokenize_attempts
  where user_id = p_user_id;
  select count(*) into v_cards
  from public.saved_cards
  where user_id = p_user_id;
  return v_attempts <= 5 and v_cards < 5;
end;
$$;

revoke all on function private.claim_card_tokenize_attempt(uuid)
  from public, anon, authenticated;
grant execute on function private.claim_card_tokenize_attempt(uuid)
  to service_role;

create or replace function public.claim_card_tokenize_attempt(p_user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.claim_card_tokenize_attempt(p_user_id);
$$;

revoke all on function public.claim_card_tokenize_attempt(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_card_tokenize_attempt(uuid)
  to service_role;

create or replace function public.saved_cards_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('card_tokenize'),
    pg_catalog.hashtext(new.user_id::text)
  );
  select count(*) into v_count
  from public.saved_cards
  where user_id = new.user_id;
  if v_count >= 5 then
    raise exception 'limite de cartões';
  end if;
  return new;
end;
$$;

drop trigger if exists saved_cards_limit on public.saved_cards;
create trigger saved_cards_limit
  before insert on public.saved_cards
  for each row execute function public.saved_cards_limit();

revoke all on function public.saved_cards_limit()
  from public, anon, authenticated;
