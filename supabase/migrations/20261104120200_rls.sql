-- RLS. Jogador anônimo lê cidade, casa aprovada, sala, sessão, grupo e
-- notícia. Casa só escreve o que é dela. Grupo e cadeira não têm insert
-- direto: entram pelas funções.

alter table public.partner_invites enable row level security;
alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.cities enable row level security;
alter table public.venues enable row level security;
alter table public.rooms enable row level security;
alter table public.room_photos enable row level security;
alter table public.room_sessions enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.waitlist enable row level security;
alter table public.news_items enable row level security;
alter table public.promotions enable row level security;
alter table public.absences enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.platform_settings enable row level security;

create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy admins_select_self on public.admins
  for select to authenticated
  using (user_id = auth.uid());

create policy cities_read on public.cities
  for select to anon, authenticated
  using (true);

create policy invites_read on public.partner_invites
  for select to anon, authenticated
  using (active or public.is_admin());

revoke insert, update, delete on public.partner_invites from anon, authenticated;

create policy venues_select on public.venues
  for select to anon, authenticated
  using (
    status = 'approved'
    or owner_id = auth.uid()
    or public.is_admin()
  );

create policy venues_insert on public.venues
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy venues_update on public.venues
  for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

create policy rooms_select on public.rooms
  for select to anon, authenticated
  using (public.venue_is_visible(venue_id));

create policy rooms_write on public.rooms
  for all to authenticated
  using (public.owns_venue(venue_id) or public.is_admin())
  with check (public.owns_venue(venue_id) or public.is_admin());

create policy room_photos_select on public.room_photos
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_photos.room_id
        and public.venue_is_visible(r.venue_id)
    )
  );

create policy room_photos_write on public.room_photos
  for all to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_photos.room_id
        and (public.owns_venue(r.venue_id) or public.is_admin())
    )
  )
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = room_photos.room_id
        and (public.owns_venue(r.venue_id) or public.is_admin())
    )
  );

create policy room_sessions_select on public.room_sessions
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_sessions.room_id
        and public.venue_is_visible(r.venue_id)
    )
  );

create policy room_sessions_write on public.room_sessions
  for all to authenticated
  using (
    exists (
      select 1 from public.rooms r
      where r.id = room_sessions.room_id
        and (public.owns_venue(r.venue_id) or public.is_admin())
    )
  )
  with check (
    exists (
      select 1 from public.rooms r
      where r.id = room_sessions.room_id
        and (public.owns_venue(r.venue_id) or public.is_admin())
    )
  );

create policy groups_select on public.groups
  for select to anon, authenticated
  using (
    public.venue_is_visible(venue_id)
    or created_by = auth.uid()
    or exists (
      select 1 from public.group_members m
      where m.group_id = groups.id
        and m.user_id = auth.uid()
    )
  );

create policy group_members_select on public.group_members
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.groups g
      where g.id = group_members.group_id
        and (
          public.venue_is_visible(g.venue_id)
          or g.created_by = auth.uid()
          or group_members.user_id = auth.uid()
        )
    )
  );

create policy waitlist_select on public.waitlist
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.groups g
      where g.id = waitlist.group_id
        and (g.created_by = auth.uid() or public.owns_venue(g.venue_id))
    )
  );

create policy news_select on public.news_items
  for select to anon, authenticated
  using (public.venue_is_visible(venue_id));

create policy news_write on public.news_items
  for all to authenticated
  using (public.owns_venue(venue_id) or public.is_admin())
  with check (public.owns_venue(venue_id) or public.is_admin());

create policy promotions_select on public.promotions
  for select to anon, authenticated
  using (
    public.venue_is_visible(venue_id)
    and (
      active
      or public.owns_venue(venue_id)
      or public.is_admin()
    )
  );

create policy promotions_write on public.promotions
  for all to authenticated
  using (public.owns_venue(venue_id) or public.is_admin())
  with check (public.owns_venue(venue_id) or public.is_admin());

create policy absences_select on public.absences
  for select to authenticated
  using (
    public.owns_venue(venue_id)
    or public.is_admin()
    or user_id = auth.uid()
  );

create policy absences_insert on public.absences
  for insert to authenticated
  with check (public.owns_venue(venue_id) or public.is_admin());

create policy ledger_select on public.ledger_entries
  for select to authenticated
  using (
    (account = 'house' and (public.owns_venue(venue_id) or public.is_admin()))
    or user_id = auth.uid()
  );

create policy settings_admin on public.platform_settings
  for select to authenticated
  using (public.is_admin());

revoke insert, update, delete on public.cities from anon, authenticated;
revoke insert, update, delete on public.groups from anon, authenticated;
revoke insert, update, delete on public.group_members from anon, authenticated;
revoke insert, update, delete on public.waitlist from anon, authenticated;
revoke insert, update, delete on public.ledger_entries from anon, authenticated;
revoke insert, update, delete on public.platform_settings from anon, authenticated;
revoke insert, update, delete on public.admins from anon, authenticated;
revoke insert, delete on public.profiles from anon, authenticated;

grant select on public.groups_with_counts to anon, authenticated;

insert into storage.buckets (id, name, public)
values ('room-photos', 'room-photos', true)
on conflict (id) do nothing;

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
        or v.owner_id = auth.uid()
        or public.is_admin()
      )
  );
$$;

revoke all on function public.room_photo_object_allowed(text) from public;
grant execute on function public.room_photo_object_allowed(text) to anon, authenticated;

create policy room_photos_storage_read on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'room-photos'
    and public.room_photo_object_allowed(name)
  );

create policy room_photos_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = auth.uid()
    )
  );

create policy room_photos_storage_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = auth.uid()
    )
  );

create policy room_photos_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'room-photos'
    and exists (
      select 1 from public.venues v
      where v.id::text = split_part(name, '/', 1)
        and v.owner_id = auth.uid()
    )
  );

alter table public.group_members replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'group_members'
  ) then
    alter publication supabase_realtime add table public.group_members;
  end if;
end $$;
