-- Duplicata de casa.
-- Documento repetido não entra. CEP + número, ou nome parecido na mesma
-- cidade, só avisa: o cadastro pode seguir com possible_duplicate_of.
-- A função pública não é security definer. Quem lê documento e casa
-- pendente é private.check_venue_duplicates, fora da API. A resposta
-- traz só o conflito, o tipo e o id/nome da casa aprovada.

create schema if not exists extensions;
create schema if not exists private;

create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

grant usage on schema extensions to postgres, anon, authenticated, service_role;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

comment on schema private is
  'Funções que atravessam o RLS. Este schema não entra na API.';

create or replace function public.normalize_document(p_document text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(coalesce(p_document, ''), '\D', '', 'g'), '');
$$;

create or replace function public.normalize_address_number(p_number text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when cleaned in ('', 'sn', 'snum', 'semnumero') then 'sn'
    when digits = '' then 'sn'
    else digits
  end
  from (
    select
      regexp_replace(lower(coalesce(p_number, '')), '[^a-z0-9]', '', 'g') as cleaned,
      regexp_replace(
        regexp_replace(lower(coalesce(p_number, '')), '[^a-z0-9]', '', 'g'),
        '^[a-z]+',
        ''
      ) as digits
  ) shaped;
$$;

-- Tira acento, minúscula e o que não distingue uma casa da outra
-- ("escape room", "ltda", "s.a." e o resto do sufixo).
create or replace function public.normalize_venue_name(p_name text)
returns text
language sql
stable
set search_path = ''
as $$
  select trim(both from regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_name, ''))),
            '[^a-z0-9]+',
            ' ',
            'g'
          ),
          '\m(escape rooms|escape room|sala de escape|casa de escape)\M',
          ' ',
          'g'
        ),
        '\ms a\M',
        ' ',
        'g'
      ),
      '\m(ltda|limitada|eireli|epp|me|sa|sociedade|anonima|escape|room|rooms)\M',
      ' ',
      'g'
    ),
    '\s+',
    ' ',
    'g'
  ));
$$;

revoke all on function public.normalize_document(text) from public, anon, authenticated;
revoke all on function public.normalize_address_number(text) from public, anon, authenticated;
revoke all on function public.normalize_venue_name(text) from public, anon, authenticated;
grant execute on function public.normalize_document(text) to service_role;
grant execute on function public.normalize_address_number(text) to service_role;
grant execute on function public.normalize_venue_name(text) to service_role;

alter table public.venues
  add column document_digits text,
  add column name_normalized text,
  add column address_number_normalized text,
  add column possible_duplicate_of uuid,
  add column merged_into uuid;

alter table public.venues
  add constraint venues_possible_duplicate_fkey
  foreign key (possible_duplicate_of) references public.venues (id) on delete set null,
  add constraint venues_merged_into_fkey
  foreign key (merged_into) references public.venues (id) on delete set null,
  add constraint venues_possible_duplicate_not_self
  check (possible_duplicate_of is null or possible_duplicate_of <> id),
  add constraint venues_merged_into_not_self
  check (merged_into is null or merged_into <> id);

do $$
declare
  v_name text;
begin
  select con.conname
    into v_name
  from pg_constraint con
  where con.conrelid = 'public.venues'::regclass
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) like '%pending%'
    and pg_get_constraintdef(con.oid) like '%approved%'
    and pg_get_constraintdef(con.oid) like '%rejected%';
  if v_name is not null then
    execute format('alter table public.venues drop constraint %I', v_name);
  end if;
end $$;

alter table public.venues
  add constraint venues_status_check
  check (status in ('pending', 'approved', 'rejected', 'merged'));

comment on column public.venues.document_digits is
  'Documento só com dígitos. Único enquanto a casa não foi recusada nem mesclada.';
comment on column public.venues.name_normalized is
  'Nome sem acento, minúsculo, sem escape room nem sufixo societário.';
comment on column public.venues.possible_duplicate_of is
  'Casa aprovada que o cadastro avisou como parecida. Não bloqueia.';
comment on column public.venues.merged_into is
  'Casa aprovada que ficou no lugar desta, quando o admin mesclou.';

create or replace function public.venues_normalize()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
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
    if v_uid is not null and not public.is_admin() then
      new.merged_into := null;
    end if;
  elsif v_uid is not null and not public.is_admin() then
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

  if new.status not in ('rejected', 'merged')
    and new.document_digits is not null
    and exists (
      select 1
      from public.venues venue
      where venue.document_digits = new.document_digits
        and venue.status not in ('rejected', 'merged')
        and venue.id is distinct from new.id
    ) then
    raise exception 'duplicate document' using errcode = '23505';
  end if;

  return new;
end;
$$;

drop trigger if exists venues_normalize on public.venues;
create trigger venues_normalize
  before insert or update on public.venues
  for each row execute function public.venues_normalize();

revoke all on function public.venues_normalize() from public, anon, authenticated;

update public.venues
set name = name;

alter table public.venues
  alter column document_digits set not null,
  alter column name_normalized set not null,
  alter column address_number_normalized set not null;

alter table public.venues
  add constraint venues_document_digits_shape
  check (document_digits ~ '^[0-9]{11}$' or document_digits ~ '^[0-9]{14}$');

create unique index venues_document_digits_active_uidx
  on public.venues (document_digits)
  where status <> 'rejected' and status <> 'merged';

create index venues_approved_name_trgm
  on public.venues using gin (name_normalized extensions.gin_trgm_ops)
  where status = 'approved' and name_normalized <> '';

create index venues_approved_name_city
  on public.venues (city_id, name_normalized)
  where status = 'approved';

create index venues_approved_address
  on public.venues (postal_code, address_number_normalized)
  where status = 'approved';

create index venues_by_possible_duplicate
  on public.venues (possible_duplicate_of);

create index venues_by_merged_into
  on public.venues (merged_into);

-- Coluna nova não herda o grant antigo. Documento normalizado fica de fora.
revoke select (
  document_digits,
  name_normalized,
  address_number_normalized,
  possible_duplicate_of,
  merged_into
) on table public.venues from anon, authenticated;

-- Consulta de documento: quem já tem casa ativa não recebe resposta,
-- e cada usuário sem casa só consulta 10 vezes por hora.
create table private.venue_duplicate_attempts (
  user_id uuid not null,
  checked_at timestamptz not null default now()
);

create index venue_duplicate_attempts_by_user
  on private.venue_duplicate_attempts (user_id, checked_at desc);

revoke all on table private.venue_duplicate_attempts from public, anon, authenticated;

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

create or replace function public.check_venue_duplicates(
  documento text,
  nome text,
  cidade text,
  cep text,
  numero text
)
returns table (
  conflict boolean,
  conflict_type text,
  venue_id uuid,
  venue_name text
)
language sql
volatile
security invoker
set search_path = ''
as $$
  select
    found.conflict,
    found.conflict_type,
    found.venue_id,
    found.venue_name
  from private.check_venue_duplicates(documento, nome, cidade, cep, numero) as found;
$$;

comment on function public.check_venue_duplicates(text, text, text, text, text) is
  'Avisa duplicata. Só conflito, tipo, id e nome público da casa aprovada.';

revoke all on function private.check_venue_duplicates(text, text, text, text, text)
  from public, anon;
revoke all on function public.check_venue_duplicates(text, text, text, text, text)
  from public, anon;
grant execute on function private.check_venue_duplicates(text, text, text, text, text)
  to authenticated, service_role;
grant execute on function public.check_venue_duplicates(text, text, text, text, text)
  to authenticated, service_role;

-- O authenticated não lê as colunas. Dono e admin leem por aqui.
create or replace function public.venue_link_status(p_venue_id uuid)
returns table (
  possible_duplicate_of uuid,
  merged_into uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not (public.owns_venue(p_venue_id) or public.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return query
  select venue.possible_duplicate_of, venue.merged_into
  from public.venues venue
  where venue.id = p_venue_id;
end;
$$;

revoke all on function public.venue_link_status(uuid) from public, anon;
grant execute on function public.venue_link_status(uuid) to authenticated, service_role;

create table public.venue_claims (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  claimant_id uuid not null references auth.users (id) on delete cascade,
  pending_venue_id uuid references public.venues (id) on delete set null,
  note text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (char_length(note) <= 500),
  check (pending_venue_id is null or pending_venue_id <> venue_id)
);

comment on table public.venue_claims is
  'Pedido "Esta casa é minha?". O admin aprova ou recusa. Anon não lê.';

create index venue_claims_by_venue on public.venue_claims (venue_id);
create index venue_claims_by_claimant on public.venue_claims (claimant_id);
create unique index venue_claims_one_open
  on public.venue_claims (venue_id, claimant_id)
  where status = 'pending';

create or replace function public.venue_claims_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if tg_op = 'INSERT' then
    if not public.is_admin() then
      new.claimant_id := v_uid;
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
    end if;
    if not exists (
      select 1
      from public.venues venue
      where venue.id = new.venue_id
        and venue.status = 'approved'
    ) then
      raise exception 'venue not approved' using errcode = 'P0002';
    end if;
    if exists (
      select 1
      from public.venues venue
      where venue.id = new.venue_id
        and venue.owner_id = new.claimant_id
    ) then
      raise exception 'already owner' using errcode = 'P0001';
    end if;
    if new.pending_venue_id is not null and not exists (
      select 1
      from public.venues venue
      where venue.id = new.pending_venue_id
        and venue.owner_id = new.claimant_id
        and venue.status = 'pending'
    ) then
      raise exception 'pending venue not owned' using errcode = '42501';
    end if;
    return new;
  end if;

  if not public.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  new.venue_id := old.venue_id;
  new.claimant_id := old.claimant_id;
  new.pending_venue_id := old.pending_venue_id;
  new.note := old.note;
  new.created_at := old.created_at;
  if new.status is distinct from old.status then
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  else
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists venue_claims_guard on public.venue_claims;
create trigger venue_claims_guard
  before insert or update on public.venue_claims
  for each row execute function public.venue_claims_guard();

revoke all on function public.venue_claims_guard() from public, anon, authenticated;

alter table public.venue_claims enable row level security;
alter table public.venue_claims force row level security;

revoke all on table public.venue_claims from public, anon, authenticated;
grant select, insert on table public.venue_claims to authenticated;
grant update (status, reviewed_by, reviewed_at) on table public.venue_claims to authenticated;
grant all on table public.venue_claims to service_role;

create policy venue_claims_select on public.venue_claims
  for select to authenticated
  using (
    claimant_id = (select auth.uid())
    or (select public.is_admin())
  );

create policy venue_claims_insert on public.venue_claims
  for insert to authenticated
  with check (
    claimant_id = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and exists (
      select 1
      from public.venues venue
      where venue.id = venue_claims.venue_id
        and venue.status = 'approved'
    )
    and (
      venue_claims.pending_venue_id is null
      or exists (
        select 1
        from public.venues venue
        where venue.id = venue_claims.pending_venue_id
          and venue.owner_id = (select auth.uid())
          and venue.status = 'pending'
      )
    )
  );

create policy venue_claims_update on public.venue_claims
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create or replace function private.request_venue_claim(
  p_venue_id uuid,
  p_note text,
  p_pending_venue_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_note text := left(btrim(coalesce(p_note, '')), 500);
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1
    from public.venues venue
    where venue.id = p_venue_id
      and venue.status = 'approved'
      and venue.owner_id is distinct from v_uid
  ) then
    raise exception 'venue not approved' using errcode = 'P0002';
  end if;
  if p_pending_venue_id is not null and not exists (
    select 1
    from public.venues venue
    where venue.id = p_pending_venue_id
      and venue.owner_id = v_uid
      and venue.status = 'pending'
  ) then
    raise exception 'pending venue not owned' using errcode = '42501';
  end if;

  insert into public.venue_claims (venue_id, claimant_id, pending_venue_id, note)
  values (p_venue_id, v_uid, p_pending_venue_id, v_note)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'claim already open' using errcode = '23505';
end;
$$;

create or replace function public.request_venue_claim(
  venue_id uuid,
  note text default '',
  pending_venue_id uuid default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.request_venue_claim(venue_id, note, pending_venue_id);
$$;

create or replace function private.review_venue(
  p_venue_id uuid,
  p_decision text,
  p_merge_into uuid
)
returns table (
  venue_id uuid,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_status text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected', 'merged') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;

  select venue.status
    into v_status
  from public.venues venue
  where venue.id = p_venue_id
  for update;

  if not found then
    raise exception 'venue not found' using errcode = 'P0002';
  end if;
  if v_status <> 'pending' then
    raise exception 'venue not pending' using errcode = 'P0001';
  end if;

  if p_decision = 'merged' then
    if p_merge_into is null or p_merge_into = p_venue_id or not exists (
      select 1
      from public.venues venue
      where venue.id = p_merge_into
        and venue.status = 'approved'
    ) then
      raise exception 'invalid merge target' using errcode = '23503';
    end if;
    update public.venues as house
    set
      status = 'merged',
      merged_into = p_merge_into,
      reviewed_by = v_uid,
      reviewed_at = now()
    where house.id = p_venue_id;
  else
    update public.venues as house
    set
      status = p_decision,
      reviewed_by = v_uid,
      reviewed_at = now()
    where house.id = p_venue_id;
  end if;

  return query
  select p_venue_id, p_decision;
exception
  when unique_violation then
    raise exception 'duplicate document' using errcode = '23505';
end;
$$;

create or replace function public.review_venue(
  venue_id uuid,
  decision text,
  merge_into uuid default null
)
returns table (
  venue_id uuid,
  status text
)
language sql
security invoker
set search_path = ''
as $$
  select reviewed.venue_id, reviewed.status
  from private.review_venue(venue_id, decision, merge_into) as reviewed;
$$;

create or replace function private.review_venue_claim(
  p_claim_id uuid,
  p_decision text
)
returns table (
  claim_id uuid,
  status text,
  venue_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_claim public.venue_claims%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not public.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;

  select claim.*
    into v_claim
  from public.venue_claims claim
  where claim.id = p_claim_id
  for update;

  if not found then
    raise exception 'claim not found' using errcode = 'P0002';
  end if;
  if v_claim.status <> 'pending' then
    raise exception 'claim not pending' using errcode = 'P0001';
  end if;

  update public.venue_claims as claim
  set
    status = p_decision,
    reviewed_by = v_uid,
    reviewed_at = now()
  where claim.id = p_claim_id;

  if p_decision = 'approved' then
    update public.venues as house
    set owner_id = v_claim.claimant_id
    where house.id = v_claim.venue_id
      and house.status = 'approved';

    if v_claim.pending_venue_id is not null then
      update public.venues as pending_house
      set
        status = 'merged',
        merged_into = v_claim.venue_id,
        reviewed_by = v_uid,
        reviewed_at = now()
      where pending_house.id = v_claim.pending_venue_id
        and pending_house.owner_id = v_claim.claimant_id
        and pending_house.status = 'pending';
    end if;
  end if;

  return query
  select p_claim_id, p_decision, v_claim.venue_id;
end;
$$;

create or replace function public.review_venue_claim(
  claim_id uuid,
  decision text
)
returns table (
  claim_id uuid,
  status text,
  venue_id uuid
)
language sql
security invoker
set search_path = ''
as $$
  select reviewed.claim_id, reviewed.status, reviewed.venue_id
  from private.review_venue_claim(claim_id, decision) as reviewed;
$$;

revoke all on function private.request_venue_claim(uuid, text, uuid) from public, anon;
revoke all on function public.request_venue_claim(uuid, text, uuid) from public, anon;
revoke all on function private.review_venue(uuid, text, uuid) from public, anon;
revoke all on function public.review_venue(uuid, text, uuid) from public, anon;
revoke all on function private.review_venue_claim(uuid, text) from public, anon;
revoke all on function public.review_venue_claim(uuid, text) from public, anon;

grant execute on function private.request_venue_claim(uuid, text, uuid)
  to authenticated, service_role;
grant execute on function public.request_venue_claim(uuid, text, uuid)
  to authenticated, service_role;
grant execute on function private.review_venue(uuid, text, uuid)
  to authenticated, service_role;
grant execute on function public.review_venue(uuid, text, uuid)
  to authenticated, service_role;
grant execute on function private.review_venue_claim(uuid, text)
  to authenticated, service_role;
grant execute on function public.review_venue_claim(uuid, text)
  to authenticated, service_role;
