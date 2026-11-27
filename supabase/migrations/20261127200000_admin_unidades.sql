-- Admin: compartilhar a conta PagBank entre cidades do mesmo dono e reativar
-- cidade removida (decisão do Nícolas, 27/11: "Sim, o Admin também pode").
-- Exige admin com MFA (private.admin_require) e grava em admin_audit_log.
-- Só acrescenta funções; a do dono passa a usar o mesmo núcleo.

-- Núcleo do compartilhamento. Quem chama confere quem pode (dono ou admin).
create or replace function private.share_venue_pagbank_core(
  p_venue_id uuid,
  p_source_venue_id uuid,
  p_actor uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.venues%rowtype;
  v_source public.venues%rowtype;
begin
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
  if v_target.id is null or v_source.id is null then
    raise exception 'casa' using errcode = '22023';
  end if;
  if v_target.owner_id is null or v_target.owner_id is distinct from v_source.owner_id then
    raise exception 'pagbank_share_invalid'
      using errcode = 'PB409',
            detail = 'as duas cidades precisam ser do mesmo dono';
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
            detail = 'esta cidade já tem conta PagBank; desconecte antes';
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
    p_actor,
    p_action,
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

revoke all on function private.share_venue_pagbank_core(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

-- Dono: as duas cidades precisam ser dele.
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
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.venues where id = p_venue_id and owner_id = v_uid
  ) or not exists (
    select 1 from public.venues where id = p_source_venue_id and owner_id = v_uid
  ) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return private.share_venue_pagbank_core(
    p_venue_id, p_source_venue_id, v_uid, 'share_pagbank'
  );
end;
$$;

revoke all on function public.share_venue_pagbank_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.share_venue_pagbank_account(uuid, uuid) to authenticated;

-- Admin: mesmas regras (mesmo dono, origem com conta), com MFA.
create or replace function public.admin_share_venue_pagbank_account(
  p_venue_id uuid,
  p_source_venue_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
begin
  return private.share_venue_pagbank_core(
    p_venue_id, p_source_venue_id, v_uid, 'admin_share_pagbank'
  );
end;
$$;

revoke all on function public.admin_share_venue_pagbank_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_share_venue_pagbank_account(uuid, uuid) to authenticated;

-- Admin: reativar cidade removida (pelo dono ou pelo Admin). Volta como
-- estava: o status não muda. Se a cidade estava suspensa antes da remoção,
-- continua suspensa. Sem saber o estado de antes (cidade antiga sem
-- auditoria), continua suspensa e o Admin decide tirar a suspensão.
create or replace function public.admin_reactivate_unit(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_venue public.venues%rowtype;
  v_prev timestamptz;
  v_known boolean := false;
  v_audit jsonb;
  v_after timestamptz;
begin
  select * into v_venue
  from public.venues
  where id = p_venue_id
  for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v_venue.deactivated_at is null then
    return pg_catalog.jsonb_build_object(
      'ok', true, 'already', true, 'status', v_venue.status,
      'suspended', v_venue.suspended_at is not null
    );
  end if;

  if v_venue.deactivated_prev_suspended_at is not null then
    v_prev := v_venue.deactivated_prev_suspended_at;
    v_known := true;
  else
    select l.before_state into v_audit
    from public.admin_audit_log l
    where l.action = 'deactivate_unit'
      and l.target_table = 'venues'
      and l.target_id = p_venue_id::text
      and l.created_at >= v_venue.deactivated_at - interval '1 minute'
    order by l.created_at desc
    limit 1;
    if v_audit is not null and v_audit ? 'suspended_at' then
      v_prev := (v_audit ->> 'suspended_at')::timestamptz;
      v_known := true;
    end if;
  end if;
  v_after := case when v_known then v_prev else v_venue.suspended_at end;

  perform pg_catalog.set_config('scapematch.unit_deactivation', 'on', true);
  update public.venues
  set suspended_at = v_after,
      deactivated_at = null,
      deactivated_by = null,
      deactivated_prev_suspended_at = null
  where id = p_venue_id;
  perform pg_catalog.set_config('scapematch.unit_deactivation', 'off', true);

  perform private.admin_audit(
    v_uid,
    'admin_reactivate_unit',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object(
      'deactivated_at', v_venue.deactivated_at,
      'deactivated_by_owner', v_venue.deactivated_by is not distinct from v_venue.owner_id,
      'suspended_at', v_venue.suspended_at
    ),
    pg_catalog.jsonb_build_object(
      'suspended_at', v_after,
      'previous_known', v_known
    )
  );
  return pg_catalog.jsonb_build_object(
    'ok', true,
    'already', false,
    'status', v_venue.status,
    'suspended', v_after is not null,
    'previous_known', v_known
  );
end;
$$;

revoke all on function public.admin_reactivate_unit(uuid) from public, anon, authenticated;
grant execute on function public.admin_reactivate_unit(uuid) to authenticated;

-- Admin: estado de unidade da casa (removida, conta compartilhada) e as
-- cidades do mesmo dono que podem emprestar a conta.
create or replace function public.admin_venue_units(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v public.venues%rowtype;
  v_shared_from text;
begin
  select * into v from public.venues where id = p_venue_id;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v.pagbank_token_venue_id is not null then
    select s.name into v_shared_from
    from public.venues s where s.id = v.pagbank_token_venue_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'venue_id', v.id,
    'deactivated', v.deactivated_at is not null,
    'deactivated_at', v.deactivated_at,
    'deactivated_by_owner',
      v.deactivated_at is not null
      and v.deactivated_by is not distinct from v.owner_id,
    'has_account', v.pagbank_account_id is not null
      and pg_catalog.btrim(v.pagbank_account_id) <> '',
    'shared_from_id', v.pagbank_token_venue_id,
    'shared_from_name', v_shared_from,
    'share_sources', case
      when v.owner_id is null
        or (v.pagbank_account_id is not null and pg_catalog.btrim(v.pagbank_account_id) <> '')
      then '[]'::jsonb
      else coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'venue_id', s.id,
          'venue_name', s.name,
          'city_name', c.name,
          'account_last4', right(s.pagbank_account_id, 4)
        ) order by s.created_at)
        from public.venues s
        left join public.cities c on c.id = s.city_id
        where s.owner_id = v.owner_id
          and s.id <> v.id
          and s.is_test = v.is_test
          and s.deactivated_at is null
          and s.pagbank_token_venue_id is null
          and s.pagbank_account_id is not null
          and pg_catalog.btrim(s.pagbank_account_id) <> ''
          and exists (
            select 1 from public.venue_pagbank_tokens t
            where t.venue_id = s.id and t.account_id = s.pagbank_account_id
          )
      ), '[]'::jsonb)
    end
  );
end;
$$;

revoke all on function public.admin_venue_units(uuid) from public, anon, authenticated;
grant execute on function public.admin_venue_units(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Conta de recebimento ÚNICA por casa (esclarecimento do Nícolas, 27/11:
-- "a conta pra saque é única e fica por conta da casa escolher"). A casa
-- (o dono) conecta uma conta PagBank em qualquer cidade e todas as cidades
-- dela passam a receber por essa conta. O CNPJ pode ser o mesmo em todas
-- ou um por cidade. Entre donos diferentes continua bloqueado.
-- ---------------------------------------------------------------------------

-- Cidade da casa que guarda o token da conta de recebimento (a "raiz").
create or replace function private.house_pagbank_root(p_owner uuid, p_is_test boolean, p_except uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
  from public.venues s
  where s.owner_id = p_owner
    and s.is_test = p_is_test
    and s.id is distinct from p_except
    and s.pagbank_token_venue_id is null
    and s.pagbank_account_id is not null
    and pg_catalog.btrim(s.pagbank_account_id) <> ''
    and s.status not in ('rejected', 'merged')
    and exists (
      select 1 from public.venue_pagbank_tokens t
      where t.venue_id = s.id and t.account_id = s.pagbank_account_id
    )
  order by s.created_at
  limit 1;
$$;

revoke all on function private.house_pagbank_root(uuid, boolean, uuid)
  from public, anon, authenticated, service_role;

-- Liga à conta da casa as cidades do dono que ainda não têm conta.
create or replace function private.link_house_cities(p_root uuid, p_actor uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_root public.venues%rowtype;
  v_count integer;
begin
  select * into v_root from public.venues where id = p_root;
  if not found or v_root.owner_id is null
    or v_root.pagbank_account_id is null
    or v_root.pagbank_token_venue_id is not null
  then
    return 0;
  end if;
  perform pg_catalog.set_config('scapematch.pagbank_share', 'on', true);
  with linked as (
    update public.venues o
    set pagbank_account_id = v_root.pagbank_account_id,
        pagbank_token_venue_id = v_root.id
    where o.owner_id = v_root.owner_id
      and o.id <> v_root.id
      and o.is_test = v_root.is_test
      and o.status not in ('rejected', 'merged')
      and (o.pagbank_account_id is null or pg_catalog.btrim(o.pagbank_account_id) = '')
      and not exists (select 1 from public.venue_pagbank_tokens t where t.venue_id = o.id)
    returning o.id
  )
  select count(*) into v_count from linked;
  perform pg_catalog.set_config('scapematch.pagbank_share', 'off', true);
  if v_count > 0 then
    perform private.admin_audit(
      p_actor, 'link_house_pagbank', 'venues', p_root::text,
      pg_catalog.jsonb_build_object('linked', 0),
      pg_catalog.jsonb_build_object(
        'linked', v_count,
        'account_last4', right(v_root.pagbank_account_id, 4)
      )
    );
  end if;
  return v_count;
end;
$$;

revoke all on function private.link_house_cities(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Cidade nova de uma casa que já tem conta: já nasce recebendo por ela.
create or replace function private.venues_link_house_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_root uuid;
begin
  if new.owner_id is null
    or (new.pagbank_account_id is not null and pg_catalog.btrim(new.pagbank_account_id) <> '')
  then
    return null;
  end if;
  v_root := private.house_pagbank_root(new.owner_id, new.is_test, new.id);
  if v_root is not null then
    perform private.link_house_cities(v_root, new.owner_id);
  end if;
  return null;
end;
$$;

revoke all on function private.venues_link_house_account()
  from public, anon, authenticated, service_role;

drop trigger if exists venues_link_house_account on public.venues;
create trigger venues_link_house_account
  after insert on public.venues
  for each row execute function private.venues_link_house_account();

-- Conectar: uma conta por casa.
--  * a casa já tem conta e é a mesma: renova o token na cidade que guarda o
--    token e liga esta cidade a ela;
--  * a casa já tem outra conta: 409 pagbank_account_exists (trocar a conta
--    da casa é desconectar e conectar de novo);
--  * primeira conta da casa: grava aqui e liga as outras cidades.
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
  v_pointer uuid;
  v_root uuid;
  v_root_account text;
  v_linked integer := 0;
begin
  if p_venue_id is null or p_actor is null or v_account = '' then
    raise exception 'conta' using errcode = '22023';
  end if;
  select v.pagbank_account_id, v.is_test, v.owner_id, v.pagbank_token_venue_id
    into v_current, v_test, v_owner, v_pointer
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

  -- A mesma conta não liga a casa de outro dono. Casa de teste fica de fora.
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
            detail = 'essa conta PagBank já está ligada a casa de outro dono';
  end if;

  -- Conta da casa já existe em outra cidade.
  if v_owner is not null then
    v_root := coalesce(v_pointer, private.house_pagbank_root(v_owner, v_test, p_venue_id));
    if v_root = p_venue_id then
      v_root := null;
    end if;
  end if;
  if v_root is not null then
    select pagbank_account_id into v_root_account
    from public.venues where id = v_root for update;
    if v_root_account is distinct from v_account then
      raise exception 'pagbank_account_exists'
        using errcode = 'PB409',
              detail = 'a casa já tem outra conta de recebimento';
    end if;
    perform pg_catalog.set_config('scapematch.pagbank_share', 'on', true);
    update public.venues
    set pagbank_account_id = v_account,
        pagbank_token_venue_id = v_root
    where id = p_venue_id;
    perform pg_catalog.set_config('scapematch.pagbank_share', 'off', true);
    perform public.store_venue_pagbank_tokens(
      v_root, p_access_token, p_refresh_token, p_expires_at
    );
    update public.venue_pagbank_tokens
    set account_id = v_account
    where venue_id = v_root;
    perform private.admin_audit(
      p_actor, 'connect_pagbank', 'venues', p_venue_id::text,
      pg_catalog.jsonb_build_object('account_last4', right(coalesce(v_current, ''), 4)),
      pg_catalog.jsonb_build_object('account_last4', right(v_account, 4), 'house_root', v_root)
    );
    v_linked := private.link_house_cities(v_root, p_actor);
    return pg_catalog.jsonb_build_object(
      'venue_id', p_venue_id,
      'account_last4', right(v_account, 4),
      'renewed', true,
      'house_root', v_root,
      'linked', v_linked
    );
  end if;

  begin
    update public.venues
    set pagbank_account_id = v_account
    where id = p_venue_id
      and pagbank_account_id is distinct from v_account;
  exception when unique_violation then
    raise exception 'pagbank_account_in_use'
      using errcode = 'PB409',
            detail = 'essa conta PagBank já está ligada a outra casa';
  end;

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
  v_linked := private.link_house_cities(p_venue_id, p_actor);
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'account_last4', right(v_account, 4),
    'renewed', v_current is not null and v_current = v_account,
    'linked', v_linked
  );
end;
$$;

-- Desconectar a cidade que guarda o token desconecta a conta da casa: as
-- cidades ligadas a ela saem junto (nenhuma fica recebendo por uma conta
-- sem token). Trava se houver dinheiro a caminho em qualquer uma delas.
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
  v_linked integer := 0;
  v_city uuid;
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
    -- Só esta cidade sai da conta da casa; o token é da outra cidade.
    update public.venues
    set pagbank_account_id = null,
        pagbank_token_venue_id = null
    where id = p_venue_id;
    perform private.admin_audit(
      p_actor, 'disconnect_pagbank', 'venues', p_venue_id::text,
      pg_catalog.jsonb_build_object('account_last4', right(v_current, 4), 'shared', true),
      pg_catalog.jsonb_build_object('account_last4', null, 'by_admin', coalesce(p_admin, false))
    );
    return pg_catalog.jsonb_build_object(
      'disconnected', true,
      'shared', true,
      'account_last4', right(v_current, 4)
    );
  end if;

  for v_city in
    select o.id from public.venues o
    where o.pagbank_token_venue_id = p_venue_id
    order by o.id
    for update
  loop
    v_busy := private.venue_pagbank_in_flight(v_city);
    if v_busy > 0 then
      raise exception 'pagbank_in_flight'
        using errcode = 'PB409',
              detail = pg_catalog.format('%s item(ns) a caminho em outra cidade da casa', v_busy);
    end if;
  end loop;

  with unlinked as (
    update public.venues o
    set pagbank_account_id = null,
        pagbank_token_venue_id = null
    where o.pagbank_token_venue_id = p_venue_id
    returning o.id
  )
  select count(*) into v_linked from unlinked;

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
    pg_catalog.jsonb_build_object('account_last4', right(v_current, 4), 'cities', v_linked),
    pg_catalog.jsonb_build_object('account_last4', null, 'by_admin', coalesce(p_admin, false))
  );
  return pg_catalog.jsonb_build_object(
    'disconnected', true,
    'account_last4', right(v_current, 4),
    'cities', v_linked
  );
end;
$$;

-- Modelo para cadastrar outra cidade: os dados da casa (inclusive o
-- documento, para a opção "mesmo CNPJ em todas as cidades"). Só o dono.
create or replace function public.my_unit_template(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select * into v from public.venues where id = p_venue_id;
  if not found or v.owner_id is distinct from v_uid then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return pg_catalog.jsonb_build_object(
    'name', v.name,
    'phone', v.phone,
    'document_kind', v.document_kind,
    'document_number', v.document_number,
    'company_type', v.company_type,
    'category', v.category,
    'income_value', v.income_value
  );
end;
$$;

revoke all on function public.my_unit_template(uuid) from public, anon, authenticated;
grant execute on function public.my_unit_template(uuid) to authenticated;
