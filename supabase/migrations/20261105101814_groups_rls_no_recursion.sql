-- Quebra a recursão entre groups_select e group_members_select.
-- Substitui a definição de 20261104120500_privacy.sql.
-- Já aplicada no Supabase de produção.

create or replace function public.is_group_member(gid uuid) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.group_members m where m.group_id = gid and m.user_id = (select auth.uid())); $$;
create or replace function public.group_is_readable(gid uuid) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.groups g where g.id = gid and (public.venue_is_visible(g.venue_id) or g.created_by = (select auth.uid()))); $$;
revoke all on function public.is_group_member(uuid) from public, anon;
revoke all on function public.group_is_readable(uuid) from public, anon;
grant execute on function public.is_group_member(uuid) to authenticated, anon;
grant execute on function public.group_is_readable(uuid) to authenticated, anon;
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select using (public.venue_is_visible(venue_id) or created_by = (select auth.uid()) or public.is_group_member(id));
drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members for select using (user_id = (select auth.uid()) or public.group_is_readable(group_id));
