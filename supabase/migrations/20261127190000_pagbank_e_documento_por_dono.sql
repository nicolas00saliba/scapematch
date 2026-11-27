-- Conta PagBank e documento por dono; reativar cidade.
--
-- Decisões do Nícolas (27/11/2026):
--   * uma conta PagBank só pode receber por todas as unidades (cidades) do
--     MESMO dono, inclusive com CNPJs diferentes;
--   * o mesmo CPF/CNPJ vale para várias cidades do mesmo dono;
--   * o dono reativa sozinho uma cidade que ele mesmo desativou.
-- Entre donos diferentes, conta e documento continuam bloqueados.
--
-- Como a conta é compartilhada: a unidade que conectou pelo PagBank guarda o
-- token (venue_pagbank_tokens). A outra unidade grava a mesma conta em
-- pagbank_account_id e aponta para ela em pagbank_token_venue_id. Ler e
-- gravar token passam pela unidade dona do token, então a renovação do token
-- vale para todas e nada é copiado. Split, custódia e repasse continuam por
-- unidade (pagbank_account_id de cada uma).
--
-- Troca dois índices únicos por índices comuns + checagem com trava
-- (pg_advisory_xact_lock), porque o Postgres não expressa "único entre donos
-- diferentes" num índice único. O resto só acrescenta.
-- Não aplicar em produção antes do ok do Nícolas.

alter table public.venues
  add column if not exists pagbank_token_venue_id uuid
    references public.venues (id) on delete set null,
  add column if not exists deactivated_prev_suspended_at timestamptz;

comment on column public.venues.pagbank_token_venue_id is
  'Unidade do mesmo dono que guarda o token PagBank desta. Nulo: o token é desta unidade.';
comment on column public.venues.deactivated_prev_suspended_at is
  'suspended_at de antes da desativação pelo dono; volta na reativação.';

grant select (pagbank_token_venue_id) on table public.venues to authenticated;

create or replace function private.venue_pagbank_token_venue(p_venue_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select v.pagbank_token_venue_id from public.venues v where v.id = p_venue_id),
    p_venue_id
  );
$$;

revoke all on function private.venue_pagbank_token_venue(uuid)
  from public, anon, authenticated;

-- Conta PagBank: mesma conta só entre unidades do mesmo dono.
drop index if exists public.venues_pagbank_account_real_uidx;
create index if not exists venues_by_pagbank_account
  on public.venues (pagbank_account_id)
  where pagbank_account_id is not null;

create or replace function private.venues_pagbank_account_one_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_test
    or new.pagbank_account_id is null
    or pg_catalog.btrim(new.pagbank_account_id) = ''
  then
    return new;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('venue_pagbank_account:' || new.pagbank_account_id)
  );
  if exists (
    select 1
    from public.venues o
    where o.pagbank_account_id = new.pagbank_account_id
      and o.id <> new.id
      and not o.is_test
      and (o.owner_id is null or new.owner_id is null or o.owner_id <> new.owner_id)
  ) then
    raise exception 'pagbank_account_in_use'
      using errcode = 'PB409',
            detail = 'essa conta PagBank já está ligada a casa de outro dono';
  end if;
  if new.pagbank_token_venue_id is not null then
    if new.pagbank_token_venue_id = new.id or not exists (
      select 1
      from public.venues s
      where s.id = new.pagbank_token_venue_id
        and s.pagbank_token_venue_id is null
        and s.pagbank_account_id = new.pagbank_account_id
        and s.owner_id = new.owner_id
    ) then
      raise exception 'pagbank_share_invalid'
        using errcode = 'PB409',
              detail = 'a unidade de origem não tem esta conta ou é de outro dono';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.venues_pagbank_account_one_owner()
  from public, anon, authenticated, service_role;

drop trigger if exists venues_pagbank_account_one_owner on public.venues;
create trigger venues_pagbank_account_one_owner
  before insert or update of pagbank_account_id, pagbank_token_venue_id, owner_id, is_test
  on public.venues
  for each row execute function private.venues_pagbank_account_one_owner();

-- Documento: mesmo CPF/CNPJ só entre unidades do mesmo dono.
drop index if exists public.venues_document_digits_active_uidx;
create index if not exists venues_by_document_digits
  on public.venues (document_digits)
  where document_digits is not null;

create or replace function private.venues_normalize()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_test boolean;
begin
  new.document_number := public.normalize_document(new.document_number);
  new.document_digits := new.document_number;
  if char_length(new.document_number) = 11 then
    new.document_kind := 'cpf';
  elsif char_length(new.document_number) = 14 then
    new.document_kind := 'cnpj';
  end if;
  new.postal_code := regexp_replace(coalesce(new.postal_code, ''), '\D', '', 'g');
  new.name_normalized := public.normalize_venue_name(new.name);
  new.address_number_normalized := public.normalize_address_number(new.address_number);

  if tg_op = 'INSERT' then
    if v_uid is not null and not private.is_admin_aal2() then
      new.merged_into := null;
    end if;
  elsif v_uid is not null and not private.is_admin_aal2() then
    new.merged_into := old.merged_into;
  end if;

  if new.possible_duplicate_of is not null then
    if not exists (
      select 1
      from public.venues venue
      where venue.id = new.possible_duplicate_of
        and venue.status = 'approved'
        and venue.id is distinct from new.id
    ) then
      raise exception 'invalid duplicate link' using errcode = '23503';
    end if;
  end if;

  -- A mesma regra de private.venues_test_flag. O valor que o cliente
  -- manda em is_test não entra: no insert vale o perfil do dono.
  if v_uid is null or private.is_admin_aal2() then
    v_test := new.is_test;
  elsif tg_op = 'INSERT' then
    v_test := coalesce(
      (select p.is_test from public.profiles p where p.id = new.owner_id),
      false
    );
  else
    v_test := old.is_test;
  end if;

  -- Casa real não vê casa de teste, no insert nem no update. A cópia
  -- de teste do mesmo CPF não bloqueia o cadastro nem o PagBank.
  -- Mesmo documento vale para várias unidades (cidades) do MESMO dono
  -- (decisão do Nícolas, 27/11). Entre donos diferentes, ou casa sem dono,
  -- continua bloqueado. A trava serializa dois cadastros do mesmo documento.
  if not v_test
    and new.status not in ('rejected', 'merged')
    and new.document_digits is not null
  then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('venue_document:' || new.document_digits)
    );
  end if;
  if not v_test
    and new.status not in ('rejected', 'merged')
    and new.document_digits is not null
    and exists (
      select 1
      from public.venues venue
      where venue.document_digits = new.document_digits
        and venue.status not in ('rejected', 'merged')
        and venue.id is distinct from new.id
        and not venue.is_test
        and (
          venue.owner_id is null
          or new.owner_id is null
          or venue.owner_id <> new.owner_id
        )
    ) then
    raise exception 'duplicate document' using errcode = '23505';
  end if;

  return new;
end;
$$;

CREATE OR REPLACE FUNCTION private.venues_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.pagbank_account_id := null;
      new.suspended_at := null;
      new.deactivated_at := null;
      new.deactivated_by := null;
      new.deactivated_prev_suspended_at := null;
      new.pagbank_token_venue_id := null;
      new.featured_rank := null;
      new.official_email := null;
      new.official_phone := null;
      new.claimed_at := pg_catalog.now();
      if new.invite_id is not null then
        select i.badge
          into new.badge
        from public.partner_invites i
        where i.id = new.invite_id
          and i.active;
        if not found then
          raise exception 'unknown invite' using errcode = 'P0002';
        end if;
      else
        new.badge := null;
      end if;
    end if;
    if new.latitude is null or new.longitude is null then
      select c.latitude, c.longitude
        into new.latitude, new.longitude
      from public.cities c
      where c.id = new.city_id;
    end if;
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  if not private.is_admin_aal2() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.invite_id := old.invite_id;
    -- Só share_venue_pagbank_account liga esta chave, depois de conferir
    -- que as duas unidades são do mesmo dono.
    if current_setting('scapematch.pagbank_share', true) is distinct from 'on' then
      new.pagbank_account_id := old.pagbank_account_id;
      new.pagbank_token_venue_id := old.pagbank_token_venue_id;
    end if;
    -- Só deactivate_my_unit liga esta chave, na própria transação, depois de
    -- conferir dono, outra unidade ativa, grupos futuros e dinheiro a caminho.
    if current_setting('scapematch.unit_deactivation', true) is distinct from 'on' then
      new.suspended_at := old.suspended_at;
      new.deactivated_at := old.deactivated_at;
      new.deactivated_by := old.deactivated_by;
      new.deactivated_prev_suspended_at := old.deactivated_prev_suspended_at;
    end if;
    new.featured_rank := old.featured_rank;
    new.official_email := old.official_email;
    new.official_phone := old.official_phone;
    new.claimed_at := old.claimed_at;
    if old.status is distinct from 'pending'
      or old.pagbank_account_id is not null
    then
      new.company_type := old.company_type;
    end if;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  -- Admin reativando (suspended_at volta a nulo) desfaz também a
  -- desativação do dono, para a unidade voltar a aparecer no Parceiro.
  if new.suspended_at is null and new.deactivated_at is not null then
    new.deactivated_at := null;
    new.deactivated_by := null;
    new.deactivated_prev_suspended_at := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.store_venue_pagbank_tokens(p_venue_id uuid, p_access_token text, p_refresh_token text, p_expires_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := private.pagbank_token_key();
  v_access bytea;
  v_refresh bytea;
  v_root uuid := private.venue_pagbank_token_venue(p_venue_id);
begin
  if p_access_token is null or char_length(btrim(p_access_token)) = 0 then
    raise exception 'api_key ausente' using errcode = '22023';
  end if;
  v_access := extensions.pgp_sym_encrypt(btrim(p_access_token), v_key);
  if p_refresh_token is null or char_length(btrim(p_refresh_token)) = 0 then
    v_refresh := null;
  else
    v_refresh := extensions.pgp_sym_encrypt(btrim(p_refresh_token), v_key);
  end if;
  insert into public.venue_pagbank_tokens (
    venue_id, access_token, refresh_token, access_expires_at
  ) values (v_root, v_access, v_refresh, p_expires_at)
  on conflict (venue_id) do update
  set access_token = excluded.access_token,
      refresh_token = coalesce(
        excluded.refresh_token,
        public.venue_pagbank_tokens.refresh_token
      ),
      access_expires_at = coalesce(
        excluded.access_expires_at,
        public.venue_pagbank_tokens.access_expires_at
      ),
      updated_at = pg_catalog.now();
end;
$function$;

CREATE OR REPLACE FUNCTION public.read_venue_pagbank_tokens(p_venue_id uuid)
 RETURNS TABLE(access_token text, refresh_token text, access_expires_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := private.pagbank_token_key();
begin
  return query
  select
    extensions.pgp_sym_decrypt(k.access_token, v_key)::text,
    case
      when k.refresh_token is null then null
      else extensions.pgp_sym_decrypt(k.refresh_token, v_key)::text
    end,
    k.access_expires_at
  from public.venue_pagbank_tokens k
  where k.venue_id = private.venue_pagbank_token_venue(p_venue_id);
end;
$function$;

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
  where t.venue_id = private.venue_pagbank_token_venue(p_venue_id);
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
  v_shared_from text;
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
  where t.venue_id = private.venue_pagbank_token_venue(p_venue_id);
  if v.pagbank_token_venue_id is not null then
    select s.name into v_shared_from
    from public.venues s
    where s.id = v.pagbank_token_venue_id;
  end if;
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
    'can_disconnect', v_busy = 0,
    'shared', v.pagbank_token_venue_id is not null,
    'shared_from', v_shared_from
  );
end;
$$;

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
  v_owner uuid;
begin
  if p_venue_id is null or p_actor is null or v_account = '' then
    raise exception 'conta' using errcode = '22023';
  end if;
  select v.pagbank_account_id, v.is_test, v.owner_id
    into v_current, v_test, v_owner
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
  -- Mesmo dono pode usar a mesma conta em várias unidades (decisão do
  -- Nícolas, 27/11). Entre donos diferentes, continua recusado.
  if not v_test and exists (
    select 1
    from public.venues o
    where o.pagbank_account_id = v_account
      and o.id <> p_venue_id
      and not o.is_test
      and (o.owner_id is null or v_owner is null or o.owner_id <> v_owner)
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

  -- Login próprio no PagBank: a unidade passa a guardar o token dela.
  update public.venues
  set pagbank_token_venue_id = null
  where id = p_venue_id
    and pagbank_token_venue_id is not null;

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
  v_pointer uuid;
begin
  if p_venue_id is null or p_actor is null then
    raise exception 'casa' using errcode = '22023';
  end if;
  select v.owner_id, v.pagbank_account_id, v.pagbank_token_venue_id
    into v_owner, v_current, v_pointer
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

  if v_pointer is not null then
    -- Unidade que usa a conta de outra: solta só a ligação. O token é da
    -- outra unidade e continua valendo lá (a função não revoga).
    update public.venues
    set pagbank_account_id = null,
        pagbank_token_venue_id = null
    where id = p_venue_id;
    perform private.admin_audit(
      p_actor,
      'disconnect_pagbank',
      'venues',
      p_venue_id::text,
      pg_catalog.jsonb_build_object('account_last4', right(v_current, 4), 'shared', true),
      pg_catalog.jsonb_build_object('account_last4', null, 'by_admin', coalesce(p_admin, false))
    );
    return pg_catalog.jsonb_build_object(
      'disconnected', true,
      'shared', true,
      'account_last4', right(v_current, 4)
    );
  end if;
  if exists (
    select 1 from public.venues o
    where o.pagbank_token_venue_id = p_venue_id
  ) then
    raise exception 'pagbank_account_shared'
      using errcode = 'PB409',
            detail = 'outra unidade usa esta conta; desconecte a outra antes';
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

create or replace function public.deactivate_my_unit(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_venue public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_venue
  from public.venues
  where id = p_venue_id
  for update;
  if not found or v_venue.owner_id is distinct from v_uid then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_venue.deactivated_at is not null then
    return pg_catalog.jsonb_build_object('ok', true, 'already', true);
  end if;

  if not exists (
    select 1
    from public.venues other
    where other.owner_id = v_uid
      and other.id <> p_venue_id
      and other.deactivated_at is null
      and other.status in ('pending', 'approved')
  ) then
    raise exception 'unit_last' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.groups g
    where g.venue_id = p_venue_id
      and g.cancelled_at is null
      and g.starts_at > pg_catalog.now()
  ) then
    raise exception 'unit_future_groups' using errcode = 'P0001';
  end if;

  if private.venue_pagbank_in_flight(p_venue_id) > 0 then
    raise exception 'unit_pending_money' using errcode = 'P0001';
  end if;

  perform pg_catalog.set_config('scapematch.unit_deactivation', 'on', true);
  update public.venues
  set deactivated_prev_suspended_at = suspended_at,
      suspended_at = coalesce(suspended_at, pg_catalog.now()),
      deactivated_at = pg_catalog.now(),
      deactivated_by = v_uid
  where id = p_venue_id;
  perform pg_catalog.set_config('scapematch.unit_deactivation', 'off', true);

  insert into public.admin_audit_log (
    actor_id, action, target_table, target_id, before_state, after_state
  ) values (
    v_uid,
    'deactivate_unit',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('suspended_at', v_venue.suspended_at),
    pg_catalog.jsonb_build_object('deactivated', true)
  );

  return pg_catalog.jsonb_build_object('ok', true, 'already', false);
end;
$$;

-- Unidades que compartilham a conta: lista para a tela do Parceiro.
create or replace function public.my_pagbank_share_sources(p_venue_id uuid)
returns table (venue_id uuid, venue_name text, city_name text, account_last4 text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v_target from public.venues where id = p_venue_id;
  if not found or v_target.owner_id is distinct from v_uid then
    raise exception 'not owner' using errcode = '42501';
  end if;
  -- Cidade que já tem conta não recebe a oferta.
  if v_target.pagbank_account_id is not null
    and pg_catalog.btrim(v_target.pagbank_account_id) <> ''
  then
    return;
  end if;
  return query
  select s.id, s.name, c.name, right(s.pagbank_account_id, 4)
  from public.venues s
  left join public.cities c on c.id = s.city_id
  where s.owner_id = v_uid
    and s.id <> p_venue_id
    and s.is_test = v_target.is_test
    and s.deactivated_at is null
    and s.pagbank_token_venue_id is null
    and s.pagbank_account_id is not null
    and pg_catalog.btrim(s.pagbank_account_id) <> ''
    and exists (
      select 1 from public.venue_pagbank_tokens t
      where t.venue_id = s.id
        and t.account_id = s.pagbank_account_id
    )
  order by s.created_at;
end;
$$;

revoke all on function public.my_pagbank_share_sources(uuid) from public, anon, authenticated;
grant execute on function public.my_pagbank_share_sources(uuid) to authenticated;

-- "Usar a mesma conta PagBank de outra cidade".
create or replace function public.share_venue_pagbank_account(
  p_venue_id uuid,
  p_source_venue_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_target public.venues%rowtype;
  v_source public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_venue_id is null or p_source_venue_id is null or p_venue_id = p_source_venue_id then
    raise exception 'casa' using errcode = '22023';
  end if;
  -- Trava as duas na mesma ordem para não cruzar com outra chamada.
  perform 1 from public.venues
  where id in (p_venue_id, p_source_venue_id)
  order by id
  for update;
  select * into v_target from public.venues where id = p_venue_id;
  select * into v_source from public.venues where id = p_source_venue_id;
  if v_target.id is null or v_source.id is null
    or v_target.owner_id is distinct from v_uid
    or v_source.owner_id is distinct from v_uid
  then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_target.is_test <> v_source.is_test then
    raise exception 'pagbank_share_invalid' using errcode = 'PB409';
  end if;
  if v_source.pagbank_token_venue_id is not null
    or v_source.deactivated_at is not null
    or v_source.pagbank_account_id is null
    or pg_catalog.btrim(v_source.pagbank_account_id) = ''
    or not exists (
      select 1 from public.venue_pagbank_tokens t
      where t.venue_id = v_source.id
        and t.account_id = v_source.pagbank_account_id
    )
  then
    raise exception 'pagbank_share_invalid'
      using errcode = 'PB409',
            detail = 'a outra cidade ainda não conectou a conta PagBank';
  end if;
  if v_target.pagbank_account_id is not null
    and pg_catalog.btrim(v_target.pagbank_account_id) <> ''
  then
    if v_target.pagbank_account_id = v_source.pagbank_account_id
      and v_target.pagbank_token_venue_id = v_source.id
    then
      return pg_catalog.jsonb_build_object('shared', true, 'already', true);
    end if;
    raise exception 'pagbank_account_exists'
      using errcode = 'PB409',
            detail = 'esta cidade já tem conta PagBank; peça ao suporte para trocar';
  end if;
  if exists (select 1 from public.venue_pagbank_tokens t where t.venue_id = p_venue_id) then
    raise exception 'pagbank_account_exists' using errcode = 'PB409';
  end if;

  perform pg_catalog.set_config('scapematch.pagbank_share', 'on', true);
  update public.venues
  set pagbank_account_id = v_source.pagbank_account_id,
      pagbank_token_venue_id = v_source.id
  where id = p_venue_id;
  perform pg_catalog.set_config('scapematch.pagbank_share', 'off', true);

  perform private.admin_audit(
    v_uid,
    'share_pagbank',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('account_last4', null),
    pg_catalog.jsonb_build_object(
      'account_last4', right(v_source.pagbank_account_id, 4),
      'from_venue', v_source.id
    )
  );
  return pg_catalog.jsonb_build_object(
    'shared', true,
    'already', false,
    'account_last4', right(v_source.pagbank_account_id, 4)
  );
end;
$$;

revoke all on function public.share_venue_pagbank_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.share_venue_pagbank_account(uuid, uuid) to authenticated;

-- O dono reativa a cidade que ele mesmo desativou. Volta como estava:
-- status (aprovada, em análise) não muda, e a suspensão de antes (do Admin)
-- volta junto. Cidade nunca aprovada continua em análise.
create or replace function public.reactivate_my_unit(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_venue public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v_venue
  from public.venues
  where id = p_venue_id
  for update;
  if not found or v_venue.owner_id is distinct from v_uid then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_venue.deactivated_at is null then
    return pg_catalog.jsonb_build_object('ok', true, 'already', true, 'status', v_venue.status);
  end if;

  perform pg_catalog.set_config('scapematch.unit_deactivation', 'on', true);
  update public.venues
  set suspended_at = v_venue.deactivated_prev_suspended_at,
      deactivated_at = null,
      deactivated_by = null,
      deactivated_prev_suspended_at = null
  where id = p_venue_id;
  perform pg_catalog.set_config('scapematch.unit_deactivation', 'off', true);

  insert into public.admin_audit_log (
    actor_id, action, target_table, target_id, before_state, after_state
  ) values (
    v_uid,
    'reactivate_unit',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('deactivated', true),
    pg_catalog.jsonb_build_object(
      'status', v_venue.status,
      'suspended', v_venue.deactivated_prev_suspended_at is not null
    )
  );
  return pg_catalog.jsonb_build_object(
    'ok', true,
    'already', false,
    'status', v_venue.status,
    'suspended', v_venue.deactivated_prev_suspended_at is not null
  );
end;
$$;

revoke all on function public.reactivate_my_unit(uuid) from public, anon, authenticated;
grant execute on function public.reactivate_my_unit(uuid) to authenticated;
