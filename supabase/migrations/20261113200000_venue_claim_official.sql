-- Reivindicação oficial de um perfil que já existe.
-- O CNPJ acha a casa. O código vai para o e-mail ou o telefone oficial
-- gravados no perfil, nunca para o que a pessoa digitou no cadastro.
-- Sem esses contatos, o pedido fica pendente para o admin.
-- Não aplicar no projeto remoto neste PR.

alter table public.venues
  add column if not exists official_email text,
  add column if not exists official_phone text,
  add column if not exists claimed_at timestamptz;

alter table public.venues
  drop constraint if exists venues_official_email_check,
  drop constraint if exists venues_official_phone_check;

alter table public.venues
  add constraint venues_official_email_check check (
    official_email is null
    or (
      char_length(official_email) between 6 and 160
      and official_email = lower(official_email)
      and official_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
  ),
  add constraint venues_official_phone_check check (
    official_phone is null
    or official_phone ~ '^[0-9]{10,13}$'
  );

comment on column public.venues.official_email is
  'E-mail oficial do perfil. O código de posse sai daqui. O cadastro não grava o que a pessoa digitou.';
comment on column public.venues.official_phone is
  'Telefone oficial do perfil, só dígitos. Distinto do telefone operacional.';
comment on column public.venues.claimed_at is
  'Nulo enquanto o perfil não foi reivindicado. O cadastro do Parceiro preenche na hora. Seed e admin deixam nulo.';

-- authenticated tem INSERT e UPDATE na tabela public.venues.
-- No Postgres o privilégio da tabela cobre a coluna: o revoke
-- abaixo não tira o que a tabela já deu. Quem trava
-- official_email, official_phone e claimed_at é o trigger
-- private.venues_guard.
revoke insert (official_email, official_phone, claimed_at)
  on table public.venues from anon, authenticated;
revoke update (official_email, official_phone, claimed_at)
  on table public.venues from anon, authenticated;
revoke select (official_email, official_phone, claimed_at)
  on table public.venues from anon, authenticated;

create table if not exists private.venue_claim_codes (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  claimant_id uuid not null references auth.users (id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  consumed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  check (attempts >= 0 and attempts <= max_attempts),
  check (max_attempts between 1 and 10),
  check (char_length(code_hash) between 20 and 200)
);

comment on table private.venue_claim_codes is
  'Hash do código de posse. Fora da API. Sem o código, sem e-mail e sem telefone.';

create index if not exists venue_claim_codes_open
  on private.venue_claim_codes (venue_id, claimant_id, created_at desc);

revoke all on table private.venue_claim_codes from public, anon, authenticated;

create table if not exists private.venue_claim_audit (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  claimant_id uuid,
  actor_id uuid,
  action text not null check (action in (
    'send',
    'confirm',
    'fail',
    'manual',
    'approve',
    'reject',
    'rate',
    'abort'
  )),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table private.venue_claim_audit is
  'Quem pediu o código, quem confirmou e quem o admin decidiu. Sem código e sem contato.';

create index if not exists venue_claim_audit_by_venue
  on private.venue_claim_audit (venue_id, created_at desc);

revoke all on table private.venue_claim_audit from public, anon, authenticated;

create or replace function private.venues_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.asaas_wallet_id := null;
      new.suspended_at := null;
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
    new.asaas_wallet_id := old.asaas_wallet_id;
    new.suspended_at := old.suspended_at;
    new.featured_rank := old.featured_rank;
    new.official_email := old.official_email;
    new.official_phone := old.official_phone;
    new.claimed_at := old.claimed_at;
    if old.status is distinct from 'pending'
      or old.asaas_wallet_id is not null
    then
      new.company_type := old.company_type;
    end if;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.venues_guard() from public, anon, authenticated;

create or replace function private.venue_claims_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if current_setting('scapematch.claim_issue', true) = 'on' then
    if tg_op = 'INSERT' then
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      return new;
    end if;
    new.venue_id := old.venue_id;
    new.claimant_id := old.claimant_id;
    new.pending_venue_id := old.pending_venue_id;
    new.note := old.note;
    new.created_at := old.created_at;
    if new.status is distinct from 'rejected' then
      new.status := old.status;
    end if;
    return new;
  end if;

  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if tg_op = 'INSERT' then
    if not private.is_admin_aal2() then
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

  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
  new.venue_id := old.venue_id;
  new.claimant_id := old.claimant_id;
  new.pending_venue_id := old.pending_venue_id;
  new.note := old.note;
  new.created_at := old.created_at;
  if new.status is distinct from old.status then
    new.reviewed_by := v_uid;
    new.reviewed_at := pg_catalog.now();
  else
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

revoke all on function private.venue_claims_guard() from public, anon, authenticated;

create or replace function private.venue_claim_audit(
  p_venue_id uuid,
  p_claimant uuid,
  p_actor uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.venue_claim_audit (venue_id, claimant_id, actor_id, action)
  values (p_venue_id, p_claimant, p_actor, p_action);
end;
$$;

revoke all on function private.venue_claim_audit(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.open_manual_venue_claim(
  p_venue_id uuid,
  p_claimant uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select claim.id
    into v_id
  from public.venue_claims claim
  where claim.venue_id = p_venue_id
    and claim.claimant_id = p_claimant
    and claim.status = 'pending'
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  perform pg_catalog.set_config('scapematch.claim_issue', 'on', true);
  insert into public.venue_claims (venue_id, claimant_id, note)
  values (p_venue_id, p_claimant, 'Sem contato oficial no perfil.')
  returning id into v_id;
  perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'manual');
  return v_id;
end;
$$;

revoke all on function private.open_manual_venue_claim(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.open_manual_venue_claim(uuid, uuid)
  to service_role;

create or replace function private.issue_venue_claim_code(
  p_venue_id uuid,
  p_claimant uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_house public.venues%rowtype;
  v_recent integer;
  v_last timestamptz;
  v_code text;
  v_hash text;
  v_id uuid;
  v_email text;
  v_phone text;
begin
  if p_claimant is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select venue.*
    into v_house
  from public.venues venue
  where venue.id = p_venue_id
  for update;

  if not found or v_house.status in ('rejected', 'merged') then
    return pg_catalog.jsonb_build_object('status', 'not_found');
  end if;
  if v_house.owner_id = p_claimant then
    return pg_catalog.jsonb_build_object('status', 'already_owner');
  end if;
  if v_house.claimed_at is not null or v_house.status <> 'approved' then
    return pg_catalog.jsonb_build_object('status', 'already_claimed');
  end if;

  v_email := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(v_house.official_email, ''))), '');
  v_phone := nullif(pg_catalog.btrim(coalesce(v_house.official_phone, '')), '');

  select count(*)
    into v_recent
  from private.venue_claim_codes code
  where code.venue_id = p_venue_id
    and code.created_at > pg_catalog.now() - interval '1 hour';
  if v_recent >= 5 then
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'rate');
    return pg_catalog.jsonb_build_object('status', 'rate');
  end if;

  select count(*)
    into v_recent
  from private.venue_claim_codes code
  where code.claimant_id = p_claimant
    and code.created_at > pg_catalog.now() - interval '15 minutes';
  if v_recent >= 3 then
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'rate');
    return pg_catalog.jsonb_build_object('status', 'rate');
  end if;

  select max(code.created_at)
    into v_last
  from private.venue_claim_codes code
  where code.venue_id = p_venue_id
    and code.claimant_id = p_claimant;
  if v_last is not null and v_last > pg_catalog.now() - interval '60 seconds' then
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'rate');
    return pg_catalog.jsonb_build_object('status', 'rate');
  end if;

  if v_email is null and v_phone is null then
    return pg_catalog.jsonb_build_object(
      'status', 'manual',
      'claim_id', private.open_manual_venue_claim(p_venue_id, p_claimant),
      'venue_id', p_venue_id,
      'venue_name', v_house.name
    );
  end if;

  update private.venue_claim_codes code
  set consumed_at = pg_catalog.now()
  where code.venue_id = p_venue_id
    and code.claimant_id = p_claimant
    and code.consumed_at is null;

  select pg_catalog.string_agg(
    pg_catalog.substr('0123456789', 1 + (pg_catalog.get_byte(buf, g) % 10), 1),
    ''
    order by g
  )
    into v_code
  from extensions.gen_random_bytes(6) as buf
  cross join pg_catalog.generate_series(0, 5) as g;

  v_hash := extensions.crypt(v_code, extensions.gen_salt('bf', 8));
  insert into private.venue_claim_codes (
    venue_id, claimant_id, code_hash, expires_at
  ) values (
    p_venue_id,
    p_claimant,
    v_hash,
    pg_catalog.now() + interval '10 minutes'
  )
  returning id into v_id;

  perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'send');
  return pg_catalog.jsonb_build_object(
    'status', 'otp',
    'code_id', v_id,
    'code', v_code,
    'email', v_email,
    'phone', v_phone,
    'venue_id', p_venue_id,
    'venue_name', v_house.name
  );
end;
$$;

revoke all on function private.issue_venue_claim_code(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.issue_venue_claim_code(uuid, uuid)
  to service_role;

create or replace function private.abort_venue_claim_code(
  p_code_id uuid,
  p_claimant uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  update private.venue_claim_codes code
  set consumed_at = pg_catalog.now()
  where code.id = p_code_id
    and code.claimant_id = p_claimant
    and code.consumed_at is null
  returning code.venue_id into v_venue;
  if v_venue is null then
    return pg_catalog.jsonb_build_object('status', 'not_found');
  end if;
  perform private.venue_claim_audit(v_venue, p_claimant, null, 'abort');
  return pg_catalog.jsonb_build_object(
    'status', 'manual',
    'claim_id', private.open_manual_venue_claim(v_venue, p_claimant),
    'venue_id', v_venue
  );
end;
$$;

revoke all on function private.abort_venue_claim_code(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.abort_venue_claim_code(uuid, uuid)
  to service_role;

create or replace function private.confirm_venue_claim_code(
  p_venue_id uuid,
  p_claimant uuid,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.venue_claim_codes%rowtype;
  v_code text := pg_catalog.btrim(coalesce(p_code, ''));
  v_match boolean;
begin
  if p_claimant is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if v_code !~ '^[0-9]{6}$' then
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'mismatch');
  end if;

  select code.*
    into v_row
  from private.venue_claim_codes code
  where code.venue_id = p_venue_id
    and code.claimant_id = p_claimant
    and code.consumed_at is null
  order by code.created_at desc
  limit 1
  for update;

  if not found then
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'no_code');
  end if;
  if v_row.expires_at <= pg_catalog.now() then
    update private.venue_claim_codes
    set consumed_at = pg_catalog.now()
    where id = v_row.id;
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'expired');
  end if;
  if v_row.attempts >= v_row.max_attempts then
    update private.venue_claim_codes
    set consumed_at = pg_catalog.now()
    where id = v_row.id;
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'locked');
  end if;

  v_match := extensions.crypt(v_code, v_row.code_hash) = v_row.code_hash;
  if not v_match then
    update private.venue_claim_codes
    set
      attempts = attempts + 1,
      consumed_at = case
        when attempts + 1 >= max_attempts then pg_catalog.now()
        else consumed_at
      end
    where id = v_row.id;
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'mismatch');
  end if;

  if not exists (
    select 1
    from public.venues venue
    where venue.id = p_venue_id
      and venue.status = 'approved'
      and venue.claimed_at is null
      and venue.owner_id is distinct from p_claimant
  ) then
    update private.venue_claim_codes
    set consumed_at = pg_catalog.now()
    where id = v_row.id;
    perform private.venue_claim_audit(p_venue_id, p_claimant, null, 'fail');
    return pg_catalog.jsonb_build_object('status', 'already_claimed');
  end if;

  update public.venues
  set
    owner_id = p_claimant,
    claimed_at = pg_catalog.now()
  where id = p_venue_id;

  update private.venue_claim_codes
  set consumed_at = pg_catalog.now()
  where id = v_row.id;

  perform pg_catalog.set_config('scapematch.claim_issue', 'on', true);
  update public.venue_claims claim
  set
    status = 'rejected',
    reviewed_at = pg_catalog.now()
  where claim.venue_id = p_venue_id
    and claim.status = 'pending'
    and claim.claimant_id is distinct from p_claimant;

  perform private.venue_claim_audit(p_venue_id, p_claimant, p_claimant, 'confirm');
  return pg_catalog.jsonb_build_object(
    'status', 'confirmed',
    'venue_id', p_venue_id
  );
end;
$$;

revoke all on function private.confirm_venue_claim_code(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function private.confirm_venue_claim_code(uuid, uuid, text)
  to service_role;

-- A API só enxerga public. Quem chama é a Edge Function, com service_role.
-- authenticated não executa: o claimant sai do JWT, não do body.
create or replace function public.issue_venue_claim_code(
  p_venue_id uuid,
  p_claimant uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.issue_venue_claim_code(p_venue_id, p_claimant);
$$;

create or replace function public.abort_venue_claim_code(
  p_code_id uuid,
  p_claimant uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.abort_venue_claim_code(p_code_id, p_claimant);
$$;

create or replace function public.confirm_venue_claim_code(
  p_venue_id uuid,
  p_claimant uuid,
  p_code text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.confirm_venue_claim_code(p_venue_id, p_claimant, p_code);
$$;

revoke all on function public.issue_venue_claim_code(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.abort_venue_claim_code(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.confirm_venue_claim_code(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.issue_venue_claim_code(uuid, uuid) to service_role;
grant execute on function public.abort_venue_claim_code(uuid, uuid) to service_role;
grant execute on function public.confirm_venue_claim_code(uuid, uuid, text)
  to service_role;

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

revoke all on function public.find_claimable_venue(text)
  from public, anon, service_role;
grant execute on function public.find_claimable_venue(text) to authenticated;

create or replace function private.review_venue_claim(
  p_claim_id uuid,
  p_decision text
)
returns table (claim_id uuid, status text, venue_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_claim public.venue_claims%rowtype;
  v_updated integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
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

  if p_decision = 'approved' then
    perform 1
    from public.venues house
    where house.id = v_claim.venue_id
    for update;

    update public.venues as house
    set
      owner_id = v_claim.claimant_id,
      claimed_at = pg_catalog.now()
    where house.id = v_claim.venue_id
      and house.status = 'approved'
      and house.claimed_at is null
      and house.owner_id is distinct from v_claim.claimant_id;
    get diagnostics v_updated = row_count;
    if v_updated <> 1 then
      raise exception 'already_claimed' using errcode = 'P0001';
    end if;

    update public.venue_claims as claim
    set
      status = 'approved',
      reviewed_by = v_uid,
      reviewed_at = pg_catalog.now()
    where claim.id = p_claim_id;

    perform pg_catalog.set_config('scapematch.claim_issue', 'on', true);
    update public.venue_claims claim
    set
      status = 'rejected',
      reviewed_at = pg_catalog.now()
    where claim.venue_id = v_claim.venue_id
      and claim.status = 'pending'
      and claim.claimant_id is distinct from v_claim.claimant_id;
    perform pg_catalog.set_config('scapematch.claim_issue', 'off', true);

    if v_claim.pending_venue_id is not null then
      update public.venues as pending_house
      set
        status = 'merged',
        merged_into = v_claim.venue_id,
        reviewed_by = v_uid,
        reviewed_at = pg_catalog.now()
      where pending_house.id = v_claim.pending_venue_id
        and pending_house.owner_id = v_claim.claimant_id
        and pending_house.status = 'pending';
    end if;
    perform private.venue_claim_audit(
      v_claim.venue_id, v_claim.claimant_id, v_uid, 'approve'
    );
  else
    update public.venue_claims as claim
    set
      status = 'rejected',
      reviewed_by = v_uid,
      reviewed_at = pg_catalog.now()
    where claim.id = p_claim_id;

    perform private.venue_claim_audit(
      v_claim.venue_id, v_claim.claimant_id, v_uid, 'reject'
    );
  end if;

  return query
  select p_claim_id, p_decision, v_claim.venue_id;
end;
$$;

create or replace function public.admin_list_venue_claims()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at)
    from (
      select
        claim.id,
        claim.venue_id,
        venue.name as venue_name,
        claim.claimant_id,
        coalesce(profile.display_name, 'Conta') as claimant_label,
        claim.created_at,
        (
          venue.official_email is not null
          and pg_catalog.btrim(venue.official_email) <> ''
        ) as has_official_email,
        (
          venue.official_phone is not null
          and pg_catalog.btrim(venue.official_phone) <> ''
        ) as has_official_phone
      from public.venue_claims claim
      join public.venues venue on venue.id = claim.venue_id
      left join public.profiles profile on profile.id = claim.claimant_id
      where claim.status = 'pending'
      order by claim.created_at
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_review_venue_claim(
  p_claim_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_row record;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  select reviewed.claim_id, reviewed.status, reviewed.venue_id
    into v_row
  from private.review_venue_claim(p_claim_id, p_decision) as reviewed;
  perform private.admin_audit(
    v_uid,
    'review_venue_claim',
    'venue_claims',
    p_claim_id::text,
    pg_catalog.jsonb_build_object('status', 'pending'),
    pg_catalog.jsonb_build_object('status', p_decision, 'venue_id', v_row.venue_id)
  );
  return pg_catalog.jsonb_build_object(
    'claim_id', v_row.claim_id,
    'status', v_row.status,
    'venue_id', v_row.venue_id
  );
end;
$$;

create or replace function public.admin_set_venue_contacts(
  p_venue_id uuid,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_email text := nullif(pg_catalog.lower(pg_catalog.btrim(coalesce(p_email, ''))), '');
  v_phone text := nullif(pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
begin
  if not exists (select 1 from public.venues where id = p_venue_id) then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v_email is not null and (
    char_length(v_email) > 160
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) then
    raise exception 'e-mail oficial invalido' using errcode = '22023';
  end if;
  if v_phone is not null and v_phone !~ '^[0-9]{10,13}$' then
    raise exception 'telefone oficial invalido' using errcode = '22023';
  end if;
  update public.venues
  set official_email = v_email, official_phone = v_phone
  where id = p_venue_id;
  perform private.admin_audit(
    v_uid,
    'set_venue_contacts',
    'venues',
    p_venue_id::text,
    '{}'::jsonb,
    pg_catalog.jsonb_build_object(
      'has_email', v_email is not null,
      'has_phone', v_phone is not null
    )
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'has_email', v_email is not null,
    'has_phone', v_phone is not null
  );
end;
$$;

revoke all on function public.admin_list_venue_claims()
  from public, anon, service_role;
revoke all on function public.admin_review_venue_claim(uuid, text)
  from public, anon, service_role;
revoke all on function public.admin_set_venue_contacts(uuid, text, text)
  from public, anon, service_role;
grant execute on function public.admin_list_venue_claims() to authenticated;
grant execute on function public.admin_review_venue_claim(uuid, text) to authenticated;
grant execute on function public.admin_set_venue_contacts(uuid, text, text) to authenticated;

create or replace function public.venue_finance_ready(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues venue
    where venue.id = p_venue_id
      and venue.status = 'approved'
      and venue.suspended_at is null
      and venue.asaas_wallet_id is not null
      and pg_catalog.btrim(venue.asaas_wallet_id) <> ''
      and exists (
        select 1
        from public.venue_bank_accounts bank
        where bank.venue_id = venue.id
      )
  );
$$;

revoke all on function public.venue_finance_ready(uuid) from public;
grant execute on function public.venue_finance_ready(uuid)
  to anon, authenticated, service_role;

create or replace view public.venues_vitrine
with (security_invoker = true) as
select
  id,
  city_id,
  name,
  neighborhood,
  street_address,
  address_number,
  postal_code,
  latitude,
  longitude,
  category,
  badge,
  status,
  created_at,
  receives_payments,
  featured_rank,
  public.venue_finance_ready(id) as finance_ready
from public.venues;

revoke all on table public.venues_vitrine from public, anon, authenticated;
grant select on table public.venues_vitrine to anon, authenticated, service_role;
