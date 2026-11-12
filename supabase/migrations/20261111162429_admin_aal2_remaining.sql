-- O que sobrou do portão do PR #97. Quem não é dono passa por
-- private.admin_require() nas RPCs (admin e aal2, senão 'mfa obrigatorio').
-- Quem não é admin continua com o erro de antes ('not owner' ou 'not admin').
-- O ramo do dono não olha o aal.
--
-- Policy e auxiliar booleano usam private.is_admin_aal2(). admin_require
-- levanta exceção e derrubaria o SELECT. Gatilho que só congela campo
-- faz o mesmo: admin em aal1 perde o atalho, sem abortar a gravação do dono.
--
-- private.profiles_guard é security invoker e o authenticated não tem
-- USAGE em private. O critério de is_admin_aal2 fica inline (admins + aal2).
--
-- A conta da comissão não muda: teto de 0 a 30%, auditoria e o painel
-- seguem iguais. Só o portão de quem chama é outro.

create or replace function private.venue_is_visible(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and (
        (status = 'approved' and suspended_at is null)
        or owner_id = (select auth.uid())
        or private.is_admin_aal2()
      )
  );
$$;

create or replace function private.room_photo_object_allowed(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues v
    where v.id::text = split_part(object_name, '/', 1)
      and (
        v.status = 'approved'
        or v.owner_id = (select auth.uid())
        or private.is_admin_aal2()
      )
  );
$$;

create or replace function private.freeze_news_carousel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.carousel_rank := null;
    end if;
    return new;
  end if;
  if auth.uid() is not null and not private.is_admin_aal2() then
    new.carousel_rank := old.carousel_rank;
  end if;
  return new;
end;
$$;

create or replace function private.freeze_room_highlight()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.featured_rank := null;
    end if;
    return new;
  end if;
  if auth.uid() is not null and not private.is_admin_aal2() then
    new.featured_rank := old.featured_rank;
  end if;
  return new;
end;
$$;

create or replace function private.venues_normalize()
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
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.venue_claims_guard()
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
    new.reviewed_at := now();
  else
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  return new;
end;
$$;

create or replace function private.profiles_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.asaas_customer_id := old.asaas_customer_id;
    if not (
      exists (
        select 1
        from public.admins admin_row
        where admin_row.user_id = auth.uid()
      )
      and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    ) then
      new.suspended_at := old.suspended_at;
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.review_venue(
  p_venue_id uuid,
  p_decision text,
  p_merge_into uuid
)
returns table (venue_id uuid, status text)
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
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
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

create or replace function private.venue_link_status(p_venue_id uuid)
returns table (possible_duplicate_of uuid, merged_into uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.owns_venue(p_venue_id) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;
  return query
  select venue.possible_duplicate_of, venue.merged_into
  from public.venues venue
  where venue.id = p_venue_id;
end;
$$;

create or replace function public.accept_terms(
  p_audience text,
  p_venue_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_version text := '2026-11-06';
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_audience = 'player' then
    if p_venue_id is not null then
      raise exception 'player acceptance has no venue' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.legal_documents
      where code = 'player_terms' and version = v_version
    ) then
      raise exception 'unknown terms version' using errcode = '22023';
    end if;
    insert into public.terms_acceptances (
      user_id, audience, document_code, document_version
    )
    select v_user, 'player', d.code, v_version
    from (
      values ('player_terms'), ('privacy'), ('cancellation')
    ) as d(code)
    where not exists (
      select 1 from public.terms_acceptances t
      where t.user_id = v_user
        and t.audience = 'player'
        and t.document_code = d.code
        and t.document_version = v_version
    );
    return;
  end if;
  if p_audience = 'partner' then
    if p_venue_id is not null and not private.owns_venue(p_venue_id) then
      if not private.is_admin() then
        raise exception 'not owner' using errcode = '42501';
      end if;
      perform private.admin_require();
    end if;
    if not exists (
      select 1 from public.legal_documents
      where code = 'partner_terms' and version = v_version
    ) then
      raise exception 'unknown terms version' using errcode = '22023';
    end if;
    insert into public.terms_acceptances (
      user_id, venue_id, audience, document_code, document_version
    )
    select v_user, p_venue_id, 'partner', d.code, v_version
    from (
      values ('partner_terms'), ('privacy'), ('cancellation')
    ) as d(code)
    where not exists (
      select 1 from public.terms_acceptances t
      where t.user_id = v_user
        and t.audience = 'partner'
        and t.document_code = d.code
        and t.document_version = v_version
        and t.venue_id is not distinct from p_venue_id
    );
    return;
  end if;
  raise exception 'unknown audience' using errcode = '22023';
end;
$$;

create or replace function public.claim_venue_referral(
  p_venue_id uuid,
  p_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.venues
    where id = p_venue_id and owner_id = auth.uid()
  ) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;
  return private.attach_referral('venue', null, p_venue_id, p_code, true);
end;
$$;

create or replace function public.mark_absence(
  p_group_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group public.groups%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if not private.owns_venue(v_group.venue_id) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at > now() then
    raise exception 'session not started' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members
    where group_id = p_group_id
      and user_id = p_user_id
      and attendance <> 'cancelled'
  ) then
    raise exception 'not member' using errcode = 'P0002';
  end if;
  insert into public.absences (venue_id, group_id, user_id, marked_by)
  values (v_group.venue_id, p_group_id, p_user_id, auth.uid())
  on conflict (group_id, user_id) do nothing;
end;
$$;

create or replace function public.venue_private(p_venue_id uuid)
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
  if not private.owns_venue(p_venue_id) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
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

create or replace function public.commission_board()
returns table (
  venue_id uuid,
  venue_name text,
  commission_bps integer,
  is_override boolean,
  updated_by uuid,
  updated_at timestamptz
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
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
  return query
  select
    null::uuid,
    'EscapeMatch'::text,
    s.commission_bps,
    false,
    s.updated_by,
    s.updated_at
  from public.platform_settings s
  where s.id = 1;
  return query
  select
    v.id,
    v.name,
    coalesce(c.commission_bps, s.commission_bps),
    c.venue_id is not null,
    c.updated_by,
    c.updated_at
  from public.venues v
  cross join public.platform_settings s
  left join public.venue_commissions c on c.venue_id = v.id
  where s.id = 1
  order by v.name;
end;
$$;

create or replace function public.set_platform_commission(p_commission_bps integer)
returns table (
  commission_bps integer,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_before integer;
  v_at timestamptz := pg_catalog.now();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
  if p_commission_bps is null
    or p_commission_bps < 0
    or p_commission_bps > 3000
  then
    raise exception 'comissão fora de 0 a 30%%' using errcode = '22023';
  end if;
  select s.commission_bps into v_before
  from public.platform_settings s
  where s.id = 1
  for update;
  if v_before is null then
    raise exception 'configuração ausente';
  end if;
  update public.platform_settings s
  set commission_bps = p_commission_bps,
      updated_by = v_uid,
      updated_at = v_at
  where s.id = 1;
  insert into public.commission_changes (
    actor_id, venue_id, before_bps, after_bps, created_at
  ) values (
    v_uid, null, v_before, p_commission_bps, v_at
  );
  return query
  select p_commission_bps, v_uid, v_at;
end;
$$;

create or replace function public.set_venue_commission(
  p_venue_id uuid,
  p_commission_bps integer
)
returns table (
  venue_id uuid,
  commission_bps integer,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_before integer;
  v_at timestamptz := pg_catalog.now();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  perform private.admin_require();
  if p_venue_id is null or not exists (
    select 1 from public.venues v where v.id = p_venue_id
  ) then
    raise exception 'unknown venue' using errcode = 'P0002';
  end if;
  if p_commission_bps is null
    or p_commission_bps < 0
    or p_commission_bps > 3000
  then
    raise exception 'comissão fora de 0 a 30%%' using errcode = '22023';
  end if;
  select coalesce(
    (select c.commission_bps from public.venue_commissions c where c.venue_id = p_venue_id),
    (select s.commission_bps from public.platform_settings s where s.id = 1)
  ) into v_before;
  insert into public.venue_commissions (
    venue_id, commission_bps, updated_by, updated_at
  ) values (
    p_venue_id, p_commission_bps, v_uid, v_at
  )
  on conflict on constraint venue_commissions_pkey do update
  set commission_bps = excluded.commission_bps,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;
  insert into public.commission_changes (
    actor_id, venue_id, before_bps, after_bps, created_at
  ) values (
    v_uid, p_venue_id, v_before, p_commission_bps, v_at
  );
  return query
  select p_venue_id, p_commission_bps, v_uid, v_at;
end;
$$;

drop policy if exists absences_select on public.absences;
create policy absences_select on public.absences
  for select to authenticated
  using (
    private.owns_venue(venue_id)
    or private.is_admin_aal2()
    or user_id = (select auth.uid())
  );

drop policy if exists cashback_draws_select on public.cashback_draws;
create policy cashback_draws_select on public.cashback_draws
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_admin_aal2()
  );

drop policy if exists fiscal_invoices_select on public.fiscal_invoices;
create policy fiscal_invoices_select on public.fiscal_invoices
  for select to authenticated
  using (
    private.is_admin_aal2()
    or private.owns_venue(venue_id)
    or (
      kind = 'service'
      and player_user_id = (select auth.uid())
    )
  );

drop policy if exists ledger_select on public.ledger_entries;
create policy ledger_select on public.ledger_entries
  for select to authenticated
  using (
    (
      account = 'house'
      and (
        private.owns_venue(venue_id)
        or private.is_admin_aal2()
      )
    )
    or user_id = (select auth.uid())
  );

drop policy if exists news_write on public.news_items;
create policy news_write on public.news_items
  for all to authenticated
  using (private.owns_venue(venue_id) or private.is_admin_aal2())
  with check (private.owns_venue(venue_id) or private.is_admin_aal2());

drop policy if exists invites_read on public.partner_invites;
create policy invites_read on public.partner_invites
  for select to anon, authenticated
  using (active or private.is_admin_aal2());

drop policy if exists payment_charges_select on public.payment_charges;
create policy payment_charges_select on public.payment_charges
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.owns_venue(venue_id)
    or private.is_admin_aal2()
  );

drop policy if exists settings_admin on public.platform_settings;
create policy settings_admin on public.platform_settings
  for select to authenticated
  using (private.is_admin_aal2());

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or private.is_admin_aal2()
  );

drop policy if exists promotions_select on public.promotions;
create policy promotions_select on public.promotions
  for select to anon, authenticated
  using (
    private.venue_is_visible(venue_id)
    and (
      active
      or private.owns_venue(venue_id)
      or private.is_admin_aal2()
    )
  );

drop policy if exists promotions_write on public.promotions;
create policy promotions_write on public.promotions
  for all to authenticated
  using (private.owns_venue(venue_id) or private.is_admin_aal2())
  with check (private.owns_venue(venue_id) or private.is_admin_aal2());

drop policy if exists referral_attribution_select on public.referral_attributions;
create policy referral_attribution_select on public.referral_attributions
  for select to authenticated
  using (
    subject_user_id = auth.uid()
    or referrer_user_id = auth.uid()
    or (
      subject_venue_id is not null
      and private.owns_venue(subject_venue_id)
    )
    or (
      referrer_venue_id is not null
      and private.owns_venue(referrer_venue_id)
    )
    or private.is_admin_aal2()
  );

drop policy if exists referral_withholdings_select on public.referral_withholdings;
create policy referral_withholdings_select on public.referral_withholdings
  for select to authenticated
  using (user_id = auth.uid() or private.is_admin_aal2());

drop policy if exists room_photos_write on public.room_photos;
create policy room_photos_write on public.room_photos
  for all to authenticated
  using (
    exists (
      select 1
      from public.rooms r
      where r.id = room_photos.room_id
        and (
          private.owns_venue(r.venue_id)
          or private.is_admin_aal2()
        )
    )
  )
  with check (
    exists (
      select 1
      from public.rooms r
      where r.id = room_photos.room_id
        and (
          private.owns_venue(r.venue_id)
          or private.is_admin_aal2()
        )
    )
  );

drop policy if exists rooms_write on public.rooms;
create policy rooms_write on public.rooms
  for all to authenticated
  using (private.owns_venue(venue_id) or private.is_admin_aal2())
  with check (private.owns_venue(venue_id) or private.is_admin_aal2());

drop policy if exists scape_point_select on public.scape_point_entries;
create policy scape_point_select on public.scape_point_entries
  for select to authenticated
  using (user_id = auth.uid() or private.is_admin_aal2());

drop policy if exists terms_acceptances_select on public.terms_acceptances;
create policy terms_acceptances_select on public.terms_acceptances
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_admin_aal2()
    or (venue_id is not null and private.owns_venue(venue_id))
  );

drop policy if exists venue_claims_select on public.venue_claims;
create policy venue_claims_select on public.venue_claims
  for select to authenticated
  using (
    claimant_id = (select auth.uid())
    or (select private.is_admin_aal2())
  );

drop policy if exists venue_claims_update on public.venue_claims;
create policy venue_claims_update on public.venue_claims
  for update to authenticated
  using ((select private.is_admin_aal2()))
  with check ((select private.is_admin_aal2()));

drop policy if exists venue_fiscal_select on public.venue_fiscal;
create policy venue_fiscal_select on public.venue_fiscal
  for select to authenticated
  using (private.owns_venue(venue_id) or private.is_admin_aal2());

drop policy if exists venue_referral_select on public.venue_referral_entries;
create policy venue_referral_select on public.venue_referral_entries
  for select to authenticated
  using (private.owns_venue(venue_id) or private.is_admin_aal2());

drop policy if exists venues_select on public.venues;
create policy venues_select on public.venues
  for select to authenticated
  using (
    (status = 'approved' and suspended_at is null)
    or owner_id = (select auth.uid())
    or private.is_admin_aal2()
  );

drop policy if exists venues_update on public.venues;
create policy venues_update on public.venues
  for update to authenticated
  using (
    owner_id = (select auth.uid())
    or private.is_admin_aal2()
  )
  with check (
    owner_id = (select auth.uid())
    or private.is_admin_aal2()
  );
