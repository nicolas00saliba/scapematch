-- Sessão desativada não recebe grupo nem gente nova.
-- create_group já trava a linha e recusa cancelled_at com PT404
-- 'unknown session'. create_group_with_party lia a sessão sem trava
-- e seguia; o create_group interno só rodava depois. No meio, a casa
-- cancelava o grupo antigo (house_cancel_group), soltava o índice
-- único e só então marcava a sessão. A criação concorrente passava
-- no cheque, gravava membros pendentes e a sessão fechava em seguida.
-- Não há RPC de convite para uma sessão. Quem entra é join_group,
-- join_group_with_party, join_waitlist e accept_waitlist (este chama
-- join_group). A trava da sessão vem antes da trava do grupo, a mesma
-- ordem de remove_room_session.

create or replace function public.create_group_with_party(
  p_session_id uuid,
  p_open_spots integer,
  p_note text,
  p_companion_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_room public.rooms%rowtype;
  v_total integer;
  v_group_id uuid;
  v_person uuid;
  v_name text;
  v_count integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_open_spots is null or p_open_spots < 1 then
    raise exception 'open spot required' using errcode = '22023';
  end if;
  if p_companion_ids is null or cardinality(p_companion_ids) = 0 then
    raise exception 'party empty' using errcode = '22023';
  end if;
  if cardinality(p_companion_ids) > 11 then
    raise exception 'party too large' using errcode = '22023';
  end if;
  select count(distinct id) into v_count from unnest(p_companion_ids) as t(id);
  if v_count <> cardinality(p_companion_ids) or v_user = any (p_companion_ids) then
    raise exception 'invalid companion' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.friendships blocked
    where blocked.status = 'blocked'
      and blocked.requester_id = any (array[v_user] || p_companion_ids)
      and blocked.addressee_id = any (array[v_user] || p_companion_ids)
  ) then
    raise exception 'companion unavailable' using errcode = 'P0001';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;
  if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;
  select * into v_room from public.rooms where id = v_session.room_id;

  foreach v_person in array p_companion_ids loop
    if not exists (
      select 1
      from public.crew_members leader
      join public.crews crew
        on crew.id = leader.crew_id
       and crew.deleted_at is null
      join public.crew_members mate
        on mate.crew_id = leader.crew_id
       and mate.user_id = v_person
       and mate.status = 'accepted'
      where leader.user_id = v_user
        and leader.status = 'accepted'
    ) then
      raise exception 'not crew mate' using errcode = '42501';
    end if;
    if private.user_has_overlap(
      v_person, v_session.starts_at, v_room.duration_minutes, null::uuid
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
  end loop;

  v_total := 1 + cardinality(p_companion_ids) + p_open_spots;
  v_group_id := public.create_group(p_session_id, v_total, p_note);

  foreach v_person in array p_companion_ids loop
    v_name := private.profile_display_name(v_person);
    if v_name is null then
      raise exception 'display name required' using errcode = '22023';
    end if;
    insert into public.group_members (
      group_id, user_id, display_name, is_creator, payment_status
    ) values (
      v_group_id, v_person, v_name, false, 'pending'
    );
    perform private.post_app_notice(
      v_person,
      'party_seat',
      'Vaga reservada',
      'Você entrou num grupo com a sua turma. Pague a sua parte. As outras vagas ficam abertas.',
      v_group_id,
      v_group_id::text || '-' || v_person::text
    );
  end loop;

  if private.group_filled_spots(v_group_id) >= v_total then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;
  return v_group_id;
end;
$$;

create or replace function public.join_group(p_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_session_id uuid;
  v_session public.room_sessions%rowtype;
  v_filled integer;
  v_name text;
  v_existing public.group_members%rowtype;
  v_member_id uuid;
  v_offer integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select session_id
    into v_session_id
  from public.groups
  where id = p_group_id;
  if v_session_id is not null then
    select * into v_session
    from public.room_sessions
    where id = v_session_id
    for update;
    if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
      raise sqlstate 'PT404' using message = 'unknown session';
    end if;
  end if;

  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at <= pg_catalog.now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_group.closed_at is not null then
    raise exception 'group full' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= pg_catalog.now() then
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

  if private.user_has_overlap(
    v_user, v_group.starts_at, v_room.duration_minutes, p_group_id
  ) then
    raise exception 'overlaps' using errcode = 'P0001';
  end if;

  v_filled := private.group_filled_spots(p_group_id);
  if v_filled >= v_group.total_spots then
    raise exception 'group full' using errcode = 'P0001';
  end if;

  select count(*)::integer into v_offer
  from public.waitlist
  where group_id = p_group_id
    and offer_expires_at is not null
    and offer_expires_at > pg_catalog.now()
    and user_id <> v_user;
  if v_filled + v_offer >= v_group.total_spots then
    raise exception 'seat reserved' using errcode = 'P0001';
  end if;

  v_name := private.profile_display_name(v_user);
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

  if private.group_filled_spots(p_group_id) >= v_group.total_spots then
    update public.groups set closed_at = coalesce(closed_at, pg_catalog.now()) where id = p_group_id;
  end if;

  return v_member_id;
end;
$$;

create or replace function public.join_group_with_party(
  p_group_id uuid,
  p_companion_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_session_id uuid;
  v_session public.room_sessions%rowtype;
  v_party uuid[];
  v_person uuid;
  v_filled integer;
  v_offers integer;
  v_name text;
  v_leader_member uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_companion_ids is null or cardinality(p_companion_ids) = 0 then
    raise exception 'party empty' using errcode = '22023';
  end if;
  if cardinality(p_companion_ids) > 11 then
    raise exception 'party too large' using errcode = '22023';
  end if;
  select count(distinct id) into v_count from unnest(p_companion_ids) as t(id);
  if v_count <> cardinality(p_companion_ids)
    or v_user = any (p_companion_ids)
    or exists (select 1 from unnest(p_companion_ids) as t(id) where t.id is null)
  then
    raise exception 'invalid companion' using errcode = '22023';
  end if;

  select session_id
    into v_session_id
  from public.groups
  where id = p_group_id;
  if v_session_id is not null then
    select * into v_session
    from public.room_sessions
    where id = v_session_id
    for update;
    if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
      raise sqlstate 'PT404' using message = 'unknown session';
    end if;
  end if;

  select * into v_group
  from public.groups
  where id = p_group_id
  for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at <= pg_catalog.now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= pg_catalog.now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;

  v_party := array[v_user] || p_companion_ids;

  if exists (
    select 1
    from public.friendships blocked
    where blocked.status = 'blocked'
      and blocked.requester_id = any (v_party)
      and blocked.addressee_id = any (v_party)
  ) then
    raise exception 'companion unavailable' using errcode = 'P0001';
  end if;

  foreach v_person in array p_companion_ids loop
    if not exists (
      select 1
      from public.crew_members leader
      join public.crews crew
        on crew.id = leader.crew_id
       and crew.deleted_at is null
      join public.crew_members mate
        on mate.crew_id = leader.crew_id
       and mate.user_id = v_person
       and mate.status = 'accepted'
      where leader.user_id = v_user
        and leader.status = 'accepted'
    ) then
      raise exception 'not crew mate' using errcode = '42501';
    end if;
  end loop;

  foreach v_person in array v_party loop
    if exists (
      select 1 from public.group_members
      where group_id = p_group_id and user_id = v_person
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
    if private.user_has_overlap(
      v_person, v_group.starts_at, v_room.duration_minutes, p_group_id
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
    if exists (
      select 1
      from public.group_members seated
      join public.friendships f
        on f.status = 'blocked'
       and (
         (f.requester_id = seated.user_id and f.addressee_id = v_person)
         or (f.addressee_id = seated.user_id and f.requester_id = v_person)
       )
      where seated.group_id = p_group_id
        and seated.attendance <> 'cancelled'
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
  end loop;

  v_filled := private.group_filled_spots(p_group_id);
  select count(*)::integer into v_offers
  from public.waitlist
  where group_id = p_group_id
    and offer_expires_at is not null
    and offer_expires_at > pg_catalog.now()
    and not (user_id = any (v_party));

  if v_filled + coalesce(v_offers, 0) + cardinality(v_party) > v_group.total_spots then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;

  foreach v_person in array v_party loop
    v_name := private.profile_display_name(v_person);
    if v_name is null then
      raise exception 'display name required' using errcode = '22023';
    end if;
    insert into public.group_members (
      group_id, user_id, display_name, is_creator, payment_status
    ) values (
      p_group_id, v_person, v_name, false, 'pending'
    );
    delete from public.waitlist
    where group_id = p_group_id and user_id = v_person;
    if v_person = v_user then
      v_leader_member := (
        select id from public.group_members
        where group_id = p_group_id and user_id = v_user
      );
    else
      perform private.post_app_notice(
        v_person,
        'party_seat',
        'Vaga reservada',
        'Sua turma reservou sua vaga. Pague a sua parte.',
        p_group_id,
        p_group_id::text || '-' || v_person::text
      );
    end if;
  end loop;

  if private.group_filled_spots(p_group_id) > v_group.total_spots then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;

  if private.group_filled_spots(p_group_id) >= v_group.total_spots then
    update public.groups
      set closed_at = coalesce(closed_at, pg_catalog.now())
      where id = p_group_id;
  end if;

  return v_leader_member;
end;
$$;

create or replace function public.join_waitlist(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_name text;
  v_session_id uuid;
  v_session public.room_sessions%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select session_id
    into v_session_id
  from public.groups
  where id = p_group_id
    and cancelled_at is null;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_session_id is not null then
    select * into v_session
    from public.room_sessions
    where id = v_session_id
    for update;
    if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
      raise sqlstate 'PT404' using message = 'unknown session';
    end if;
  end if;
  if exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = v_user and attendance <> 'cancelled'
  ) then
    raise exception 'already joined' using errcode = '23505';
  end if;
  v_name := private.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;
  insert into public.waitlist (group_id, user_id, display_name)
  values (p_group_id, v_user, v_name)
  on conflict (group_id, user_id) do nothing;
  perform private.offer_waitlist(p_group_id);
end;
$$;

-- A casa trava a sessão antes de cancelar o grupo. Sem isso, o índice
-- único abre enquanto a sessão ainda parece livre, e a criação
-- concorrente grava o grupo novo.
create or replace function public.house_cancel_group(
  p_group_id uuid,
  p_reason text default 'Cancelada pela casa'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_reason text;
  v_member record;
  v_session_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select session_id
    into v_session_id
  from public.groups
  where id = p_group_id;
  if v_session_id is not null then
    perform 1
    from public.room_sessions
    where id = v_session_id
    for update;
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
  if pg_catalog.now() > v_group.starts_at - interval '2 hours' then
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
    set cancelled_at = pg_catalog.now(), cancel_reason = v_reason
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
      set cancelled_at = pg_catalog.now()
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
    perform private.post_app_notice(
      v_member.user_id,
      'group_cancelled',
      'Sessão cancelada',
      'A casa cancelou a sessão. Se você pagou, o estorno está em andamento.',
      p_group_id,
      'house-cancel-' || p_group_id::text
    );
  end loop;
end;
$$;
