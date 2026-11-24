-- Conta de teste (profiles.is_test, só service_role ou admin aal2) cria
-- outra casa com o mesmo documento, a mesma conta PagBank e a mesma
-- carteira antiga. Conta real segue no índice, na mensagem e na
-- reivindicação. O app não manda a exceção: o trigger lê o perfil.
--
-- Travas do cadastro da casa:
-- * venues_document_digits_active_uidx
-- * private.venues_normalize ('duplicate document')
-- * private.check_venue_duplicates (documento, endereço e nome)
-- * public.find_claimable_venue (o aviso Reivindicar)
-- Travas da conexão PagBank, no banco:
-- * venues.pagbank_account_id único
-- * venues.asaas_wallet_id único (o trigger copia a conta PagBank)
-- Não há índice único de e-mail da casa. O código 42002 da PagBank
-- continua sendo resposta da PagBank, fora deste banco.

drop index if exists public.venues_document_digits_active_uidx;

create unique index venues_document_digits_active_uidx
  on public.venues (document_digits)
  where status <> 'rejected'
    and status <> 'merged'
    and not is_test;

comment on index public.venues_document_digits_active_uidx is
  'Documento único entre casas reais ativas. Casa de teste fica de fora.';

do $$
declare
  v_name text;
begin
  select con.conname
    into v_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'venues'
    and con.contype = 'u'
    and (
      select att.attname
      from unnest(con.conkey) with ordinality as key(attnum, ord)
      join pg_attribute att
        on att.attrelid = rel.oid
       and att.attnum = key.attnum
      order by key.ord
      limit 1
    ) = 'pagbank_account_id';
  if v_name is not null then
    execute format('alter table public.venues drop constraint %I', v_name);
  end if;

  select con.conname
    into v_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'venues'
    and con.contype = 'u'
    and (
      select att.attname
      from unnest(con.conkey) with ordinality as key(attnum, ord)
      join pg_attribute att
        on att.attrelid = rel.oid
       and att.attnum = key.attnum
      order by key.ord
      limit 1
    ) = 'asaas_wallet_id';
  if v_name is not null then
    execute format('alter table public.venues drop constraint %I', v_name);
  end if;
end $$;

create unique index venues_pagbank_account_real_uidx
  on public.venues (pagbank_account_id)
  where pagbank_account_id is not null
    and not is_test;

create unique index venues_asaas_wallet_real_uidx
  on public.venues (asaas_wallet_id)
  where asaas_wallet_id is not null
    and not is_test;

comment on index public.venues_pagbank_account_real_uidx is
  'Uma conta PagBank por casa real. Casa de teste pode repetir.';

comment on index public.venues_asaas_wallet_real_uidx is
  'A carteira copiada da conta PagBank continua única entre casas reais.';

create or replace function private.venues_normalize()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_test boolean;
  v_see_test boolean;
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

  -- Insert de conta real continua vendo casa de teste. Update que não
  -- troca o documento ignora a cópia de teste, senão ligar o PagBank
  -- na casa real quebra depois que a conta de teste repetiu o CPF.
  v_see_test := tg_op = 'INSERT';
  if tg_op = 'UPDATE'
    and new.document_digits is distinct from old.document_digits
  then
    v_see_test := true;
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
        and (not venue.is_test or v_see_test)
    ) then
    raise exception 'duplicate document' using errcode = '23505';
  end if;

  return new;
end;
$$;

create or replace function private.check_venue_duplicates(
  p_documento text,
  p_nome text,
  p_cidade text,
  p_cep text,
  p_numero text
)
returns table (
  conflict boolean,
  conflict_type text,
  venue_id uuid,
  venue_name text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_digits text;
  v_name text;
  v_city text;
  v_cep text;
  v_number text;
  v_has_house boolean;
  v_attempts integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if private.viewer_is_tester() then
    return;
  end if;

  v_digits := public.normalize_document(p_documento);
  v_name := public.normalize_venue_name(p_nome);
  v_cep := regexp_replace(coalesce(p_cep, ''), '\D', '', 'g');
  v_number := public.normalize_address_number(p_numero);

  select city.id
    into v_city
  from public.cities city
  where city.id = lower(btrim(coalesce(p_cidade, '')))
     or lower(extensions.unaccent('extensions.unaccent'::regdictionary, city.name)) = lower(
       extensions.unaccent(
         'extensions.unaccent'::regdictionary,
         btrim(coalesce(p_cidade, ''))
       )
     )
  order by case
    when city.id = lower(btrim(coalesce(p_cidade, ''))) then 0
    else 1
  end
  limit 1;

  select exists (
    select 1
    from public.venues owned
    where owned.owner_id = v_uid
      and owned.status in ('pending', 'approved')
  ) into v_has_house;

  if v_digits is not null and not v_has_house then
    select count(*)
      into v_attempts
    from private.venue_duplicate_attempts attempt
    where attempt.user_id = v_uid
      and attempt.checked_at > now() - interval '1 hour';
    if v_attempts >= 10 then
      raise exception 'too many attempts' using errcode = 'P0001';
    end if;
    insert into private.venue_duplicate_attempts (user_id) values (v_uid);

    return query
    select
      true,
      'documento'::text,
      case when venue.status = 'approved' then venue.id else null end,
      case when venue.status = 'approved' then venue.name else null end
    from public.venues venue
    where venue.document_digits = v_digits
      and venue.status in ('pending', 'approved')
    order by case when venue.status = 'approved' then 0 else 1 end, venue.created_at
    limit 1;
  end if;

  return query
  select
    true,
    'endereço'::text,
    venue.id,
    venue.name
  from public.venues venue
  where venue.status = 'approved'
    and char_length(v_cep) = 8
    and venue.postal_code = v_cep
    and venue.address_number_normalized = v_number
  order by venue.created_at
  limit 3;

  return query
  select
    true,
    'nome parecido'::text,
    venue.id,
    venue.name
  from public.venues venue
  where venue.status = 'approved'
    and v_city is not null
    and venue.city_id = v_city
    and v_name <> ''
    and venue.name_normalized <> ''
    and (
      venue.name_normalized = v_name
      or (
        char_length(v_name) >= 4
        and (
          venue.name_normalized like v_name || ' %'
          or venue.name_normalized like '% ' || v_name
          or venue.name_normalized like '% ' || v_name || ' %'
          or v_name like venue.name_normalized || ' %'
          or v_name like '% ' || venue.name_normalized
          or v_name like '% ' || venue.name_normalized || ' %'
        )
      )
      or (
        char_length(v_name) >= 4
        and char_length(venue.name_normalized) >= 4
        and extensions.similarity(venue.name_normalized, v_name) >= 0.5
      )
    )
  order by extensions.similarity(venue.name_normalized, v_name) desc, venue.name
  limit 3;
end;
$$;

create or replace function public.find_claimable_venue(p_document text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_digits text;
  v_house public.venues%rowtype;
  v_attempts integer;
  v_email text;
  v_phone text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if private.viewer_is_tester() then
    return pg_catalog.jsonb_build_object('path', 'none');
  end if;
  v_digits := public.normalize_document(p_document);
  if v_digits is null or char_length(v_digits) not in (11, 14) then
    return pg_catalog.jsonb_build_object('path', 'none');
  end if;

  select count(*)
    into v_attempts
  from private.venue_duplicate_attempts attempt
  where attempt.user_id = v_uid
    and attempt.checked_at > pg_catalog.now() - interval '1 hour';
  if v_attempts >= 10 then
    raise exception 'too many attempts' using errcode = 'P0001';
  end if;
  insert into private.venue_duplicate_attempts (user_id) values (v_uid);

  select venue.*
    into v_house
  from public.venues venue
  where venue.document_digits = v_digits
    and venue.status not in ('rejected', 'merged')
  order by case when venue.status = 'approved' then 0 else 1 end
  limit 1;

  if not found then
    return pg_catalog.jsonb_build_object('path', 'none');
  end if;
  if v_house.owner_id = v_uid then
    return pg_catalog.jsonb_build_object(
      'path', 'already_owner',
      'venue_id', v_house.id,
      'name', v_house.name
    );
  end if;
  if v_house.claimed_at is not null or v_house.status <> 'approved' then
    return pg_catalog.jsonb_build_object('path', 'already_claimed');
  end if;

  v_email := nullif(pg_catalog.btrim(coalesce(v_house.official_email, '')), '');
  v_phone := nullif(pg_catalog.btrim(coalesce(v_house.official_phone, '')), '');
  return pg_catalog.jsonb_build_object(
    'path', case when v_email is null and v_phone is null then 'manual' else 'otp' end,
    'venue_id', v_house.id,
    'name', v_house.name,
    'city_id', v_house.city_id,
    'neighborhood', v_house.neighborhood,
    'has_official_email', v_email is not null,
    'has_official_phone', v_phone is not null
  );
end;
$$;
