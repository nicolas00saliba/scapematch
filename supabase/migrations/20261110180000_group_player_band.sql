-- Faixa do host: mínimo confirma, máximo lota.
-- Não edita migrations antigas. Não aplica no projeto remoto.
--
-- Grupos que já existiam tinham um alvo Z em total_spots e o mínimo da
-- sala em minimum_spots. A opção segura é mín = Z e máx = Z: o grupo
-- continua confirmando e lotando no mesmo número, sem abrir vaga nova
-- nem capturar antes. O prazo passa a exigir Z, não só o mínimo da sala.
-- Quem já tinha fechado ganha confirmed_at = closed_at.

alter table public.groups
  add column if not exists confirmed_at timestamptz;

comment on column public.groups.confirmed_at is
  'Quando o grupo atingiu o mínimo do host. A cobrança confirma aqui e o grupo segue aberto até o máximo.';

comment on column public.groups.minimum_spots is
  'Mínimo escolhido pelo host, dentro da faixa da sala. Confirma o jogo e o prazo usa este número.';

comment on column public.groups.total_spots is
  'Máximo escolhido pelo host. O grupo lota aqui e a lista de espera vale a partir daqui.';

update public.groups
set minimum_spots = total_spots
where minimum_spots is distinct from total_spots;

update public.groups
set confirmed_at = closed_at
where closed_at is not null
  and confirmed_at is null;

create or replace function private.mark_group_bounds(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_filled integer;
begin
  v_filled := private.group_filled_spots(p_group_id);
  -- Prazo vencido sem confirmed_at não confirma, mesmo se o mínimo
  -- for atingido depois. Grupo já confirmado segue até o máximo.
  update public.groups
  set confirmed_at = case
        when confirmed_at is not null then confirmed_at
        when closes_at is not null and closes_at <= pg_catalog.now() then confirmed_at
        when v_filled >= minimum_spots then pg_catalog.now()
        else confirmed_at
      end,
      closed_at = case
        when cancelled_at is not null then closed_at
        when confirmed_at is null
          and closes_at is not null
          and closes_at <= pg_catalog.now() then closed_at
        when v_filled >= total_spots then coalesce(closed_at, pg_catalog.now())
        else null
      end
  where id = p_group_id;
end;
$$;

revoke all on function private.mark_group_bounds(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.sync_bounds_from_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.mark_group_bounds(coalesce(new.group_id, old.group_id));
  return null;
end;
$$;

revoke all on function private.sync_bounds_from_member()
  from public, anon, authenticated, service_role;

drop trigger if exists group_members_sync_bounds on public.group_members;
create trigger group_members_sync_bounds
  after insert or delete or update of attendance
  on public.group_members
  for each row
  execute function private.sync_bounds_from_member();

-- Quatro argumentos, sem default no mínimo, para a função de três
-- argumentos continuar única. Mínimo nulo vira faixa exata no máximo.
create or replace function public.create_group(
  p_session_id uuid,
  p_total_spots integer,
  p_note text,
  p_minimum_spots integer
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
  v_venue public.venues%rowtype;
  v_name text;
  v_note text;
  v_group_id uuid;
  v_closes timestamptz;
  v_minimum integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;
  if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;

  select * into v_room from public.rooms where id = v_session.room_id;
  if not found then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;
  select * into v_venue from public.venues where id = v_room.venue_id;
  if v_venue.status <> 'approved' then
    raise exception 'venue not approved' using errcode = '42501';
  end if;

  v_minimum := coalesce(p_minimum_spots, p_total_spots);
  if v_minimum < v_room.minimum_players or p_total_spots < v_room.minimum_players then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if v_minimum > v_room.capacity or p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  if p_total_spots < v_minimum then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if v_session.starts_at <= pg_catalog.now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_session.starts_at - pg_catalog.now() <= interval '1 hour' then
    raise exception 'too close to create' using errcode = '22023';
  end if;
  if private.user_has_overlap(v_user, v_session.starts_at, v_room.duration_minutes, null::uuid) then
    raise exception 'overlaps' using errcode = 'P0001';
  end if;

  v_name := private.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;
  v_note := trim(coalesce(p_note, ''));
  if char_length(v_note) > 280 then
    raise exception 'note too long' using errcode = '22023';
  end if;

  if v_session.starts_at - interval '24 hours' > pg_catalog.now() then
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
    p_total_spots, v_minimum, v_room.price_cents, v_room.price_mode,
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

create or replace function public.create_group(
  p_session_id uuid,
  p_total_spots integer,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return public.create_group(p_session_id, p_total_spots, p_note, p_total_spots);
end;
$$;

revoke all on function public.create_group(uuid, integer, text, integer)
  from public, anon, authenticated;
revoke all on function public.create_group(uuid, integer, text)
  from public, anon, authenticated;

grant execute on function public.create_group(uuid, integer, text, integer)
  to authenticated, service_role;
grant execute on function public.create_group(uuid, integer, text)
  to authenticated, service_role;

create or replace function public.create_group_with_party(
  p_session_id uuid,
  p_open_spots integer,
  p_note text,
  p_companion_ids uuid[],
  p_minimum_spots integer
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
  v_group_id := public.create_group(
    p_session_id,
    v_total,
    p_note,
    coalesce(p_minimum_spots, v_total)
  );

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
  perform private.mark_group_bounds(v_group_id);
  return v_group_id;
end;
$$;

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
begin
  return public.create_group_with_party(
    p_session_id,
    p_open_spots,
    p_note,
    p_companion_ids,
    null
  );
end;
$$;

revoke all on function public.create_group_with_party(uuid, integer, text, uuid[], integer)
  from public, anon, authenticated;
revoke all on function public.create_group_with_party(uuid, integer, text, uuid[])
  from public, anon, authenticated;

grant execute on function public.create_group_with_party(uuid, integer, text, uuid[], integer)
  to authenticated, service_role;
grant execute on function public.create_group_with_party(uuid, integer, text, uuid[])
  to authenticated, service_role;

create or replace function public.edit_group(
  p_group_id uuid,
  p_total_spots integer,
  p_note text,
  p_minimum_spots integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_filled integer;
  v_note text;
  v_minimum integer;
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
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= pg_catalog.now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;
  v_filled := private.group_filled_spots(p_group_id);
  v_minimum := coalesce(p_minimum_spots, v_group.minimum_spots);
  if v_minimum < v_room.minimum_players then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if v_minimum > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  if p_total_spots < 2 then
    raise exception 'below minimum' using errcode = '22023';
  end if;
  if p_total_spots < v_minimum then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if p_total_spots < v_filled then
    raise exception 'below occupancy' using errcode = '22023';
  end if;
  if p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  if v_group.confirmed_at is not null and v_minimum > v_filled then
    raise exception 'already confirmed' using errcode = 'P0001';
  end if;
  v_note := trim(coalesce(p_note, ''));
  if char_length(v_note) > 280 then
    raise exception 'note too long' using errcode = '22023';
  end if;
  update public.groups
    set total_spots = p_total_spots,
        minimum_spots = v_minimum,
        note = v_note
    where id = p_group_id;
  perform private.mark_group_bounds(p_group_id);
  perform private.offer_waitlist(p_group_id);
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
set search_path = ''
as $$
begin
  perform public.edit_group(p_group_id, p_total_spots, p_note, null);
end;
$$;

revoke all on function public.edit_group(uuid, integer, text, integer)
  from public, anon, authenticated;
revoke all on function public.edit_group(uuid, integer, text)
  from public, anon, authenticated;

grant execute on function public.edit_group(uuid, integer, text, integer)
  to authenticated, service_role;
grant execute on function public.edit_group(uuid, integer, text)
  to authenticated, service_role;

-- O grupo confirma sozinho no mínimo e fica aberto até o máximo.
create or replace function public.close_group_with_fewer(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'group stays open until maximum' using errcode = 'P0001';
end;
$$;

create or replace function private.notify_settle_on_close()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_confirmed boolean;
  v_closed boolean;
begin
  v_confirmed := new.confirmed_at is not null
    and (tg_op = 'INSERT' or old.confirmed_at is distinct from new.confirmed_at);
  v_closed := new.closed_at is not null
    and (tg_op = 'INSERT' or old.closed_at is distinct from new.closed_at);
  if not v_confirmed and not v_closed then
    return new;
  end if;
  begin
    select btrim(s.decrypted_secret) into v_url
    from vault.decrypted_secrets s
    where s.name = 'reconcile_payments_url'
    limit 1;
    select btrim(s.decrypted_secret) into v_secret
    from vault.decrypted_secrets s
    where s.name = 'reconcile_secret'
    limit 1;
    if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
      return new;
    end if;
    perform net.http_post(
      url := v_url,
      body := pg_catalog.jsonb_build_object('settle_group_id', new.id),
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'x-reconcile-secret', v_secret
      ),
      timeout_milliseconds := 90000
    );
  exception
    when others then
      return new;
  end;
  return new;
end;
$$;

drop trigger if exists groups_settle_on_close on public.groups;
create trigger groups_settle_on_close
  after update of confirmed_at, closed_at on public.groups
  for each row
  when (
    (new.confirmed_at is not null and old.confirmed_at is distinct from new.confirmed_at)
    or (new.closed_at is not null and old.closed_at is distinct from new.closed_at)
  )
  execute function private.notify_settle_on_close();

-- A view guarda a lista de colunas de groups na criação. Sem recriar,
-- confirmed_at não aparece em groups_with_counts.
drop view public.groups_with_counts;
create view public.groups_with_counts
with (security_invoker = true) as
select
  g.*,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance <> 'cancelled'
  ) as filled_spots,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance = 'confirmed'
  ) as confirmed_count
from public.groups g;

grant select on public.groups_with_counts to anon, authenticated, service_role;

-- Prazo vencido sem confirmação recusa entrada. Grupo já confirmado
-- continua aberto até o máximo, mesmo depois de closes_at.
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
  if v_group.confirmed_at is null
     and v_group.closes_at is not null
     and v_group.closes_at <= pg_catalog.now() then
    raise exception 'O prazo deste grupo acabou' using errcode = 'P0001';
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
  if v_group.confirmed_at is null
     and v_group.closes_at is not null
     and v_group.closes_at <= pg_catalog.now() then
    raise exception 'O prazo deste grupo acabou' using errcode = 'P0001';
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


create or replace function public.expire_unconfirmed_groups()
returns setof uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.groups
  set cancelled_at = pg_catalog.now(),
      cancel_reason = 'O grupo não confirmou a tempo'
  where cancelled_at is null
    and confirmed_at is null
    and closed_at is null
    and closes_at is not null
    and closes_at <= pg_catalog.now()
  returning id;
end;
$$;

revoke all on function public.expire_unconfirmed_groups()
  from public, anon, authenticated;
grant execute on function public.expire_unconfirmed_groups() to service_role;
