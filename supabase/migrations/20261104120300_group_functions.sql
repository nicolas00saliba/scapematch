-- Entrar, criar, sair e fechar são funções. O app não faz insert em
-- groups nem em group_members. Cada função trava a linha do grupo.

create or replace function public.profile_display_name(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(display_name), '')
  from public.profiles
  where id = p_user;
$$;

create or replace function public.group_filled_spots(p_group_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.group_members
  where group_id = p_group_id
    and attendance <> 'cancelled';
$$;

create or replace function public.sessions_overlap(
  p_start_a timestamptz,
  p_minutes_a integer,
  p_start_b timestamptz,
  p_minutes_b integer
)
returns boolean
language sql
immutable
as $$
  select p_start_a < p_start_b + make_interval(mins => p_minutes_b)
    and p_start_b < p_start_a + make_interval(mins => p_minutes_a);
$$;

create or replace function public.user_has_overlap(
  p_user uuid,
  p_starts_at timestamptz,
  p_minutes integer,
  p_ignore_group uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_members m
    join public.groups g on g.id = m.group_id
    join public.rooms r on r.id = g.room_id
    where m.user_id = p_user
      and m.attendance <> 'cancelled'
      and g.cancelled_at is null
      and g.starts_at + make_interval(mins => r.duration_minutes) > now()
      and (p_ignore_group is null or g.id <> p_ignore_group)
      and public.sessions_overlap(
        g.starts_at,
        r.duration_minutes,
        p_starts_at,
        p_minutes
      )
  );
$$;

create or replace function public.offer_waitlist(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open integer;
  v_offers integer;
  v_next uuid;
begin
  update public.waitlist
    set offer_expires_at = null
    where group_id = p_group_id
      and offer_expires_at is not null
      and offer_expires_at <= now();

  select greatest(g.total_spots - public.group_filled_spots(g.id), 0)
    into v_open
  from public.groups g
  where g.id = p_group_id
    and g.cancelled_at is null
    and g.closed_at is null;

  if v_open is null or v_open = 0 then
    return;
  end if;

  select count(*)::integer
    into v_offers
  from public.waitlist
  where group_id = p_group_id
    and offer_expires_at is not null
    and offer_expires_at > now();

  while v_offers < v_open loop
    select id
      into v_next
    from public.waitlist
    where group_id = p_group_id
      and offer_expires_at is null
    order by joined_at
    limit 1;
    exit when v_next is null;
    update public.waitlist
      set offer_expires_at = now() + interval '2 hours'
      where id = v_next;
    v_offers := v_offers + 1;
  end loop;
end;
$$;

create or replace function public.create_group(
  p_session_id uuid,
  p_total_spots integer,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_room public.rooms%rowtype;
  v_venue public.venues%rowtype;
  v_name text;
  v_note text;
  v_group_id uuid;
  v_closes timestamptz;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;
  if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;

  select * into v_room from public.rooms where id = v_session.room_id;
  if not found then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;
  select * into v_venue from public.venues where id = v_room.venue_id;
  if v_venue.status <> 'approved' then
    raise exception 'venue not approved' using errcode = '42501';
  end if;

  if p_total_spots < v_room.minimum_players then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  if v_session.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_session.starts_at - now() <= interval '1 hour' then
    raise exception 'too close to create' using errcode = '22023';
  end if;
  if public.user_has_overlap(v_user, v_session.starts_at, v_room.duration_minutes, null) then
    raise exception 'overlaps' using errcode = 'P0001';
  end if;

  v_name := public.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;
  v_note := trim(coalesce(p_note, ''));
  if char_length(v_note) > 280 then
    raise exception 'note too long' using errcode = '22023';
  end if;

  if v_session.starts_at - interval '24 hours' > now() then
    v_closes := v_session.starts_at - interval '24 hours';
  else
    v_closes := v_session.starts_at - interval '1 hour';
  end if;

  insert into public.groups (
    city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, price_mode,
    note, cancel_window_minutes, created_by, closes_at
  ) values (
    v_venue.city_id, v_venue.id, v_room.id, v_session.id, v_session.starts_at,
    p_total_spots, v_room.minimum_players, v_room.price_cents, v_room.price_mode,
    v_note, v_room.cancel_window_minutes, v_user, v_closes
  )
  returning id into v_group_id;

  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status
  ) values (
    v_group_id, v_user, v_name, true, 'pending'
  );

  return v_group_id;
exception
  when unique_violation then
    raise exception 'duplicate session' using errcode = '23505';
end;
$$;

create or replace function public.join_group(p_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_filled integer;
  v_name text;
  v_existing public.group_members%rowtype;
  v_member_id uuid;
  v_offer integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_group.closed_at is not null then
    raise exception 'group full' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;

  select * into v_existing
  from public.group_members
  where group_id = p_group_id and user_id = v_user;
  if found then
    if v_existing.attendance = 'cancelled' then
      raise exception 'membership closed' using errcode = 'P0001';
    end if;
    raise exception 'already joined' using errcode = '23505';
  end if;

  if public.user_has_overlap(
    v_user, v_group.starts_at, v_room.duration_minutes, p_group_id
  ) then
    raise exception 'overlaps' using errcode = 'P0001';
  end if;

  v_filled := public.group_filled_spots(p_group_id);
  if v_filled >= v_group.total_spots then
    raise exception 'group full' using errcode = 'P0001';
  end if;

  -- Oferta aberta para outra pessoa cobre a vaga. Quem tem a oferta passa.
  select count(*)::integer into v_offer
  from public.waitlist
  where group_id = p_group_id
    and offer_expires_at is not null
    and offer_expires_at > now()
    and user_id <> v_user;
  if v_filled + v_offer >= v_group.total_spots then
    raise exception 'seat reserved' using errcode = 'P0001';
  end if;

  v_name := public.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;

  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status
  ) values (
    p_group_id, v_user, v_name, false, 'pending'
  )
  returning id into v_member_id;

  delete from public.waitlist
  where group_id = p_group_id and user_id = v_user;

  if public.group_filled_spots(p_group_id) >= v_group.total_spots then
    update public.groups set closed_at = coalesce(closed_at, now()) where id = p_group_id;
  end if;

  return v_member_id;
end;
$$;

create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_in_time boolean;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where group_id = p_group_id and user_id = v_user and attendance <> 'cancelled';
  if not found then
    raise exception 'not member' using errcode = 'P0002';
  end if;
  if v_member.is_creator then
    raise exception 'creator must delete' using errcode = 'P0001';
  end if;

  v_in_time := v_group.starts_at - now() >= make_interval(mins => v_group.cancel_window_minutes);
  update public.group_members
    set attendance = 'cancelled',
        refund_status = case
          when payment_status = 'paid' and v_in_time then 'refunded'
          when payment_status = 'paid' then 'denied'
          else 'none'
        end,
        refund_reason = case
          when payment_status = 'paid' and v_in_time then 'cancelled_in_time'
          when payment_status = 'paid' then 'cancelled_too_late'
          else 'hold_released'
        end,
        payment_status = case
          when payment_status = 'paid' then payment_status
          else 'released'
        end
    where id = v_member.id;

  update public.groups set closed_at = null where id = p_group_id and closed_at is not null
    and public.group_filled_spots(p_group_id) < total_spots;
  perform public.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'already cancelled' using errcode = 'P0001';
  end if;
  -- No instante exato das 2 h ainda pode. Depois disso, não.
  if now() > v_group.starts_at - interval '2 hours' then
    raise exception 'too close to delete' using errcode = 'P0001';
  end if;

  update public.groups
    set cancelled_at = now(), cancel_reason = 'organizer'
    where id = p_group_id;

  update public.group_members
    set attendance = 'cancelled',
        refund_status = case when payment_status = 'paid' then 'refunded' else 'none' end,
        refund_reason = 'organizer_cancelled_event',
        payment_status = case when payment_status = 'paid' then payment_status else 'released' end
    where group_id = p_group_id
      and attendance <> 'cancelled';
end;
$$;

create or replace function public.remove_member(p_group_id uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_room public.rooms%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where id = p_member_id and group_id = p_group_id and attendance <> 'cancelled';
  if not found then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  if v_member.is_creator or v_member.user_id = v_user then
    raise exception 'cannot remove creator' using errcode = 'P0001';
  end if;

  update public.group_members
    set attendance = 'cancelled',
        refund_status = case when payment_status = 'paid' then 'refunded' else 'none' end,
        refund_reason = 'organizer_removed_member',
        payment_status = case when payment_status = 'paid' then payment_status else 'released' end
    where id = v_member.id;

  update public.groups set closed_at = null
    where id = p_group_id
      and public.group_filled_spots(p_group_id) < total_spots;
  perform public.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.edit_group(
  p_group_id uuid,
  p_total_spots integer,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_filled integer;
  v_note text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;
  v_filled := public.group_filled_spots(p_group_id);
  if p_total_spots < 2 then
    raise exception 'below minimum' using errcode = '22023';
  end if;
  if p_total_spots < v_group.minimum_spots then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if p_total_spots < v_filled then
    raise exception 'below occupancy' using errcode = '22023';
  end if;
  if p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  v_note := trim(coalesce(p_note, ''));
  if char_length(v_note) > 280 then
    raise exception 'note too long' using errcode = '22023';
  end if;
  update public.groups
    set total_spots = p_total_spots,
        note = v_note,
        closed_at = case
          when v_filled >= p_total_spots then coalesce(closed_at, now())
          else null
        end
    where id = p_group_id;
  perform public.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.confirm_attendance(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.group_members
    where group_id = p_group_id
      and user_id = v_user
      and attendance = 'confirmed'
  ) then
    return;
  end if;
  update public.group_members
    set attendance = 'confirmed'
    where group_id = p_group_id
      and user_id = v_user
      and attendance = 'joined';
  if not found then
    raise exception 'not member' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.close_group_with_fewer(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_filled integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  v_filled := public.group_filled_spots(p_group_id);
  if v_filled < v_group.minimum_spots then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if v_filled >= v_group.total_spots then
    raise exception 'already planned size' using errcode = 'P0001';
  end if;
  update public.groups
    set total_spots = v_filled,
        closed_at = coalesce(closed_at, now())
    where id = p_group_id;
end;
$$;

create or replace function public.join_waitlist(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_name text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not exists (select 1 from public.groups where id = p_group_id and cancelled_at is null) then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = v_user and attendance <> 'cancelled'
  ) then
    raise exception 'already joined' using errcode = '23505';
  end if;
  v_name := public.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;
  insert into public.waitlist (group_id, user_id, display_name)
  values (p_group_id, v_user, v_name)
  on conflict (group_id, user_id) do nothing;
  perform public.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.decline_waitlist(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.waitlist
  where group_id = p_group_id and user_id = auth.uid();
  perform public.offer_waitlist(p_group_id);
end;
$$;

create or replace function public.accept_waitlist(p_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offer timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select offer_expires_at into v_offer
  from public.waitlist
  where group_id = p_group_id and user_id = auth.uid();
  if not found then
    raise exception 'not on waitlist' using errcode = 'P0002';
  end if;
  if v_offer is null or v_offer <= now() then
    raise exception 'offer expired' using errcode = 'P0001';
  end if;
  return public.join_group(p_group_id);
end;
$$;

create or replace function public.mark_absence(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
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
  if not (public.owns_venue(v_group.venue_id) or public.is_admin()) then
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
$$;

revoke all on function public.profile_display_name(uuid) from public, anon, authenticated;
revoke all on function public.group_filled_spots(uuid) from public, anon, authenticated;
revoke all on function public.sessions_overlap(timestamptz, integer, timestamptz, integer) from public, anon, authenticated;
revoke all on function public.user_has_overlap(uuid, timestamptz, integer, uuid) from public, anon, authenticated;
revoke all on function public.offer_waitlist(uuid) from public, anon, authenticated;
revoke all on function public.create_group(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.join_group(uuid) from public, anon, authenticated;
revoke all on function public.leave_group(uuid) from public, anon, authenticated;
revoke all on function public.delete_group(uuid) from public, anon, authenticated;
revoke all on function public.remove_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.edit_group(uuid, integer, text) from public, anon, authenticated;
revoke all on function public.confirm_attendance(uuid) from public, anon, authenticated;
revoke all on function public.close_group_with_fewer(uuid) from public, anon, authenticated;
revoke all on function public.join_waitlist(uuid) from public, anon, authenticated;
revoke all on function public.decline_waitlist(uuid) from public, anon, authenticated;
revoke all on function public.accept_waitlist(uuid) from public, anon, authenticated;
revoke all on function public.mark_absence(uuid, uuid) from public, anon, authenticated;

grant execute on function public.create_group(uuid, integer, text) to authenticated, service_role;
grant execute on function public.join_group(uuid) to authenticated, service_role;
grant execute on function public.leave_group(uuid) to authenticated, service_role;
grant execute on function public.delete_group(uuid) to authenticated, service_role;
grant execute on function public.remove_member(uuid, uuid) to authenticated, service_role;
grant execute on function public.edit_group(uuid, integer, text) to authenticated, service_role;
grant execute on function public.confirm_attendance(uuid) to authenticated, service_role;
grant execute on function public.close_group_with_fewer(uuid) to authenticated, service_role;
grant execute on function public.join_waitlist(uuid) to authenticated, service_role;
grant execute on function public.decline_waitlist(uuid) to authenticated, service_role;
grant execute on function public.accept_waitlist(uuid) to authenticated, service_role;
grant execute on function public.mark_absence(uuid, uuid) to authenticated, service_role;
