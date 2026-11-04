-- Privacidade e o que o advisor já tinha apontado.
-- Anon e authenticated não leem documento, telefone nem renda.
-- Wallet e indicação saem só em venue_private (dono ou admin) ou service_role.
-- Foto de casa pendente não abre por URL pública. Falta só entra por mark_absence.
-- Gatilhos e sessions_overlap repetem o que já foi aplicado no banco.

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.venues_guard() from public, anon, authenticated;
revoke all on function public.profiles_guard() from public, anon, authenticated;

alter function public.sessions_overlap(timestamptz, integer, timestamptz, integer)
  set search_path = public;

-- Coluna a coluna: um revoke só na coluna não tira o grant da tabela.
-- service_role fica com o select da tabela. A Edge Function lê por aí.
revoke select on table public.venues from anon, authenticated;

grant select (
  id,
  city_id,
  name,
  neighborhood,
  street_address,
  address_number,
  postal_code,
  latitude,
  longitude,
  document_kind,
  category,
  badge,
  status,
  reviewed_at,
  created_at
) on table public.venues to anon;

grant select (
  id,
  owner_id,
  city_id,
  name,
  neighborhood,
  street_address,
  address_number,
  postal_code,
  latitude,
  longitude,
  document_kind,
  category,
  badge,
  invite_id,
  status,
  reviewed_by,
  reviewed_at,
  created_at
) on table public.venues to authenticated;

-- Vitrine para o select *. O anon não consegue select * na tabela.
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
  created_at
from public.venues;

revoke all on table public.venues_vitrine from public, anon, authenticated;
grant select on table public.venues_vitrine to anon, authenticated, service_role;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins where user_id = (select auth.uid())
  );
$$;

create or replace function public.owns_venue(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and owner_id = (select auth.uid())
  );
$$;

create or replace function public.venue_is_visible(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and (
        status = 'approved'
        or owner_id = (select auth.uid())
        or public.is_admin()
      )
  );
$$;

create or replace function public.room_photo_object_allowed(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues v
    where v.id::text = split_part(object_name, '/', 1)
      and (
        v.status = 'approved'
        or v.owner_id = (select auth.uid())
        or public.is_admin()
      )
  );
$$;

-- Documento, telefone, renda, wallet e quem indicou. Só o dono ou um admin.
create or replace function public.venue_private(p_venue_id uuid)
returns table (
  document_number text,
  phone text,
  income_value numeric,
  asaas_wallet_id text,
  referred_by uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not (public.owns_venue(p_venue_id) or public.is_admin()) then
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
$$;

revoke all on function public.venue_private(uuid) from public, anon, authenticated;
grant execute on function public.venue_private(uuid) to authenticated, service_role;

update storage.buckets
set public = false
where id = 'room-photos';

drop policy if exists room_photos_storage_insert on storage.objects;
create policy room_photos_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = (select auth.uid())
    )
  );

drop policy if exists room_photos_storage_update on storage.objects;
create policy room_photos_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = (select auth.uid())
    )
  )
  with check (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = (select auth.uid())
    )
  );

drop policy if exists room_photos_storage_delete on storage.objects;
create policy room_photos_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = (select auth.uid())
    )
  );

-- A leitura continua em room_photo_object_allowed: casa aprovada, dono ou admin.
-- Signed URL só sai quando essa política passa. Casa pendente não tem URL pública.

drop policy if exists absences_insert on public.absences;
revoke insert, update, delete on public.absences from anon, authenticated;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists admins_select_self on public.admins;
create policy admins_select_self on public.admins
  for select to authenticated
  using (user_id = (select auth.uid()));

-- A expressão roda com o privilégio de quem consulta. O anon não tem
-- select em owner_id. Sem usuário, auth.uid() é nulo e is_admin() é
-- falso, então o resultado do anon continua sendo só status = 'approved'.
drop policy if exists venues_select on public.venues;
create policy venues_select_anon on public.venues
  for select to anon
  using (status = 'approved');

create policy venues_select on public.venues
  for select to authenticated
  using (
    status = 'approved'
    or owner_id = (select auth.uid())
    or public.is_admin()
  );

drop policy if exists venues_insert on public.venues;
create policy venues_insert on public.venues
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists venues_update on public.venues;
create policy venues_update on public.venues
  for update to authenticated
  using (owner_id = (select auth.uid()) or public.is_admin())
  with check (owner_id = (select auth.uid()) or public.is_admin());

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups
  for select to anon, authenticated
  using (
    public.venue_is_visible(venue_id)
    or created_by = (select auth.uid())
    or exists (
      select 1 from public.group_members m
      where m.group_id = groups.id
        and m.user_id = (select auth.uid())
    )
  );

drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.groups g
      where g.id = group_members.group_id
        and (
          public.venue_is_visible(g.venue_id)
          or g.created_by = (select auth.uid())
          or group_members.user_id = (select auth.uid())
        )
    )
  );

drop policy if exists waitlist_select on public.waitlist;
create policy waitlist_select on public.waitlist
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.groups g
      where g.id = waitlist.group_id
        and (
          g.created_by = (select auth.uid())
          or public.owns_venue(g.venue_id)
        )
    )
  );

drop policy if exists absences_select on public.absences;
create policy absences_select on public.absences
  for select to authenticated
  using (
    public.owns_venue(venue_id)
    or public.is_admin()
    or user_id = (select auth.uid())
  );

drop policy if exists ledger_select on public.ledger_entries;
create policy ledger_select on public.ledger_entries
  for select to authenticated
  using (
    (account = 'house' and (public.owns_venue(venue_id) or public.is_admin()))
    or user_id = (select auth.uid())
  );

drop policy if exists payment_charges_select on public.payment_charges;
create policy payment_charges_select on public.payment_charges
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.owns_venue(venue_id)
    or public.is_admin()
  );

create index if not exists absences_by_venue on public.absences (venue_id);
create index if not exists absences_by_user on public.absences (user_id);
create index if not exists absences_by_marked_by on public.absences (marked_by);
create index if not exists groups_by_session on public.groups (session_id);
create index if not exists groups_by_creator on public.groups (created_by);
create index if not exists ledger_by_group on public.ledger_entries (group_id);
create index if not exists ledger_by_user on public.ledger_entries (user_id);
create index if not exists partner_invites_by_city on public.partner_invites (city_id);
create index if not exists payment_charges_by_user on public.payment_charges (user_id);
create index if not exists payment_charges_by_venue on public.payment_charges (venue_id);
create index if not exists venues_by_invite on public.venues (invite_id);
create index if not exists venues_by_reviewer on public.venues (reviewed_by);
create index if not exists waitlist_by_user on public.waitlist (user_id);
