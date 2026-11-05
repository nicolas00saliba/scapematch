-- Tira da API as funções SECURITY DEFINER usadas só por policy.
-- O schema private não entra em pgrst.db_schemas, então
-- /rest/v1/rpc não as publica. anon e authenticated continuam
-- podendo executá-las: a policy roda com o papel de quem consulta.
-- Sem esse EXECUTE a leitura anônima de salas, casas e fotos quebra.

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

comment on schema private is
  'Funções que atravessam o RLS. Este schema não entra na API.';

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admins where user_id = (select auth.uid())
  );
$$;

create or replace function private.owns_venue(p_venue_id uuid)
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
      and owner_id = (select auth.uid())
  );
$$;

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
        status = 'approved'
        or owner_id = (select auth.uid())
        or private.is_admin()
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
        or private.is_admin()
      )
  );
$$;

create or replace function private.is_group_member(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members m
    where m.group_id = gid
      and m.user_id = (select auth.uid())
  );
$$;

create or replace function private.group_is_readable(gid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.groups g
    where g.id = gid
      and (
        private.venue_is_visible(g.venue_id)
        or g.created_by = (select auth.uid())
      )
  );
$$;

revoke all on function private.is_admin() from public;
revoke all on function private.owns_venue(uuid) from public;
revoke all on function private.venue_is_visible(uuid) from public;
revoke all on function private.room_photo_object_allowed(text) from public;
revoke all on function private.is_group_member(uuid) from public;
revoke all on function private.group_is_readable(uuid) from public;

grant execute on function private.is_admin() to anon, authenticated, service_role;
grant execute on function private.owns_venue(uuid) to anon, authenticated, service_role;
grant execute on function private.venue_is_visible(uuid) to anon, authenticated, service_role;
grant execute on function private.room_photo_object_allowed(text) to anon, authenticated, service_role;
grant execute on function private.is_group_member(uuid) to anon, authenticated, service_role;
grant execute on function private.group_is_readable(uuid) to anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.review_venue(p_venue_id uuid, p_decision text, p_merge_into uuid)
 RETURNS TABLE(venue_id uuid, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.review_venue_claim(p_claim_id uuid, p_decision text)
 RETURNS TABLE(claim_id uuid, status text, venue_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.accept_terms(p_audience text, p_venue_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    if p_venue_id is not null
      and not (private.owns_venue(p_venue_id) or private.is_admin()) then
      raise exception 'not owner' using errcode = '42501';
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
$function$;

CREATE OR REPLACE FUNCTION public.house_cancel_group(p_group_id uuid, p_reason text DEFAULT 'Cancelada pela casa'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_reason text;
  v_member record;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if not (private.owns_venue(v_group.venue_id) or private.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'already cancelled' using errcode = 'P0001';
  end if;
  if now() > v_group.starts_at - interval '2 hours' then
    raise exception 'too close to delete' using errcode = 'P0001';
  end if;

  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    v_reason := 'Cancelada pela casa';
  end if;
  if char_length(v_reason) > 280 then
    v_reason := left(v_reason, 280);
  end if;

  update public.groups
    set cancelled_at = now(), cancel_reason = v_reason
    where id = p_group_id;

  update public.group_members
    set attendance = 'cancelled',
        refund_status = case
          when payment_status = 'paid' then 'pending'
          else 'none'
        end,
        refund_reason = 'organizer_cancelled_event',
        payment_status = case
          when payment_status = 'paid' then payment_status
          else 'released'
        end
    where group_id = p_group_id
      and attendance <> 'cancelled';

  if v_group.session_id is not null then
    update public.room_sessions
      set cancelled_at = now()
      where id = v_group.session_id
        and cancelled_at is null;
  end if;

  for v_member in
    select user_id
    from public.group_members
    where group_id = p_group_id
      and attendance = 'cancelled'
      and refund_reason = 'organizer_cancelled_event'
  loop
    perform public.post_app_notice(
      v_member.user_id,
      'group_cancelled',
      'Sessão cancelada',
      'A casa cancelou a sessão. Se você pagou, o estorno está em andamento.',
      p_group_id,
      'house-cancel-' || p_group_id::text
    );
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_absence(p_group_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if not (private.owns_venue(v_group.venue_id) or private.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
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
$function$;

CREATE OR REPLACE FUNCTION public.venue_claims_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if tg_op = 'INSERT' then
    if not private.is_admin() then
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
$function$;

CREATE OR REPLACE FUNCTION public.venue_link_status(p_venue_id uuid)
 RETURNS TABLE(possible_duplicate_of uuid, merged_into uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not (private.owns_venue(p_venue_id) or private.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return query
  select venue.possible_duplicate_of, venue.merged_into
  from public.venues venue
  where venue.id = p_venue_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.venue_private(p_venue_id uuid)
 RETURNS TABLE(document_number text, phone text, income_value numeric, asaas_wallet_id text, referred_by uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      v.asaas_wallet_id,
      v.referred_by
    from public.venues v
    where v.id = p_venue_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.venues_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.asaas_wallet_id := null;
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

  -- Sem JWT: SQL editor ou service role da Edge Function (grava o walletId).
  if auth.uid() is null then
    return new;
  end if;

  if not private.is_admin() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.referred_by := old.referred_by;
    new.invite_id := old.invite_id;
    new.asaas_wallet_id := old.asaas_wallet_id;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.venues_normalize()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if v_uid is not null and not private.is_admin() then
      new.merged_into := null;
    end if;
  elsif v_uid is not null and not private.is_admin() then
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
$function$;

drop policy if exists absences_select on public.absences;
create policy absences_select on public.absences
  for select to authenticated
  using (
    (private.owns_venue(venue_id) OR private.is_admin() OR (user_id = ( SELECT auth.uid() AS uid)))
  );

drop policy if exists fiscal_invoices_select on public.fiscal_invoices;
create policy fiscal_invoices_select on public.fiscal_invoices
  for select to authenticated
  using (
    (private.is_admin() OR private.owns_venue(venue_id) OR ((kind = 'service'::text) AND (player_user_id = ( SELECT auth.uid() AS uid))))
  );

drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members
  for select
  using (
    ((user_id = ( SELECT auth.uid() AS uid)) OR private.group_is_readable(group_id))
  );

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups
  for select
  using (
    (private.venue_is_visible(venue_id) OR (created_by = ( SELECT auth.uid() AS uid)) OR private.is_group_member(id))
  );

drop policy if exists ledger_select on public.ledger_entries;
create policy ledger_select on public.ledger_entries
  for select to authenticated
  using (
    (((account = 'house'::text) AND (private.owns_venue(venue_id) OR private.is_admin())) OR (user_id = ( SELECT auth.uid() AS uid)))
  );

drop policy if exists news_select on public.news_items;
create policy news_select on public.news_items
  for select to anon, authenticated
  using (
    private.venue_is_visible(venue_id)
  );

drop policy if exists news_write on public.news_items;
create policy news_write on public.news_items
  for all to authenticated
  using (
    (private.owns_venue(venue_id) OR private.is_admin())
  )
  with check (
    (private.owns_venue(venue_id) OR private.is_admin())
  );

drop policy if exists invites_read on public.partner_invites;
create policy invites_read on public.partner_invites
  for select to anon, authenticated
  using (
    (active OR private.is_admin())
  );

drop policy if exists payment_charges_select on public.payment_charges;
create policy payment_charges_select on public.payment_charges
  for select to authenticated
  using (
    ((user_id = ( SELECT auth.uid() AS uid)) OR private.owns_venue(venue_id) OR private.is_admin())
  );

drop policy if exists settings_admin on public.platform_settings;
create policy settings_admin on public.platform_settings
  for select to authenticated
  using (
    private.is_admin()
  );

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    ((id = ( SELECT auth.uid() AS uid)) OR private.is_admin())
  );

drop policy if exists promotions_select on public.promotions;
create policy promotions_select on public.promotions
  for select to anon, authenticated
  using (
    (private.venue_is_visible(venue_id) AND (active OR private.owns_venue(venue_id) OR private.is_admin()))
  );

drop policy if exists promotions_write on public.promotions;
create policy promotions_write on public.promotions
  for all to authenticated
  using (
    (private.owns_venue(venue_id) OR private.is_admin())
  )
  with check (
    (private.owns_venue(venue_id) OR private.is_admin())
  );

drop policy if exists room_photos_select on public.room_photos;
create policy room_photos_select on public.room_photos
  for select to anon, authenticated
  using (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_photos.room_id) AND private.venue_is_visible(r.venue_id))))
  );

drop policy if exists room_photos_write on public.room_photos;
create policy room_photos_write on public.room_photos
  for all to authenticated
  using (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_photos.room_id) AND (private.owns_venue(r.venue_id) OR private.is_admin()))))
  )
  with check (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_photos.room_id) AND (private.owns_venue(r.venue_id) OR private.is_admin()))))
  );

drop policy if exists room_sessions_select on public.room_sessions;
create policy room_sessions_select on public.room_sessions
  for select to anon, authenticated
  using (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_sessions.room_id) AND private.venue_is_visible(r.venue_id))))
  );

drop policy if exists room_sessions_write on public.room_sessions;
create policy room_sessions_write on public.room_sessions
  for all to authenticated
  using (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_sessions.room_id) AND (private.owns_venue(r.venue_id) OR private.is_admin()))))
  )
  with check (
    (EXISTS ( SELECT 1
   FROM rooms r
  WHERE ((r.id = room_sessions.room_id) AND (private.owns_venue(r.venue_id) OR private.is_admin()))))
  );

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms
  for select to anon, authenticated
  using (
    private.venue_is_visible(venue_id)
  );

drop policy if exists rooms_write on public.rooms;
create policy rooms_write on public.rooms
  for all to authenticated
  using (
    (private.owns_venue(venue_id) OR private.is_admin())
  )
  with check (
    (private.owns_venue(venue_id) OR private.is_admin())
  );

drop policy if exists terms_acceptances_select on public.terms_acceptances;
create policy terms_acceptances_select on public.terms_acceptances
  for select to authenticated
  using (
    ((user_id = ( SELECT auth.uid() AS uid)) OR private.is_admin() OR ((venue_id IS NOT NULL) AND private.owns_venue(venue_id)))
  );

drop policy if exists venue_claims_select on public.venue_claims;
create policy venue_claims_select on public.venue_claims
  for select to authenticated
  using (
    ((claimant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin))
  );

drop policy if exists venue_claims_update on public.venue_claims;
create policy venue_claims_update on public.venue_claims
  for update to authenticated
  using (
    ( SELECT private.is_admin() AS is_admin)
  )
  with check (
    ( SELECT private.is_admin() AS is_admin)
  );

drop policy if exists venue_fiscal_select on public.venue_fiscal;
create policy venue_fiscal_select on public.venue_fiscal
  for select to authenticated
  using (
    (private.owns_venue(venue_id) OR private.is_admin())
  );

drop policy if exists venues_select on public.venues;
create policy venues_select on public.venues
  for select to authenticated
  using (
    ((status = 'approved'::text) OR (owner_id = ( SELECT auth.uid() AS uid)) OR private.is_admin())
  );

drop policy if exists venues_update on public.venues;
create policy venues_update on public.venues
  for update to authenticated
  using (
    ((owner_id = ( SELECT auth.uid() AS uid)) OR private.is_admin())
  )
  with check (
    ((owner_id = ( SELECT auth.uid() AS uid)) OR private.is_admin())
  );

drop policy if exists waitlist_select on public.waitlist;
create policy waitlist_select on public.waitlist
  for select to authenticated
  using (
    ((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM groups g
  WHERE ((g.id = waitlist.group_id) AND ((g.created_by = ( SELECT auth.uid() AS uid)) OR private.owns_venue(g.venue_id))))))
  );

drop policy if exists room_photos_storage_read on storage.objects;
create policy room_photos_storage_read on storage.objects
  for select to anon, authenticated
  using (
    ((bucket_id = 'room-photos'::text) AND private.room_photo_object_allowed(name))
  );

drop function public.group_is_readable(uuid);
drop function public.is_group_member(uuid);
drop function public.room_photo_object_allowed(text);
drop function public.venue_is_visible(uuid);
drop function public.owns_venue(uuid);
drop function public.is_admin();

-- Auxiliares internas. Não são RPC do app. O EXECUTE de anon,
-- authenticated e public sai; service_role conserva o que já tinha.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.profiles_guard() from public, anon, authenticated;
revoke all on function public.venues_guard() from public, anon, authenticated;
revoke all on function public.venues_normalize() from public, anon, authenticated;
revoke all on function public.venue_claims_guard() from public, anon, authenticated;
revoke all on function public.group_filled_spots(uuid) from public, anon, authenticated;
revoke all on function public.profile_display_name(uuid) from public, anon, authenticated;
revoke all on function public.user_has_overlap(uuid, timestamptz, integer, uuid) from public, anon, authenticated;
revoke all on function public.users_are_friends(uuid, uuid) from public, anon, authenticated;
revoke all on function public.post_app_notice(uuid, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.offer_waitlist(uuid) from public, anon, authenticated;
revoke all on function public.venue_link_status(uuid) from public, anon, authenticated;
