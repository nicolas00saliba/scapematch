-- Ranking de tempo por sala. A flag nasce desligada.
-- A duração já está em rooms.duration_minutes (15 a 480). O tempo
-- lançado guarda uma cópia em segundos, para o "restavam" não mudar
-- se a casa alterar o cadastro depois.
-- Quem lança é a casa (dono ou equipe aceita), a partir de uma sessão
-- real do EscapeMatch. O comparecimento da casa é o check-in do
-- passaporte (PR #111, public.session_checkins). Essa tabela ainda não
-- está na main: enquanto não existir, vale a reserva paga do grupo.
-- Quando existir, só entra quem pagou e foi marcado pela casa.
-- Quem não escapou fica no histórico do jogador e fora do ranking.
-- Leitura pública: top 10, sem dado pessoal além do primeiro nome ou
-- apelido, e só com a flag ligada, a casa aprovada e não suspensa.

create table public.room_time_settings (
  id integer primary key default 1 check (id = 1),
  enabled boolean not null default false,
  updated_at timestamptz,
  updated_by uuid references auth.users (id)
);

insert into public.room_time_settings (id, enabled)
values (1, false);

comment on table public.room_time_settings is
  'Interruptor do ranking de tempo. Nasce desligado.';

create table public.venue_time_ranking (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  show_public boolean not null default true,
  show_members boolean not null default false,
  updated_at timestamptz,
  updated_by uuid references auth.users (id)
);

comment on table public.venue_time_ranking is
  'A casa escolhe se o ranking da sala é público e se os integrantes aparecem. Sem linha, o ranking é público e os nomes ficam ocultos.';

alter table public.groups
  add column team_name text;

alter table public.groups
  drop constraint if exists groups_team_name_len;

alter table public.groups
  add constraint groups_team_name_len
  check (
    team_name is null
    or (
      pg_catalog.char_length(pg_catalog.btrim(team_name)) between 2 and 40
      and team_name = pg_catalog.btrim(team_name)
    )
  );

comment on column public.groups.team_name is
  'Nome escolhido pelo grupo para o ranking. Nulo usa o padrão Grupo. A casa não grava aqui ao lançar o tempo. A view de grupos não foi recriada, então o nome não sai por ela.';

alter table public.profiles
  add column show_in_room_ranking boolean not null default true;

comment on column public.profiles.show_in_room_ranking is
  'O jogador aparece no ranking público. O padrão é aparecer. Desligar tira só o nome dele; a linha do grupo fica.';

create table public.room_time_entries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  group_id uuid not null unique references public.groups (id) on delete cascade,
  group_name text not null check (pg_catalog.char_length(group_name) between 2 and 40),
  elapsed_seconds integer not null,
  duration_seconds integer not null check (duration_seconds between 900 and 28800),
  escaped boolean not null,
  played_at timestamptz not null,
  recorded_by uuid not null references auth.users (id),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz,
  updated_by uuid references auth.users (id),
  removed_at timestamptz,
  removed_by uuid references auth.users (id),
  check (elapsed_seconds between 1 and duration_seconds),
  check (removed_at is null or removed_by is not null)
);

comment on table public.room_time_entries is
  'Um tempo por sessão. Quem não escapou não entra no ranking. Remover é lógico: a auditoria fica.';

create index room_time_entries_by_room
  on public.room_time_entries (room_id, elapsed_seconds, played_at)
  where escaped and removed_at is null;

create index room_time_entries_by_venue
  on public.room_time_entries (venue_id, played_at desc);

create table public.room_time_members (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  entry_id uuid not null references public.room_time_entries (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null check (pg_catalog.char_length(label) between 1 and 24),
  sort_order integer not null check (sort_order > 0),
  published boolean not null default false,
  unique (entry_id, user_id)
);

comment on table public.room_time_members is
  'Vínculo do jogador com o tempo, para o histórico. published libera o primeiro nome ou apelido no ranking.';

create index room_time_members_by_user
  on public.room_time_members (user_id);

create table public.room_time_audit (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  entry_id uuid not null references public.room_time_entries (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  actor_id uuid not null references auth.users (id),
  action text not null check (action in ('record', 'edit', 'remove', 'correct_name')),
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.room_time_audit is
  'Auditoria de lançar, editar, corrigir o nome e remover. O Admin aal2 também grava em admin_audit_log.';

create index room_time_audit_by_entry
  on public.room_time_audit (entry_id, created_at);

alter table public.room_time_settings enable row level security;
alter table public.venue_time_ranking enable row level security;
alter table public.room_time_entries enable row level security;
alter table public.room_time_members enable row level security;
alter table public.room_time_audit enable row level security;

revoke all on table public.room_time_settings from public, anon, authenticated, service_role;
revoke all on table public.venue_time_ranking from public, anon, authenticated, service_role;
revoke all on table public.room_time_entries from public, anon, authenticated, service_role;
revoke all on table public.room_time_members from public, anon, authenticated, service_role;
revoke all on table public.room_time_audit from public, anon, authenticated, service_role;

create or replace function private.room_time_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select settings.enabled from public.room_time_settings settings where settings.id = 1),
    false
  );
$$;

revoke all on function private.room_time_enabled()
  from public, anon, authenticated, service_role;

create or replace function private.room_time_fold(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.lower(
    pg_catalog.translate(
      coalesce(p_text, ''),
      'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
      'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn'
    )
  );
$$;

revoke all on function private.room_time_fold(text)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_blocked(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1
    from pg_catalog.regexp_split_to_table(
      private.room_time_fold(p_text),
      '[^a-z0-9]+'
    ) token
    where token in (
      'porra', 'caralho', 'foda', 'foder', 'fodase', 'puta', 'puto',
      'buceta', 'cu', 'merda', 'bosta', 'viado', 'viada', 'desgraca',
      'arrombado', 'arrombada', 'cacete', 'piranha', 'vadia',
      'fuck', 'shit', 'bitch', 'asshole'
    )
  );
$$;

revoke all on function private.room_time_blocked(text)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_clean_name(p_raw text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := pg_catalog.regexp_replace(
    pg_catalog.btrim(coalesce(p_raw, '')),
    '[[:space:]]+',
    ' ',
    'g'
  );
  if pg_catalog.char_length(v_name) < 2
    or pg_catalog.char_length(v_name) > 40
  then
    raise exception 'O nome do grupo fica entre 2 e 40 caracteres.'
      using errcode = '22023';
  end if;
  if v_name ~ '[[:cntrl:]]'
    or v_name ~ '[@#$%&*_+=<>/\\|\[\]{}~`^,.;:!?()"]'
  then
    raise exception 'O nome do grupo usa letras, números, espaço, apóstrofo ou hífen.'
      using errcode = '22023';
  end if;
  if private.room_time_blocked(v_name) then
    raise exception 'Escolha outro nome para o grupo.'
      using errcode = '22023';
  end if;
  return v_name;
end;
$$;

revoke all on function private.room_time_clean_name(text)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_label(p_raw text, p_strict boolean)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_text text;
begin
  v_text := pg_catalog.left(
    pg_catalog.split_part(pg_catalog.btrim(coalesce(p_raw, '')), ' ', 1),
    24
  );
  if v_text = '' or pg_catalog.strpos(v_text, '@') > 0 then
    if p_strict then
      raise exception 'Nome de integrante não permitido.'
        using errcode = '22023';
    end if;
    return 'Jogador';
  end if;
  if private.room_time_blocked(v_text) then
    if p_strict then
      raise exception 'Nome de integrante não permitido.'
        using errcode = '22023';
    end if;
    return 'Jogador';
  end if;
  return v_text;
end;
$$;

revoke all on function private.room_time_label(text, boolean)
  from public, anon, authenticated, service_role;

-- Ponto de integração com o check-in da casa (PR #111).
-- public.session_checkins guarda (group_id, user_id) marcado pela casa.
-- A tabela não está na main. O SQL dinâmico evita criar a função
-- apontando para uma relação que ainda não existe. Sem ela, a sessão
-- real é o grupo com reserva paga (payment_status = paid, vaga ativa,
-- sem estorno). Com ela, além da reserva é obrigatório o check-in.
create or replace function private.ranking_ready_players(p_group_id uuid)
returns table (user_id uuid, label text, sort_order integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if pg_catalog.to_regclass('public.session_checkins') is null then
    return query
    select
      member.user_id,
      private.room_time_label(profile.display_name, false),
      pg_catalog.row_number() over (
        order by member.joined_at, member.user_id
      )::integer
    from public.group_members member
    join public.profiles profile on profile.id = member.user_id
    where member.group_id = p_group_id
      and member.payment_status = 'paid'
      and member.attendance <> 'cancelled'
      and member.refund_status is distinct from 'refunded';
    return;
  end if;

  return query execute $sql$
    select
      member.user_id,
      private.room_time_label(profile.display_name, false),
      pg_catalog.row_number() over (
        order by member.joined_at, member.user_id
      )::integer
    from public.group_members member
    join public.profiles profile on profile.id = member.user_id
    join public.session_checkins checkin
      on checkin.group_id = member.group_id
     and checkin.user_id = member.user_id
    where member.group_id = $1
      and member.payment_status = 'paid'
      and member.attendance <> 'cancelled'
      and member.refund_status is distinct from 'refunded'
  $sql$ using p_group_id;
end;
$$;

comment on function private.ranking_ready_players(uuid) is
  'Jogadores da sessão que podem receber o tempo. Integra com public.session_checkins (PR #111) quando a tabela existir; senão usa a reserva paga.';

revoke all on function private.ranking_ready_players(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_require_manager(p_venue_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if private.owns_venue(p_venue_id) or exists (
    select 1
    from public.venue_staff staff
    where staff.venue_id = p_venue_id
      and staff.user_id = v_uid
      and staff.status = 'accepted'
  ) then
    return v_uid;
  end if;
  if not private.is_admin() then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return private.admin_require();
end;
$$;

revoke all on function private.room_time_require_manager(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_snapshot(p_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'group_name', entry.group_name,
    'elapsed_seconds', entry.elapsed_seconds,
    'duration_seconds', entry.duration_seconds,
    'escaped', entry.escaped,
    'removed_at', entry.removed_at,
    'members', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'user_id', member.user_id,
          'label', member.label,
          'published', member.published
        )
        order by member.sort_order
      )
      from public.room_time_members member
      where member.entry_id = entry.id
    ), '[]'::jsonb)
  )
  from public.room_time_entries entry
  where entry.id = p_entry_id;
$$;

revoke all on function private.room_time_snapshot(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_audit(
  p_entry_id uuid,
  p_venue_id uuid,
  p_actor uuid,
  p_action text,
  p_before jsonb,
  p_after jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.room_time_audit (
    entry_id, venue_id, actor_id, action, before_state, after_state
  ) values (
    p_entry_id, p_venue_id, p_actor, p_action, p_before, p_after
  );
  if private.is_admin() then
    perform private.admin_audit(
      p_actor,
      p_action,
      'room_time_entries',
      p_entry_id::text,
      p_before,
      p_after
    );
  end if;
end;
$$;

revoke all on function private.room_time_audit(uuid, uuid, uuid, text, jsonb, jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_reject_if_off()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.room_time_enabled() then
    raise exception 'O ranking de tempo está desligado.'
      using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.room_time_reject_if_off()
  from public, anon, authenticated, service_role;

create or replace function private.room_time_resolve_name(
  p_given text,
  p_stored text
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_raw text;
begin
  v_raw := nullif(pg_catalog.btrim(coalesce(p_given, '')), '');
  if v_raw is null then
    v_raw := nullif(pg_catalog.btrim(coalesce(p_stored, '')), '');
  end if;
  if v_raw is null then
    return 'Grupo';
  end if;
  return private.room_time_clean_name(v_raw);
end;
$$;

revoke all on function private.room_time_resolve_name(text, text)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_write_members(
  p_entry_id uuid,
  p_group_id uuid,
  p_members jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ready integer;
  v_item jsonb;
  v_user uuid;
  v_label text;
  v_order integer := 0;
  v_listed uuid[] := array[]::uuid[];
begin
  select count(*)::integer into v_ready
  from private.ranking_ready_players(p_group_id);

  if v_ready = 0 then
    if pg_catalog.to_regclass('public.session_checkins') is not null then
      raise exception 'Sem comparecimento confirmado pela casa.'
        using errcode = 'P0001';
    end if;
    raise exception 'Sem reserva paga nesta sessão.'
      using errcode = 'P0001';
  end if;

  delete from public.room_time_members where entry_id = p_entry_id;

  if p_members is null or p_members = 'null'::jsonb then
    insert into public.room_time_members (
      entry_id, user_id, label, sort_order, published
    )
    select p_entry_id, player.user_id, player.label, player.sort_order, true
    from private.ranking_ready_players(p_group_id) player;
    return;
  end if;

  if pg_catalog.jsonb_typeof(p_members) <> 'array' then
    raise exception 'Integrantes em formato inválido.'
      using errcode = '22023';
  end if;

  for v_item in
    select elem
    from pg_catalog.jsonb_array_elements(p_members) as elem
  loop
    begin
      v_user := (v_item ->> 'user_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Integrante inválido.'
          using errcode = '22023';
    end;
    if v_user is null or not v_user = any (
      select player.user_id from private.ranking_ready_players(p_group_id) player
    ) then
      raise exception 'Integrante fora da sessão.'
        using errcode = '22023';
    end if;
    if v_user = any (v_listed) then
      raise exception 'Integrante repetido.'
        using errcode = '22023';
    end if;
    v_listed := v_listed || v_user;
    if pg_catalog.btrim(coalesce(v_item ->> 'label', '')) <> '' then
      v_label := private.room_time_label(v_item ->> 'label', true);
    else
      select player.label into v_label
      from private.ranking_ready_players(p_group_id) player
      where player.user_id = v_user;
    end if;
    v_order := v_order + 1;
    insert into public.room_time_members (
      entry_id, user_id, label, sort_order, published
    ) values (
      p_entry_id, v_user, v_label, v_order, true
    );
  end loop;

  insert into public.room_time_members (
    entry_id, user_id, label, sort_order, published
  )
  select
    p_entry_id,
    player.user_id,
    player.label,
    100 + player.sort_order,
    false
  from private.ranking_ready_players(p_group_id) player
  where not player.user_id = any (v_listed);
end;
$$;

revoke all on function private.room_time_write_members(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;

create or replace function private.room_time_load_group(p_group_id uuid)
returns table (
  group_id uuid,
  venue_id uuid,
  room_id uuid,
  session_id uuid,
  starts_at timestamptz,
  cancelled_at timestamptz,
  team_name text,
  duration_minutes integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    g.id,
    g.venue_id,
    g.room_id,
    g.session_id,
    g.starts_at,
    g.cancelled_at,
    g.team_name,
    r.duration_minutes
  from public.groups g
  join public.rooms r on r.id = g.room_id
  where g.id = p_group_id;
$$;

revoke all on function private.room_time_load_group(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.room_time_ranking_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.room_time_enabled();
$$;

revoke all on function public.room_time_ranking_enabled()
  from public, anon, authenticated, service_role;
grant execute on function public.room_time_ranking_enabled()
  to anon, authenticated;

create or replace function public.record_room_time(
  p_group_id uuid,
  p_elapsed_seconds integer,
  p_escaped boolean,
  p_group_name text default null,
  p_members jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_group record;
  v_existing uuid;
  v_removed timestamptz;
  v_name text;
  v_duration integer;
  v_before jsonb;
begin
  perform private.room_time_reject_if_off();
  select * into v_group from private.room_time_load_group(p_group_id);
  if not found then
    raise exception 'grupo não encontrado' using errcode = 'P0002';
  end if;
  v_actor := private.room_time_require_manager(v_group.venue_id);
  if v_group.cancelled_at is not null then
    raise exception 'grupo cancelado' using errcode = 'P0001';
  end if;
  if v_group.starts_at > pg_catalog.now() then
    raise exception 'sessão ainda não começou' using errcode = 'P0001';
  end if;
  v_duration := v_group.duration_minutes * 60;
  if p_elapsed_seconds is null
    or p_elapsed_seconds < 1
    or p_elapsed_seconds > v_duration
    or p_escaped is null
  then
    raise exception 'O tempo fica entre 1 segundo e a duração da sala.'
      using errcode = '22023';
  end if;
  if nullif(pg_catalog.btrim(coalesce(v_group.team_name, '')), '') is not null then
    v_name := private.room_time_clean_name(v_group.team_name);
  else
    v_name := private.room_time_resolve_name(p_group_name, null);
  end if;

  select entry.id, entry.removed_at
    into v_existing, v_removed
  from public.room_time_entries entry
  where entry.group_id = p_group_id;

  if v_existing is not null and v_removed is null then
    raise exception 'Este grupo já tem tempo lançado. Edite a linha.'
      using errcode = 'P0001';
  end if;

  if v_existing is null then
    insert into public.room_time_entries (
      venue_id, room_id, group_id, group_name, elapsed_seconds,
      duration_seconds, escaped, played_at, recorded_by
    ) values (
      v_group.venue_id, v_group.room_id, p_group_id, v_name, p_elapsed_seconds,
      v_duration, p_escaped, v_group.starts_at, v_actor
    )
    returning id into v_existing;
    v_before := null;
  else
    v_before := private.room_time_snapshot(v_existing);
    update public.room_time_entries
      set group_name = v_name,
          elapsed_seconds = p_elapsed_seconds,
          duration_seconds = v_duration,
          escaped = p_escaped,
          updated_at = pg_catalog.now(),
          updated_by = v_actor,
          removed_at = null,
          removed_by = null
      where id = v_existing;
  end if;

  perform private.room_time_write_members(v_existing, p_group_id, p_members);

  perform private.room_time_audit(
    v_existing,
    v_group.venue_id,
    v_actor,
    'record',
    v_before,
    private.room_time_snapshot(v_existing)
  );
  return v_existing;
end;
$$;

revoke all on function public.record_room_time(uuid, integer, boolean, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_room_time(uuid, integer, boolean, text, jsonb)
  to authenticated;

create or replace function public.edit_room_time(
  p_entry_id uuid,
  p_elapsed_seconds integer,
  p_escaped boolean,
  p_group_name text default null,
  p_members jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_entry public.room_time_entries%rowtype;
  v_name text;
  v_chosen text;
  v_before jsonb;
begin
  perform private.room_time_reject_if_off();
  select * into v_entry
  from public.room_time_entries
  where id = p_entry_id;
  if not found then
    raise exception 'tempo não encontrado' using errcode = 'P0002';
  end if;
  v_actor := private.room_time_require_manager(v_entry.venue_id);
  if v_entry.removed_at is not null then
    raise exception 'Linha removida.' using errcode = 'P0001';
  end if;
  if p_elapsed_seconds is null
    or p_elapsed_seconds < 1
    or p_elapsed_seconds > v_entry.duration_seconds
    or p_escaped is null
  then
    raise exception 'O tempo fica entre 1 segundo e a duração da sala.'
      using errcode = '22023';
  end if;
  select chosen.team_name into v_chosen
  from public.groups chosen
  where chosen.id = v_entry.group_id;
  if nullif(pg_catalog.btrim(coalesce(v_chosen, '')), '') is not null then
    v_name := private.room_time_clean_name(v_chosen);
  elsif nullif(pg_catalog.btrim(coalesce(p_group_name, '')), '') is not null then
    v_name := private.room_time_clean_name(p_group_name);
  else
    v_name := v_entry.group_name;
  end if;
  v_before := private.room_time_snapshot(v_entry.id);
  update public.room_time_entries
    set group_name = v_name,
        elapsed_seconds = p_elapsed_seconds,
        escaped = p_escaped,
        updated_at = pg_catalog.now(),
        updated_by = v_actor
    where id = v_entry.id;
  perform private.room_time_write_members(v_entry.id, v_entry.group_id, p_members);
  perform private.room_time_audit(
    v_entry.id,
    v_entry.venue_id,
    v_actor,
    'edit',
    v_before,
    private.room_time_snapshot(v_entry.id)
  );
  return v_entry.id;
end;
$$;

revoke all on function public.edit_room_time(uuid, integer, boolean, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.edit_room_time(uuid, integer, boolean, text, jsonb)
  to authenticated;

create or replace function public.remove_room_time(p_entry_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_entry public.room_time_entries%rowtype;
  v_before jsonb;
begin
  perform private.room_time_reject_if_off();
  select * into v_entry
  from public.room_time_entries
  where id = p_entry_id;
  if not found then
    raise exception 'tempo não encontrado' using errcode = 'P0002';
  end if;
  v_actor := private.room_time_require_manager(v_entry.venue_id);
  if v_entry.removed_at is not null then
    raise exception 'Linha já removida.' using errcode = 'P0001';
  end if;
  v_before := private.room_time_snapshot(v_entry.id);
  update public.room_time_entries
    set removed_at = pg_catalog.now(),
        removed_by = v_actor,
        updated_at = pg_catalog.now(),
        updated_by = v_actor
    where id = v_entry.id;
  perform private.room_time_audit(
    v_entry.id,
    v_entry.venue_id,
    v_actor,
    'remove',
    v_before,
    private.room_time_snapshot(v_entry.id)
  );
end;
$$;

revoke all on function public.remove_room_time(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.remove_room_time(uuid)
  to authenticated;

create or replace function public.room_time_ranking(
  p_room_id uuid,
  p_limit integer default 10
)
returns table (
  rank_place integer,
  group_name text,
  elapsed_seconds integer,
  remaining_seconds integer,
  played_on date,
  members text[],
  medal text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_limit integer := least(greatest(coalesce(p_limit, 10), 1), 10);
begin
  if not private.room_time_enabled() then
    return;
  end if;
  return query
  with ranked as (
    select
      pg_catalog.row_number() over (
        order by entry.elapsed_seconds, entry.played_at, entry.id
      )::integer as rank_place,
      entry.group_name,
      entry.elapsed_seconds,
      (entry.duration_seconds - entry.elapsed_seconds)::integer as remaining_seconds,
      (entry.played_at at time zone 'America/Sao_Paulo')::date as played_on,
      case
        when coalesce(prefs.show_members, false) then coalesce((
          select pg_catalog.array_agg(member.label order by member.sort_order)
          from public.room_time_members member
          join public.profiles profile on profile.id = member.user_id
          where member.entry_id = entry.id
            and member.published
            and profile.show_in_room_ranking
        ), '{}'::text[])
        else '{}'::text[]
      end as members
    from public.room_time_entries entry
    join public.venues venue on venue.id = entry.venue_id
    left join public.venue_time_ranking prefs on prefs.venue_id = entry.venue_id
    where entry.room_id = p_room_id
      and entry.escaped
      and entry.removed_at is null
      and venue.status = 'approved'
      and venue.suspended_at is null
      and coalesce(prefs.show_public, true)
  )
  select
    ranked.rank_place,
    ranked.group_name,
    ranked.elapsed_seconds,
    ranked.remaining_seconds,
    ranked.played_on,
    ranked.members,
    case ranked.rank_place
      when 1 then 'ouro'
      when 2 then 'prata'
      when 3 then 'bronze'
      else null
    end
  from ranked
  where ranked.rank_place <= v_limit;
end;
$$;

comment on function public.room_time_ranking(uuid, integer) is
  'Top 10 público da sala, do menor tempo. Sem user id, e-mail ou nome completo. Flag, casa aprovada, preferência da casa e a escolha de cada jogador ligam a leitura.';

revoke all on function public.room_time_ranking(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.room_time_ranking(uuid, integer)
  to anon, authenticated;

create or replace function public.my_room_times()
returns table (
  entry_id uuid,
  room_id uuid,
  room_name text,
  venue_name text,
  group_name text,
  elapsed_seconds integer,
  remaining_seconds integer,
  escaped boolean,
  rank_place integer,
  played_on date,
  members text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.room_time_enabled() then
    return;
  end if;
  return query
  with ranked as (
    select
      entry.id,
      pg_catalog.row_number() over (
        partition by entry.room_id
        order by entry.elapsed_seconds, entry.played_at, entry.id
      )::integer as rank_place
    from public.room_time_entries entry
    join public.venues venue on venue.id = entry.venue_id
    where entry.escaped
      and entry.removed_at is null
      and venue.status = 'approved'
      and venue.suspended_at is null
  )
  select
    entry.id,
    entry.room_id,
    room.name,
    venue.name,
    entry.group_name,
    entry.elapsed_seconds,
    (entry.duration_seconds - entry.elapsed_seconds)::integer,
    entry.escaped,
    case when entry.escaped then ranked.rank_place else null end,
    (entry.played_at at time zone 'America/Sao_Paulo')::date,
    case
      when coalesce(prefs.show_members, false) then coalesce((
        select pg_catalog.array_agg(member.label order by member.sort_order)
        from public.room_time_members member
        where member.entry_id = entry.id
          and member.published
      ), '{}'::text[])
      else '{}'::text[]
    end
  from public.room_time_entries entry
  join public.room_time_members mine
    on mine.entry_id = entry.id
   and mine.user_id = v_uid
  join public.rooms room on room.id = entry.room_id
  join public.venues venue on venue.id = entry.venue_id
  left join ranked on ranked.id = entry.id
  left join public.venue_time_ranking prefs on prefs.venue_id = entry.venue_id
  where entry.removed_at is null
  order by entry.played_at desc, entry.id;
end;
$$;

comment on function public.my_room_times() is
  'Tempos da própria conta, inclusive quem não escapou. A posição só existe no ranking de casa aprovada e não suspensa.';

revoke all on function public.my_room_times()
  from public, anon, authenticated, service_role;
grant execute on function public.my_room_times() to authenticated;

create or replace function public.partner_room_times(p_room_id uuid)
returns table (
  entry_id uuid,
  group_id uuid,
  group_name text,
  elapsed_seconds integer,
  remaining_seconds integer,
  escaped boolean,
  rank_place integer,
  played_on date,
  members jsonb,
  recorded_at timestamptz,
  name_chosen boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_venue uuid;
begin
  if not private.room_time_enabled() then
    return;
  end if;
  select room.venue_id into v_venue
  from public.rooms room
  where room.id = p_room_id;
  if v_venue is null then
    raise exception 'sala não encontrada' using errcode = 'P0002';
  end if;
  perform private.room_time_require_manager(v_venue);
  return query
  with ranked as (
    select
      entry.id,
      pg_catalog.row_number() over (
        order by entry.elapsed_seconds, entry.played_at, entry.id
      )::integer as rank_place
    from public.room_time_entries entry
    join public.venues venue on venue.id = entry.venue_id
    where entry.room_id = p_room_id
      and entry.escaped
      and entry.removed_at is null
      and venue.status = 'approved'
      and venue.suspended_at is null
  )
  select
    entry.id,
    entry.group_id,
    entry.group_name,
    entry.elapsed_seconds,
    (entry.duration_seconds - entry.elapsed_seconds)::integer,
    entry.escaped,
    case when entry.escaped then ranked.rank_place else null end,
    (entry.played_at at time zone 'America/Sao_Paulo')::date,
    coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'user_id', member.user_id,
          'label', member.label,
          'published', member.published
        )
        order by member.sort_order
      )
      from public.room_time_members member
      where member.entry_id = entry.id
    ), '[]'::jsonb),
    entry.created_at,
    exists (
      select 1
      from public.groups chosen
      where chosen.id = entry.group_id
        and nullif(pg_catalog.btrim(coalesce(chosen.team_name, '')), '') is not null
    )
  from public.room_time_entries entry
  left join ranked on ranked.id = entry.id
  where entry.room_id = p_room_id
    and entry.removed_at is null
  order by entry.escaped desc, entry.elapsed_seconds, entry.played_at, entry.id;
end;
$$;

comment on function public.partner_room_times(uuid) is
  'Ranking completo da casa, com quem não escapou. A posição pública ignora casa suspensa ou não aprovada.';

revoke all on function public.partner_room_times(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.partner_room_times(uuid) to authenticated;

create or replace function public.set_group_team_name(
  p_group_id uuid,
  p_name text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group record;
  v_name text;
begin
  perform private.room_time_reject_if_off();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from private.room_time_load_group(p_group_id);
  if not found then
    raise exception 'grupo não encontrado' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'grupo cancelado' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.group_members member
    where member.group_id = p_group_id
      and member.user_id = v_uid
      and member.payment_status = 'paid'
      and member.attendance <> 'cancelled'
      and member.refund_status is distinct from 'refunded'
  ) then
    raise exception 'Só quem pagou e está na sessão pode escolher o nome.'
      using errcode = 'P0001';
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    v_name := null;
  else
    v_name := private.room_time_clean_name(p_name);
  end if;
  update public.groups
    set team_name = v_name
    where id = p_group_id;
  update public.room_time_entries
    set group_name = coalesce(v_name, 'Grupo'),
        updated_at = pg_catalog.now(),
        updated_by = v_uid
    where group_id = p_group_id
      and removed_at is null;
  return coalesce(v_name, 'Grupo');
end;
$$;

revoke all on function public.set_group_team_name(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_group_team_name(uuid, text)
  to authenticated;

create or replace function public.correct_group_team_name(
  p_group_id uuid,
  p_name text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_group record;
  v_name text;
  v_entry uuid;
  v_before jsonb;
begin
  perform private.room_time_reject_if_off();
  select * into v_group from private.room_time_load_group(p_group_id);
  if not found then
    raise exception 'grupo não encontrado' using errcode = 'P0002';
  end if;
  v_actor := private.room_time_require_manager(v_group.venue_id);
  v_name := private.room_time_clean_name(p_name);
  update public.groups
    set team_name = v_name
    where id = p_group_id;
  select entry.id into v_entry
  from public.room_time_entries entry
  where entry.group_id = p_group_id
    and entry.removed_at is null;
  if v_entry is not null then
    v_before := private.room_time_snapshot(v_entry);
    update public.room_time_entries
      set group_name = v_name,
          updated_at = pg_catalog.now(),
          updated_by = v_actor
      where id = v_entry;
    perform private.room_time_audit(
      v_entry,
      v_group.venue_id,
      v_actor,
      'correct_name',
      v_before,
      private.room_time_snapshot(v_entry)
    );
  end if;
  return v_name;
end;
$$;

comment on function public.correct_group_team_name(uuid, text) is
  'A casa corrige o nome do grupo de propósito. Lançar ou editar o tempo não faz isso.';

revoke all on function public.correct_group_team_name(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.correct_group_team_name(uuid, text)
  to authenticated;

create or replace function public.group_chosen_team_name(p_group_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group record;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.room_time_enabled() then
    return null;
  end if;
  select * into v_group from private.room_time_load_group(p_group_id);
  if not found then
    raise exception 'grupo não encontrado' using errcode = 'P0002';
  end if;
  if not (
    private.owns_venue(v_group.venue_id)
    or exists (
      select 1
      from public.venue_staff staff
      where staff.venue_id = v_group.venue_id
        and staff.user_id = v_uid
        and staff.status = 'accepted'
    )
    or private.is_admin_aal2()
  ) then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return nullif(pg_catalog.btrim(coalesce(v_group.team_name, '')), '');
end;
$$;

revoke all on function public.group_chosen_team_name(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.group_chosen_team_name(uuid) to authenticated;

create or replace function public.my_room_time_visibility()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select profile.show_in_room_ranking
      from public.profiles profile
      where profile.id = auth.uid()
    ),
    true
  );
$$;

revoke all on function public.my_room_time_visibility()
  from public, anon, authenticated, service_role;
grant execute on function public.my_room_time_visibility() to authenticated;

create or replace function public.set_my_room_time_visibility(p_show boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  perform private.room_time_reject_if_off();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_show is null then
    raise exception 'Preferência incompleta.' using errcode = '22023';
  end if;
  update public.profiles
    set show_in_room_ranking = p_show
    where id = v_uid;
  if not found then
    raise exception 'perfil não encontrado' using errcode = 'P0002';
  end if;
  return p_show;
end;
$$;

comment on function public.set_my_room_time_visibility(boolean) is
  'O jogador escolhe se o primeiro nome aparece no ranking público. O padrão é aparecer.';

revoke all on function public.set_my_room_time_visibility(boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_my_room_time_visibility(boolean)
  to authenticated;

create or replace function public.group_team_name(p_group_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group record;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.room_time_enabled() then
    return null;
  end if;
  select * into v_group from private.room_time_load_group(p_group_id);
  if not found then
    raise exception 'grupo não encontrado' using errcode = 'P0002';
  end if;
  if not (
    exists (
      select 1
      from public.group_members member
      where member.group_id = p_group_id
        and member.user_id = v_uid
        and member.attendance <> 'cancelled'
    )
    or private.owns_venue(v_group.venue_id)
    or exists (
      select 1
      from public.venue_staff staff
      where staff.venue_id = v_group.venue_id
        and staff.user_id = v_uid
        and staff.status = 'accepted'
    )
    or private.is_admin_aal2()
  ) then
    raise exception 'sem permissão' using errcode = '42501';
  end if;
  return coalesce(v_group.team_name, 'Grupo');
end;
$$;

revoke all on function public.group_team_name(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.group_team_name(uuid) to authenticated;

create or replace function public.venue_time_ranking(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_public boolean;
  v_members boolean;
begin
  perform private.room_time_require_manager(p_venue_id);
  if not private.room_time_enabled() then
    return pg_catalog.jsonb_build_object(
      'enabled', false,
      'show_public', true,
      'show_members', false
    );
  end if;
  select prefs.show_public, prefs.show_members
    into v_public, v_members
  from public.venue_time_ranking prefs
  where prefs.venue_id = p_venue_id;
  return pg_catalog.jsonb_build_object(
    'enabled', true,
    'show_public', coalesce(v_public, true),
    'show_members', coalesce(v_members, false)
  );
end;
$$;

revoke all on function public.venue_time_ranking(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.venue_time_ranking(uuid) to authenticated;

create or replace function public.set_venue_time_ranking(
  p_venue_id uuid,
  p_show_public boolean,
  p_show_members boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  perform private.room_time_reject_if_off();
  if p_show_public is null or p_show_members is null then
    raise exception 'Preferência incompleta.' using errcode = '22023';
  end if;
  v_actor := private.room_time_require_manager(p_venue_id);
  insert into public.venue_time_ranking (
    venue_id, show_public, show_members, updated_at, updated_by
  ) values (
    p_venue_id, p_show_public, p_show_members, pg_catalog.now(), v_actor
  )
  on conflict (venue_id) do update
    set show_public = excluded.show_public,
        show_members = excluded.show_members,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;
  return public.venue_time_ranking(p_venue_id);
end;
$$;

revoke all on function public.set_venue_time_ranking(uuid, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_venue_time_ranking(uuid, boolean, boolean)
  to authenticated;

create or replace function public.admin_room_time_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return (
    select pg_catalog.jsonb_build_object(
      'enabled', settings.enabled,
      'updated_at', settings.updated_at
    )
    from public.room_time_settings settings
    where settings.id = 1
  );
end;
$$;

revoke all on function public.admin_room_time_settings()
  from public, anon, authenticated, service_role;
grant execute on function public.admin_room_time_settings() to authenticated;

create or replace function public.admin_save_room_time_settings(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_before boolean;
begin
  if p_enabled is null then
    raise exception 'Flag incompleta.' using errcode = '22023';
  end if;
  v_actor := private.admin_require();
  select settings.enabled into v_before
  from public.room_time_settings settings
  where settings.id = 1;
  update public.room_time_settings
    set enabled = p_enabled,
        updated_at = pg_catalog.now(),
        updated_by = v_actor
    where id = 1;
  perform private.admin_audit(
    v_actor,
    'save',
    'room_time_settings',
    '1',
    pg_catalog.jsonb_build_object('enabled', v_before),
    pg_catalog.jsonb_build_object('enabled', p_enabled)
  );
  return public.admin_room_time_settings();
end;
$$;

revoke all on function public.admin_save_room_time_settings(boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_save_room_time_settings(boolean)
  to authenticated;

create or replace function public.admin_room_time_recent()
returns table (
  entry_id uuid,
  venue_name text,
  room_name text,
  group_name text,
  elapsed_seconds integer,
  escaped boolean,
  removed boolean,
  played_on date
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.admin_require();
  return query
  select
    entry.id,
    venue.name,
    room.name,
    entry.group_name,
    entry.elapsed_seconds,
    entry.escaped,
    entry.removed_at is not null,
    (entry.played_at at time zone 'America/Sao_Paulo')::date
  from public.room_time_entries entry
  join public.venues venue on venue.id = entry.venue_id
  join public.rooms room on room.id = entry.room_id
  order by entry.created_at desc
  limit 40;
end;
$$;

revoke all on function public.admin_room_time_recent()
  from public, anon, authenticated, service_role;
grant execute on function public.admin_room_time_recent() to authenticated;

create or replace function public.admin_room_time_audit(p_entry_id uuid)
returns table (
  action text,
  actor_id uuid,
  created_at timestamptz,
  before_state jsonb,
  after_state jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform private.admin_require();
  return query
  select
    audit.action,
    audit.actor_id,
    audit.created_at,
    audit.before_state,
    audit.after_state
  from public.room_time_audit audit
  where audit.entry_id = p_entry_id
  order by audit.created_at;
end;
$$;

revoke all on function public.admin_room_time_audit(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_room_time_audit(uuid) to authenticated;
