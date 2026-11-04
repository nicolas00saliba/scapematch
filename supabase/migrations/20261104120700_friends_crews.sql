-- Amigos, turmas e entrada em grupo com várias vagas.
-- Aplica depois de 20261104120500_privacy.sql. Não lê tabela de nota fiscal.
-- Não aplicar no projeto remoto até a revisão. O app de exemplo continua
-- em memória; estas funções são a troca.
--
-- Pagamento: cada pessoa paga a própria parte (payment_status pending).
-- O líder não é cobrado pelas outras cadeiras. A reserva das vagas é
-- atômica: ou a turma inteira senta, ou ninguém senta.

alter table public.profiles
  add column username text;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]{3,20}$');

create unique index profiles_username_unique
  on public.profiles (username)
  where username is not null;

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status text not null check (status in ('pending', 'accepted', 'blocked')),
  blocked_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requester_id <> addressee_id),
  check (
    (status = 'blocked' and blocked_by is not null)
    or (status <> 'blocked' and blocked_by is null)
  ),
  check (blocked_by is null or blocked_by in (requester_id, addressee_id))
);

create unique index friendships_one_pair
  on public.friendships (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  );

create index friendships_by_requester on public.friendships (requester_id);
create index friendships_by_addressee on public.friendships (addressee_id);

create table public.friend_invites (
  code text primary key,
  owner_id uuid not null unique references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  check (code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  check (char_length(code) between 4 and 40)
);

create table public.crews (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  photo_path text check (photo_path is null or char_length(photo_path) between 1 and 200),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index crews_by_creator on public.crews (created_by);

create table public.crew_members (
  id uuid primary key default gen_random_uuid(),
  crew_id uuid not null references public.crews (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null check (status in ('invited', 'accepted', 'left')),
  created_at timestamptz not null default now(),
  unique (crew_id, user_id)
);

create index crew_members_by_user on public.crew_members (user_id);

create table public.app_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in (
    'friend_request',
    'friend_accepted',
    'crew_invite',
    'party_seat'
  )),
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 280),
  group_id uuid references public.groups (id) on delete set null,
  scope text not null default '',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index app_notices_by_user on public.app_notices (user_id, created_at desc);

alter table public.friendships enable row level security;
alter table public.friend_invites enable row level security;
alter table public.crews enable row level security;
alter table public.crew_members enable row level security;
alter table public.app_notices enable row level security;

revoke all on table public.friendships from public, anon, authenticated;
revoke all on table public.friend_invites from public, anon, authenticated;
revoke all on table public.crews from public, anon, authenticated;
revoke all on table public.crew_members from public, anon, authenticated;
revoke all on table public.app_notices from public, anon, authenticated;

grant select on table public.friendships to authenticated;
grant select on table public.friend_invites to authenticated;
grant select on table public.crews to authenticated;
grant select on table public.crew_members to authenticated;
grant select on table public.app_notices to authenticated;

-- Cada pessoa só lê o próprio vínculo. Anon não tem grant nem política.
create policy friendships_select on public.friendships
  for select to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

create policy friend_invites_select on public.friend_invites
  for select to authenticated
  using (owner_id = (select auth.uid()));

create policy crews_select on public.crews
  for select to authenticated
  using (
    deleted_at is null
    and exists (
      select 1
      from public.crew_members mine
      where mine.crew_id = crews.id
        and mine.user_id = (select auth.uid())
        and mine.status in ('invited', 'accepted')
    )
  );

create policy crew_members_select on public.crew_members
  for select to authenticated
  using (
    exists (
      select 1
      from public.crew_members mine
      where mine.crew_id = crew_members.crew_id
        and mine.user_id = (select auth.uid())
        and mine.status in ('invited', 'accepted')
    )
  );

create policy app_notices_select on public.app_notices
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Cartão público. Sem nascimento, e-mail ou pagamento.
create or replace function public.users_are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships
    where status = 'accepted'
      and (
        (requester_id = p_a and addressee_id = p_b)
        or (requester_id = p_b and addressee_id = p_a)
      )
  );
$$;

create or replace function public.post_app_notice(
  p_user uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_group_id uuid,
  p_scope text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_notices (user_id, kind, title, body, group_id, scope)
  values (
    p_user,
    p_kind,
    left(p_title, 80),
    left(p_body, 280),
    p_group_id,
    coalesce(p_scope, '')
  );
end;
$$;

create or replace function public.set_my_username(p_username text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_name text := lower(trim(coalesce(p_username, '')));
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if left(v_name, 1) = '@' then
    v_name := substr(v_name, 2);
  end if;
  if v_name !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'invalid username' using errcode = '22023';
  end if;
  update public.profiles
    set username = v_name
    where id = v_user;
  if not found then
    raise exception 'profile missing' using errcode = 'P0002';
  end if;
  return v_name;
exception
  when unique_violation then
    raise exception 'username taken' using errcode = '23505';
end;
$$;

create or replace function public.request_friend_by_username(p_username text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_name text := lower(trim(coalesce(p_username, '')));
  v_other uuid;
  v_row public.friendships%rowtype;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if left(v_name, 1) = '@' then
    v_name := substr(v_name, 2);
  end if;
  if v_name !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'invalid username' using errcode = '22023';
  end if;
  select id into v_other from public.profiles where username = v_name;
  if v_other is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if v_other = v_user then
    raise exception 'cannot friend self' using errcode = '22023';
  end if;

  select * into v_row
  from public.friendships
  where least(requester_id, addressee_id) = least(v_user, v_other)
    and greatest(requester_id, addressee_id) = greatest(v_user, v_other)
  for update;

  if found then
    if v_row.status = 'blocked' then
      raise exception 'blocked' using errcode = '42501';
    end if;
    if v_row.status = 'accepted' then
      raise exception 'already friends' using errcode = '23505';
    end if;
    if v_row.addressee_id = v_user then
      update public.friendships
        set status = 'accepted', updated_at = now()
        where id = v_row.id;
      perform public.post_app_notice(
        v_row.requester_id,
        'friend_accepted',
        'Amizade aceita',
        'Seu pedido de amizade foi aceito.',
        null,
        v_row.id::text
      );
      return v_row.id;
    end if;
    raise exception 'already requested' using errcode = '23505';
  end if;

  insert into public.friendships (requester_id, addressee_id, status)
  values (v_user, v_other, 'pending')
  returning id into v_id;

  perform public.post_app_notice(
    v_other,
    'friend_request',
    'Pedido de amizade',
    'Você recebeu um pedido de amizade.',
    null,
    v_id::text
  );
  return v_id;
end;
$$;

create or replace function public.my_friend_invite()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select code into v_code from public.friend_invites where owner_id = v_user;
  if found then
    return v_code;
  end if;
  v_code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  insert into public.friend_invites (code, owner_id) values (v_code, v_user);
  return v_code;
end;
$$;

create or replace function public.request_friend_by_invite(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_owner uuid;
  v_username text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select owner_id into v_owner
  from public.friend_invites
  where code = lower(trim(coalesce(p_code, '')));
  if v_owner is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  select username into v_username from public.profiles where id = v_owner;
  if v_username is null then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  return public.request_friend_by_username(v_username);
end;
$$;

create or replace function public.respond_friendship(
  p_friendship_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row public.friendships%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_row
  from public.friendships
  where id = p_friendship_id
  for update;
  if not found then
    raise exception 'friendship not found' using errcode = 'P0002';
  end if;
  if v_row.addressee_id is distinct from v_user or v_row.status <> 'pending' then
    raise exception 'not addressee' using errcode = '42501';
  end if;
  if p_accept then
    update public.friendships
      set status = 'accepted', updated_at = now()
      where id = v_row.id;
    perform public.post_app_notice(
      v_row.requester_id,
      'friend_accepted',
      'Amizade aceita',
      'Seu pedido de amizade foi aceito.',
      null,
      v_row.id::text
    );
  else
    delete from public.friendships where id = v_row.id;
  end if;
end;
$$;

create or replace function public.remove_friend(p_other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.friendships
  where status = 'accepted'
    and (
      (requester_id = v_user and addressee_id = p_other)
      or (addressee_id = v_user and requester_id = p_other)
    );
  if not found then
    raise exception 'not friends' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.block_user(p_other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row public.friendships%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_other is null or p_other = v_user then
    raise exception 'invalid user' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_other) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  select * into v_row
  from public.friendships
  where least(requester_id, addressee_id) = least(v_user, p_other)
    and greatest(requester_id, addressee_id) = greatest(v_user, p_other)
  for update;
  if found then
    update public.friendships
      set status = 'blocked', blocked_by = v_user, updated_at = now()
      where id = v_row.id;
  else
    insert into public.friendships (requester_id, addressee_id, status, blocked_by)
    values (v_user, p_other, 'blocked', v_user);
  end if;
end;
$$;

create or replace function public.unblock_user(p_other uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  delete from public.friendships
  where status = 'blocked'
    and blocked_by = v_user
    and (
      (requester_id = v_user and addressee_id = p_other)
      or (addressee_id = v_user and requester_id = p_other)
    );
  if not found then
    raise exception 'not blocked' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.list_my_friends()
returns table (
  friendship_id uuid,
  user_id uuid,
  username text,
  display_name text,
  status text,
  incoming boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    f.id,
    case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end,
    p.username,
    p.display_name,
    f.status,
    f.addressee_id = auth.uid()
  from public.friendships f
  join public.profiles p
    on p.id = case
      when f.requester_id = auth.uid() then f.addressee_id
      else f.requester_id
    end
  where auth.uid() is not null
    and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    and (f.status <> 'blocked' or f.blocked_by = auth.uid());
$$;

create or replace function public.create_crew(
  p_name text,
  p_photo text,
  p_friend_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_photo text := nullif(trim(coalesce(p_photo, '')), '');
  v_id uuid;
  v_friend uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 40 then
    raise exception 'invalid crew name' using errcode = '22023';
  end if;
  if p_friend_ids is null or cardinality(p_friend_ids) = 0 then
    raise exception 'crew needs a friend' using errcode = '22023';
  end if;
  select count(distinct id) into v_count from unnest(p_friend_ids) as t(id);
  if v_count <> cardinality(p_friend_ids) or v_user = any (p_friend_ids) then
    raise exception 'invalid crew members' using errcode = '22023';
  end if;
  if v_count > 11 then
    raise exception 'crew too big' using errcode = '22023';
  end if;
  foreach v_friend in array p_friend_ids loop
    if not public.users_are_friends(v_user, v_friend) then
      raise exception 'not friend' using errcode = '42501';
    end if;
  end loop;

  insert into public.crews (name, photo_path, created_by)
  values (v_name, v_photo, v_user)
  returning id into v_id;

  insert into public.crew_members (crew_id, user_id, status)
  values (v_id, v_user, 'accepted');

  foreach v_friend in array p_friend_ids loop
    insert into public.crew_members (crew_id, user_id, status)
    values (v_id, v_friend, 'invited');
    perform public.post_app_notice(
      v_friend,
      'crew_invite',
      'Convite de turma',
      'Você foi chamado para a turma ' || v_name || '.',
      null,
      v_id::text
    );
  end loop;
  return v_id;
end;
$$;

create or replace function public.respond_crew(p_crew_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_crew public.crews%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_crew from public.crews where id = p_crew_id and deleted_at is null;
  if not found then
    raise exception 'crew not found' using errcode = 'P0002';
  end if;
  update public.crew_members
    set status = case when p_accept then 'accepted' else 'left' end
    where crew_id = p_crew_id
      and user_id = v_user
      and status = 'invited';
  if not found then
    raise exception 'no invite' using errcode = 'P0002';
  end if;
  if p_accept then
    perform public.post_app_notice(
      v_crew.created_by,
      'crew_invite',
      'Turma',
      'Alguém entrou na turma ' || v_crew.name || '.',
      null,
      p_crew_id::text || '-' || v_user::text
    );
  end if;
end;
$$;

create or replace function public.leave_crew(p_crew_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_crew public.crews%rowtype;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_crew from public.crews where id = p_crew_id and deleted_at is null;
  if not found then
    raise exception 'crew not found' using errcode = 'P0002';
  end if;
  if v_crew.created_by = v_user then
    raise exception 'creator must delete' using errcode = 'P0001';
  end if;
  update public.crew_members
    set status = 'left'
    where crew_id = p_crew_id and user_id = v_user and status = 'accepted';
  if not found then
    raise exception 'not member' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.delete_crew(p_crew_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  update public.crews
    set deleted_at = now()
    where id = p_crew_id and created_by = v_user and deleted_at is null;
  if not found then
    raise exception 'not creator' using errcode = '42501';
  end if;
  update public.crew_members
    set status = 'left'
    where crew_id = p_crew_id;
end;
$$;

create or replace function public.list_my_crews()
returns table (
  crew_id uuid,
  crew_name text,
  photo_path text,
  created_by uuid,
  my_status text,
  member_id uuid,
  member_name text,
  member_username text,
  member_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.photo_path,
    c.created_by,
    mine.status,
    m.user_id,
    p.display_name,
    p.username,
    m.status
  from public.crews c
  join public.crew_members mine
    on mine.crew_id = c.id
   and mine.user_id = auth.uid()
   and mine.status in ('invited', 'accepted')
  join public.crew_members m
    on m.crew_id = c.id
   and m.status <> 'left'
  join public.profiles p on p.id = m.user_id
  where auth.uid() is not null
    and c.deleted_at is null;
$$;

-- Trava o grupo e senta a turma inteira, ou não senta ninguém.
create or replace function public.join_group_with_party(
  p_group_id uuid,
  p_companion_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
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
  select count(distinct id) into v_count from unnest(p_companion_ids) as t(id);
  if v_count <> cardinality(p_companion_ids)
    or v_user = any (p_companion_ids)
    or exists (select 1 from unnest(p_companion_ids) as t(id) where t.id is null)
  then
    raise exception 'invalid companion' using errcode = '22023';
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
  if v_group.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = v_group.room_id;
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;

  v_party := array[v_user] || p_companion_ids;

  foreach v_person in array p_companion_ids loop
    if not public.users_are_friends(v_user, v_person) then
      raise exception 'not friend' using errcode = '42501';
    end if;
  end loop;

  foreach v_person in array v_party loop
    if exists (
      select 1 from public.group_members
      where group_id = p_group_id and user_id = v_person
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
    if public.user_has_overlap(
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
      raise exception 'blocked' using errcode = '42501';
    end if;
  end loop;

  v_filled := public.group_filled_spots(p_group_id);
  select count(*)::integer into v_offers
  from public.waitlist
  where group_id = p_group_id
    and offer_expires_at is not null
    and offer_expires_at > now()
    and not (user_id = any (v_party));

  if v_filled + coalesce(v_offers, 0) + cardinality(v_party) > v_group.total_spots then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;

  foreach v_person in array v_party loop
    v_name := public.profile_display_name(v_person);
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
      perform public.post_app_notice(
        v_person,
        'party_seat',
        'Vaga reservada',
        'Sua turma reservou sua vaga. Pague a sua parte.',
        p_group_id,
        p_group_id::text || '-' || v_person::text
      );
    end if;
  end loop;

  if public.group_filled_spots(p_group_id) > v_group.total_spots then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;

  if public.group_filled_spots(p_group_id) >= v_group.total_spots then
    update public.groups
      set closed_at = coalesce(closed_at, now())
      where id = p_group_id;
  end if;

  return v_leader_member;
end;
$$;

-- Cria o grupo já com a turma sentada e com vagas abertas para desconhecidos.
create or replace function public.create_group_with_party(
  p_session_id uuid,
  p_open_spots integer,
  p_note text,
  p_companion_ids uuid[]
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
  select count(distinct id) into v_count from unnest(p_companion_ids) as t(id);
  if v_count <> cardinality(p_companion_ids) or v_user = any (p_companion_ids) then
    raise exception 'invalid companion' using errcode = '22023';
  end if;

  select * into v_session from public.room_sessions where id = p_session_id;
  if not found then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;
  select * into v_room from public.rooms where id = v_session.room_id;

  foreach v_person in array p_companion_ids loop
    if not public.users_are_friends(v_user, v_person) then
      raise exception 'not friend' using errcode = '42501';
    end if;
    if public.user_has_overlap(
      v_person, v_session.starts_at, v_room.duration_minutes, null
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
  end loop;

  v_total := 1 + cardinality(p_companion_ids) + p_open_spots;
  v_group_id := public.create_group(p_session_id, v_total, p_note);

  foreach v_person in array p_companion_ids loop
    v_name := public.profile_display_name(v_person);
    if v_name is null then
      raise exception 'display name required' using errcode = '22023';
    end if;
    insert into public.group_members (
      group_id, user_id, display_name, is_creator, payment_status
    ) values (
      v_group_id, v_person, v_name, false, 'pending'
    );
    perform public.post_app_notice(
      v_person,
      'party_seat',
      'Vaga reservada',
      'Você entrou num grupo com a sua turma. Pague a sua parte. As outras vagas ficam abertas.',
      v_group_id,
      v_group_id::text || '-' || v_person::text
    );
  end loop;

  if public.group_filled_spots(v_group_id) >= v_total then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;
  return v_group_id;
end;
$$;

create or replace function public.mark_notice_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  update public.app_notices
    set read_at = coalesce(read_at, now())
    where id = p_id and user_id = v_user;
end;
$$;

revoke all on function public.users_are_friends(uuid, uuid) from public, anon, authenticated;
revoke all on function public.post_app_notice(uuid, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.set_my_username(text) from public, anon, authenticated;
revoke all on function public.request_friend_by_username(text) from public, anon, authenticated;
revoke all on function public.my_friend_invite() from public, anon, authenticated;
revoke all on function public.request_friend_by_invite(text) from public, anon, authenticated;
revoke all on function public.respond_friendship(uuid, boolean) from public, anon, authenticated;
revoke all on function public.remove_friend(uuid) from public, anon, authenticated;
revoke all on function public.block_user(uuid) from public, anon, authenticated;
revoke all on function public.unblock_user(uuid) from public, anon, authenticated;
revoke all on function public.list_my_friends() from public, anon, authenticated;
revoke all on function public.create_crew(text, text, uuid[]) from public, anon, authenticated;
revoke all on function public.respond_crew(uuid, boolean) from public, anon, authenticated;
revoke all on function public.leave_crew(uuid) from public, anon, authenticated;
revoke all on function public.delete_crew(uuid) from public, anon, authenticated;
revoke all on function public.list_my_crews() from public, anon, authenticated;
revoke all on function public.join_group_with_party(uuid, uuid[]) from public, anon, authenticated;
revoke all on function public.create_group_with_party(uuid, integer, text, uuid[]) from public, anon, authenticated;
revoke all on function public.mark_notice_read(uuid) from public, anon, authenticated;

grant execute on function public.set_my_username(text) to authenticated, service_role;
grant execute on function public.request_friend_by_username(text) to authenticated, service_role;
grant execute on function public.my_friend_invite() to authenticated, service_role;
grant execute on function public.request_friend_by_invite(text) to authenticated, service_role;
grant execute on function public.respond_friendship(uuid, boolean) to authenticated, service_role;
grant execute on function public.remove_friend(uuid) to authenticated, service_role;
grant execute on function public.block_user(uuid) to authenticated, service_role;
grant execute on function public.unblock_user(uuid) to authenticated, service_role;
grant execute on function public.list_my_friends() to authenticated, service_role;
grant execute on function public.create_crew(text, text, uuid[]) to authenticated, service_role;
grant execute on function public.respond_crew(uuid, boolean) to authenticated, service_role;
grant execute on function public.leave_crew(uuid) to authenticated, service_role;
grant execute on function public.delete_crew(uuid) to authenticated, service_role;
grant execute on function public.list_my_crews() to authenticated, service_role;
grant execute on function public.join_group_with_party(uuid, uuid[]) to authenticated, service_role;
grant execute on function public.create_group_with_party(uuid, integer, text, uuid[]) to authenticated, service_role;
grant execute on function public.mark_notice_read(uuid) to authenticated, service_role;
