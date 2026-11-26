-- Uma conta PagBank ativa por casa.
--
-- Antes: venues.pagbank_account_id guardava só a última conta conectada e o
-- Connect sobrescrevia a anterior sem avisar (a conta do split e a do token
-- podiam sair de conexões diferentes). Agora:
--   * a troca de conta só passa por desconectar e conectar de novo;
--   * conectar uma segunda conta diferente falha com 'pagbank_account_exists';
--   * o token guarda a conta a que pertence, e o repasse para se divergir.
--
-- Esta migration não apaga nem altera dado. Se já houver duplicado, ela
-- falha e lista o caso (só os 4 últimos caracteres). Quem decide é o dono.

do $$
declare
  v_dups text;
  v_orphans text;
begin
  select pg_catalog.string_agg(
           pg_catalog.format('conta ...%s em %s casas', right(a.account, 4), a.n),
           '; '
         )
    into v_dups
  from (
    select v.pagbank_account_id as account, pg_catalog.count(*) as n
    from public.venues v
    where v.pagbank_account_id is not null
      and pg_catalog.btrim(v.pagbank_account_id) <> ''
      and not v.is_test
    group by v.pagbank_account_id
    having pg_catalog.count(*) > 1
  ) a;
  if v_dups is not null then
    raise exception 'contas PagBank repetidas entre casas: %. Decida qual casa fica com cada conta e limpe a outra antes de aplicar.', v_dups
      using errcode = 'P0001';
  end if;

  select pg_catalog.string_agg(pg_catalog.left(t.venue_id::text, 8), ', ')
    into v_orphans
  from public.venue_pagbank_tokens t
  join public.venues v on v.id = t.venue_id
  where v.pagbank_account_id is null
     or pg_catalog.btrim(v.pagbank_account_id) = '';
  if v_orphans is not null then
    raise exception 'tokens PagBank sem conta na casa (casas %). Decida se a casa reconecta ou se o token sai antes de aplicar.', v_orphans
      using errcode = 'P0001';
  end if;
end $$;

-- Conta a que o token pertence. Vazio em token antigo: ainda não conferido.
alter table public.venue_pagbank_tokens
  add column if not exists account_id text;

comment on column public.venue_pagbank_tokens.account_id is
  'Conta PagBank dona do token. Nulo em token anterior a esta coluna.';

create or replace function private.venues_one_pagbank_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.pagbank_account_id is null
    or pg_catalog.btrim(new.pagbank_account_id) = ''
  then
    return new;
  end if;
  if old.pagbank_account_id is not null
    and pg_catalog.btrim(old.pagbank_account_id) <> ''
    and new.pagbank_account_id is distinct from old.pagbank_account_id
  then
    raise exception 'pagbank_account_exists'
      using errcode = 'PB409',
            detail = 'a casa já tem uma conta PagBank; desconecte antes de conectar outra';
  end if;
  if exists (
    select 1
    from public.venue_pagbank_tokens t
    where t.venue_id = new.id
      and t.account_id is not null
      and t.account_id is distinct from new.pagbank_account_id
  ) then
    raise exception 'pagbank_account_mismatch'
      using errcode = 'PB409',
            detail = 'o token guardado é de outra conta PagBank';
  end if;
  return new;
end;
$$;

revoke all on function private.venues_one_pagbank_account()
  from public, anon, authenticated, service_role;

drop trigger if exists venues_one_pagbank_account on public.venues;
create trigger venues_one_pagbank_account
  before update of pagbank_account_id on public.venues
  for each row execute function private.venues_one_pagbank_account();

create or replace function private.tokens_match_pagbank_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account text;
begin
  if new.account_id is null then
    return new;
  end if;
  select v.pagbank_account_id
    into v_account
  from public.venues v
  where v.id = new.venue_id;
  if v_account is not null
    and pg_catalog.btrim(v_account) <> ''
    and v_account is distinct from new.account_id
  then
    raise exception 'pagbank_account_mismatch'
      using errcode = 'PB409',
            detail = 'o token é de outra conta PagBank que a da casa';
  end if;
  return new;
end;
$$;

revoke all on function private.tokens_match_pagbank_account()
  from public, anon, authenticated, service_role;

drop trigger if exists tokens_match_pagbank_account
  on public.venue_pagbank_tokens;
create trigger tokens_match_pagbank_account
  before insert or update of account_id on public.venue_pagbank_tokens
  for each row execute function private.tokens_match_pagbank_account();

-- Conecta a conta única da casa: conta e token mudam juntos, numa transação,
-- com a linha da casa travada. Mesma conta de novo só renova o token.
create or replace function public.connect_venue_pagbank(
  p_venue_id uuid,
  p_actor uuid,
  p_account_id text,
  p_access_token text,
  p_refresh_token text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account text := pg_catalog.btrim(coalesce(p_account_id, ''));
  v_current text;
  v_test boolean;
begin
  if p_venue_id is null or p_actor is null or v_account = '' then
    raise exception 'conta' using errcode = '22023';
  end if;
  select v.pagbank_account_id, v.is_test
    into v_current, v_test
  from public.venues v
  where v.id = p_venue_id
  for update;
  if not found then
    raise exception 'casa' using errcode = '22023';
  end if;
  if v_current is not null
    and pg_catalog.btrim(v_current) <> ''
    and v_current <> v_account
  then
    raise exception 'pagbank_account_exists'
      using errcode = 'PB409',
            detail = pg_catalog.format('conta atual ...%s', right(v_current, 4));
  end if;

  -- A mesma conta não liga a duas casas reais. Casa de teste fica de fora,
  -- como no índice venues_pagbank_account_real_uidx.
  if not v_test and exists (
    select 1
    from public.venues o
    where o.pagbank_account_id = v_account
      and o.id <> p_venue_id
      and not o.is_test
  ) then
    raise exception 'pagbank_account_in_use'
      using errcode = 'PB409',
            detail = 'essa conta PagBank já está ligada a outra casa';
  end if;
  begin
    update public.venues
    set pagbank_account_id = v_account
    where id = p_venue_id
      and pagbank_account_id is distinct from v_account;
  exception when unique_violation then
    -- duas casas conectando a mesma conta ao mesmo tempo
    raise exception 'pagbank_account_in_use'
      using errcode = 'PB409',
            detail = 'essa conta PagBank já está ligada a outra casa';
  end;

  perform public.store_venue_pagbank_tokens(
    p_venue_id, p_access_token, p_refresh_token, p_expires_at
  );
  update public.venue_pagbank_tokens
  set account_id = v_account
  where venue_id = p_venue_id;

  perform private.admin_audit(
    p_actor,
    'connect_pagbank',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('account_last4', right(coalesce(v_current, ''), 4)),
    pg_catalog.jsonb_build_object('account_last4', right(v_account, 4))
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'account_last4', right(v_account, 4),
    'renewed', v_current is not null and v_current = v_account
  );
end;
$$;

revoke all on function public.connect_venue_pagbank(uuid, uuid, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.connect_venue_pagbank(uuid, uuid, text, text, text, timestamptz)
  to service_role;

-- Dinheiro a caminho: saque pendente ou cobrança que ainda vai cair na
-- conta atual. Trocar a conta nessa hora mandaria o dinheiro para outra.
create or replace function private.venue_pagbank_in_flight(p_venue_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (
    select pg_catalog.count(*)
    from public.venue_withdrawals w
    where w.venue_id = p_venue_id
      and w.status = 'pending'
  )::integer + (
    select pg_catalog.count(*)
    from public.payment_charges c
    where c.venue_id = p_venue_id
      and (
        -- reserva ou cobrança aberta recente: o split ainda vai para a conta
        (c.status in ('creating', 'pending')
          and c.created_at > pg_catalog.now() - interval '1 day')
        or (c.status = 'authorized'
          and c.created_at > pg_catalog.now() - interval '7 days')
        -- paga, com split e custódia ainda não solta. Sem split ou já
        -- liquidada, estornada ou com estorno pedido não conta.
        or (
          c.status = 'paid'
          and c.provider_split_id is not null
          and c.custody_released_at is null
          and c.refunded_at is null
          and c.refund_requested_at is null
        )
      )
  )::integer;
$$;

revoke all on function private.venue_pagbank_in_flight(uuid)
  from public, anon, authenticated, service_role;

-- Desconecta. O dono ou o Admin (com MFA, checado na função). Sem dinheiro
-- a caminho. O token sai junto; a conta antiga fica só no registro de
-- auditoria, pelos 4 últimos caracteres.
create or replace function public.disconnect_venue_pagbank(
  p_venue_id uuid,
  p_actor uuid,
  p_admin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_current text;
  v_busy integer;
begin
  if p_venue_id is null or p_actor is null then
    raise exception 'casa' using errcode = '22023';
  end if;
  select v.owner_id, v.pagbank_account_id
    into v_owner, v_current
  from public.venues v
  where v.id = p_venue_id
  for update;
  if not found then
    raise exception 'casa' using errcode = '22023';
  end if;
  if not coalesce(p_admin, false) and v_owner is distinct from p_actor then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_current is null or pg_catalog.btrim(v_current) = '' then
    delete from public.venue_pagbank_tokens where venue_id = p_venue_id;
    return pg_catalog.jsonb_build_object('disconnected', false);
  end if;
  v_busy := private.venue_pagbank_in_flight(p_venue_id);
  if v_busy > 0 then
    raise exception 'pagbank_in_flight'
      using errcode = 'PB409',
            detail = pg_catalog.format('%s item(ns) ainda a caminho para a conta atual', v_busy);
  end if;

  delete from public.venue_pagbank_tokens where venue_id = p_venue_id;
  delete from public.pagbank_connect_states
  where venue_id = p_venue_id and used_at is null;
  update public.venues
  set pagbank_account_id = null
  where id = p_venue_id;

  perform private.admin_audit(
    p_actor,
    'disconnect_pagbank',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('account_last4', right(v_current, 4)),
    pg_catalog.jsonb_build_object('account_last4', null, 'by_admin', coalesce(p_admin, false))
  );
  return pg_catalog.jsonb_build_object(
    'disconnected', true,
    'account_last4', right(v_current, 4)
  );
end;
$$;

revoke all on function public.disconnect_venue_pagbank(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.disconnect_venue_pagbank(uuid, uuid, boolean)
  to service_role;

-- O repasse confere antes de mexer em dinheiro. Não devolve id de conta.
--   none        casa sem conta e sem token
--   ok          conta e token da mesma conta
--   unverified  token antigo, sem a conta gravada (não é divergência)
--   ambiguous   token de outra conta, ou token sem conta na casa
create or replace function public.venue_pagbank_binding(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_account text;
  v_token_exists boolean;
  v_token_account text;
begin
  select v.pagbank_account_id
    into v_account
  from public.venues v
  where v.id = p_venue_id;
  if not found then
    return pg_catalog.jsonb_build_object('state', 'none');
  end if;
  if v_account is not null and pg_catalog.btrim(v_account) = '' then
    v_account := null;
  end if;
  select true, t.account_id
    into v_token_exists, v_token_account
  from public.venue_pagbank_tokens t
  where t.venue_id = p_venue_id;
  v_token_exists := coalesce(v_token_exists, false);

  if v_account is null and not v_token_exists then
    return pg_catalog.jsonb_build_object('state', 'none');
  end if;
  if v_account is null then
    return pg_catalog.jsonb_build_object(
      'state', 'ambiguous', 'reason', 'tokens_without_account'
    );
  end if;
  if v_token_account is not null and v_token_account <> v_account then
    return pg_catalog.jsonb_build_object(
      'state', 'ambiguous', 'reason', 'tokens_other_account'
    );
  end if;
  if v_token_exists and v_token_account is null then
    return pg_catalog.jsonb_build_object('state', 'unverified');
  end if;
  return pg_catalog.jsonb_build_object('state', 'ok');
end;
$$;

revoke all on function public.venue_pagbank_binding(uuid)
  from public, anon, authenticated;
grant execute on function public.venue_pagbank_binding(uuid) to service_role;

-- O que a tela do Parceiro mostra. Dono ou Admin. Documento e conta mascarados.
create or replace function public.venue_pagbank_account_view(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.venues%rowtype;
  v_uid uuid := auth.uid();
  v_digits text;
  v_masked text;
  v_since timestamptz;
  v_token_account text;
  v_busy integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v from public.venues where id = p_venue_id;
  if not found then
    raise exception 'casa' using errcode = '22023';
  end if;
  if v.owner_id is distinct from v_uid and not private.is_admin_aal2() then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v.pagbank_account_id is null
    or pg_catalog.btrim(v.pagbank_account_id) = ''
  then
    return pg_catalog.jsonb_build_object('connected', false);
  end if;

  v_digits := pg_catalog.regexp_replace(
    coalesce(v.document_digits, v.document_number, ''), '\D', '', 'g'
  );
  v_masked := case
    when v.document_kind = 'cnpj' and char_length(v_digits) = 14
      then '**.***.***/****-' || right(v_digits, 2)
    when char_length(v_digits) = 11
      then '***.***.***-' || right(v_digits, 2)
    else null
  end;
  select max(a.created_at)
    into v_since
  from public.admin_audit_log a
  where a.action = 'connect_pagbank'
    and a.target_table = 'venues'
    and a.target_id = p_venue_id::text;
  select t.account_id
    into v_token_account
  from public.venue_pagbank_tokens t
  where t.venue_id = p_venue_id;
  v_busy := private.venue_pagbank_in_flight(p_venue_id);

  return pg_catalog.jsonb_build_object(
    'connected', true,
    'house_name', v.name,
    'bank', 'PagBank',
    'account_last4', right(v.pagbank_account_id, 4),
    'document_kind', v.document_kind,
    'document_masked', v_masked,
    'connected_at', v_since,
    'verified', v_token_account is not null
      and v_token_account = v.pagbank_account_id,
    'can_disconnect', v_busy = 0
  );
end;
$$;

revoke all on function public.venue_pagbank_account_view(uuid)
  from public, anon;
grant execute on function public.venue_pagbank_account_view(uuid)
  to authenticated, service_role;

-- Só a reserva nova (status creating) com id de conta PagBank é conferida; cobrança histórica ou
-- inserida por outro caminho não muda de comportamento.
-- Corrida entre desconectar e reservar: a cobrança nasce com a conta que a
-- casa tem NESTE instante. O FOR SHARE espera o FOR UPDATE do disconnect; se
-- a conta mudou ou saiu, a reserva falha com 409 em vez de apontar o split
-- para a conta antiga. E o disconnect, que conta as cobranças depois do lock,
-- vê a reserva já gravada.
create or replace function private.charge_wallet_matches_venue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account text;
begin
  if new.status is distinct from 'creating'
    or new.venue_id is null
    or new.wallet_id is null
    -- só id de conta PagBank (ACCO_...); outro formato não é conferido
    or new.wallet_id not like 'ACCO\_%'
  then
    return new;
  end if;
  select v.pagbank_account_id
    into v_account
  from public.venues v
  where v.id = new.venue_id
  for share;
  if v_account is distinct from new.wallet_id then
    raise exception 'pagbank_account_changed'
      using errcode = 'PB409',
            detail = 'a conta PagBank da casa mudou durante a reserva';
  end if;
  return new;
end;
$$;

revoke all on function private.charge_wallet_matches_venue()
  from public, anon, authenticated, service_role;

drop trigger if exists charge_wallet_matches_venue on public.payment_charges;
create trigger charge_wallet_matches_venue
  before insert on public.payment_charges
  for each row
  when (new.status = 'creating')
  execute function private.charge_wallet_matches_venue();
