-- Avaliações de sala. A flag nasce desligada.
-- Não aplicar no projeto remoto neste PR: o Admin liga depois.
--
-- Escrita só por RPC. A função confere reserva paga e concluída,
-- uma avaliação por jogador por sessão, e recusa dono, sócio, staff
-- e a mesma identidade (CPF, telefone ou cartão) da casa.
-- Leitura pública: agregados e comentários não ocultos, e só com a flag ligada.
-- Admin passa por private.admin_require(), que exige is_admin_aal2().

alter table public.cities
  add column country_code text not null default 'BR',
  add column country_name text not null default 'Brasil';

alter table public.cities
  drop constraint if exists cities_country_code_format;

alter table public.cities
  add constraint cities_country_code_format
  check (country_code ~ '^[A-Z]{2}$');

alter table public.cities
  drop constraint if exists cities_country_name_present;

alter table public.cities
  add constraint cities_country_name_present
  check (char_length(country_name) between 2 and 80);

comment on column public.cities.country_code is
  'ISO 3166-1 alpha-2. As cidades já cadastradas ficam no Brasil.';

comment on column public.cities.country_name is
  'Nome do país no ranking. O padrão das cidades atuais é Brasil.';

create table public.review_settings (
  id integer primary key default 1 check (id = 1),
  enabled boolean not null default false,
  bayesian_m integer not null default 10 check (bayesian_m between 1 and 1000),
  ranking_min integer not null default 10 check (ranking_min between 1 and 10000),
  updated_at timestamptz,
  updated_by uuid references auth.users (id)
);

insert into public.review_settings (id, enabled, bayesian_m, ranking_min)
values (1, false, 10, 10);

comment on table public.review_settings is
  'Flag das avaliações. enabled nasce falso. bayesian_m é o peso do prior e ranking_min é o mínimo para ranking e JSON-LD.';

create table public.venue_staff (
  venue_id uuid not null references public.venues (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('partner', 'staff')),
  created_at timestamptz not null default pg_catalog.now(),
  primary key (venue_id, user_id)
);

comment on table public.venue_staff is
  'Sócio (partner) e equipe (staff). O dono continua em venues.owner_id. Nenhum dos três avalia a própria casa.';

create index venue_staff_by_user on public.venue_staff (user_id);

create table public.room_reviews (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  room_id uuid not null references public.rooms (id),
  venue_id uuid not null references public.venues (id),
  city_id text not null references public.cities (id),
  author_id uuid not null references auth.users (id),
  story smallint not null check (story between 1 and 5),
  puzzles smallint not null check (puzzles between 1 and 5),
  immersion smallint not null check (immersion between 1 and 5),
  service smallint not null check (service between 1 and 5),
  comfort smallint not null check (comfort between 1 and 5),
  value smallint not null check (value between 1 and 5),
  overall numeric(6, 4) generated always as (
    (story + puzzles + immersion + service + comfort + value)::numeric / 6
  ) stored,
  comment text not null default '' check (char_length(comment) <= 280),
  hidden_at timestamptz,
  hidden_reason text not null default '' check (char_length(hidden_reason) <= 280),
  hidden_by uuid references auth.users (id),
  created_at timestamptz not null default pg_catalog.now(),
  unique (group_id, author_id),
  check (
    (
      hidden_at is null
      and hidden_by is null
      and hidden_reason = ''
    )
    or (
      hidden_at is not null
      and hidden_by is not null
      and char_length(hidden_reason) between 1 and 280
    )
  )
);

comment on table public.room_reviews is
  'Uma avaliação por jogador por sessão. A nota geral é a média das seis categorias. Ocultar exige motivo.';

create index room_reviews_visible_by_room
  on public.room_reviews (room_id)
  where hidden_at is null;

create index room_reviews_by_venue on public.room_reviews (venue_id);

create table public.review_replies (
  review_id uuid primary key references public.room_reviews (id) on delete cascade,
  venue_id uuid not null references public.venues (id),
  author_id uuid not null references auth.users (id),
  body text not null check (char_length(body) between 1 and 280),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

comment on table public.review_replies is
  'Resposta da casa a um comentário. Uma por avaliação.';

create table public.review_reports (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.room_reviews (id) on delete cascade,
  reporter_id uuid not null references auth.users (id),
  reason text not null check (char_length(reason) between 1 and 280),
  created_at timestamptz not null default pg_catalog.now(),
  unique (review_id, reporter_id)
);

comment on table public.review_reports is
  'Denúncia de um comentário. Uma por pessoa. Não guarda a nota por categoria.';

create table public.review_moderation_events (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.room_reviews (id) on delete cascade,
  actor_id uuid not null references auth.users (id),
  action text not null check (action in ('hide', 'unhide')),
  reason text not null check (char_length(reason) between 1 and 280),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.review_moderation_events is
  'Auditoria de ocultar e reexibir. O motivo fica aqui e também em admin_audit_log.';

create index review_moderation_by_time
  on public.review_moderation_events (created_at desc);

create table public.room_rating_rollups (
  room_id uuid primary key references public.rooms (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  city_id text not null references public.cities (id),
  country_code text not null,
  review_count integer not null check (review_count > 0),
  sum_story integer not null,
  sum_puzzles integer not null,
  sum_immersion integer not null,
  sum_service integer not null,
  sum_comfort integer not null,
  sum_value integer not null,
  sum_overall numeric not null,
  dist_1 integer not null,
  dist_2 integer not null,
  dist_3 integer not null,
  dist_4 integer not null,
  dist_5 integer not null,
  monthly jsonb not null,
  updated_at timestamptz not null default pg_catalog.now()
);

comment on table public.room_rating_rollups is
  'Agregado da sala, sem identidade. O Parceiro escuta esta tabela para atualizar o painel. Some quando a flag está desligada.';

create index room_rating_rollups_by_venue
  on public.room_rating_rollups (venue_id);

create index room_rating_rollups_by_city
  on public.room_rating_rollups (city_id);

create index room_rating_rollups_by_country
  on public.room_rating_rollups (country_code);

alter table public.review_settings enable row level security;
alter table public.venue_staff enable row level security;
alter table public.room_reviews enable row level security;
alter table public.review_replies enable row level security;
alter table public.review_reports enable row level security;
alter table public.review_moderation_events enable row level security;
alter table public.room_rating_rollups enable row level security;

revoke all on table public.review_settings from public, anon, authenticated, service_role;
revoke all on table public.venue_staff from public, anon, authenticated, service_role;
revoke all on table public.room_reviews from public, anon, authenticated, service_role;
revoke all on table public.review_replies from public, anon, authenticated, service_role;
revoke all on table public.review_reports from public, anon, authenticated, service_role;
revoke all on table public.review_moderation_events from public, anon, authenticated, service_role;
revoke all on table public.room_rating_rollups from public, anon, authenticated, service_role;

grant select on table public.room_rating_rollups to anon, authenticated;

create or replace function private.reviews_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select enabled from public.review_settings where id = 1),
    false
  );
$$;

comment on function private.reviews_enabled() is
  'A flag. A policy do agregado chama esta função para não ler review_settings direto.';

revoke all on function private.reviews_enabled() from public, anon, authenticated, service_role;
grant execute on function private.reviews_enabled() to anon, authenticated, service_role;

create policy room_rating_rollups_read
  on public.room_rating_rollups
  for select
  to anon, authenticated
  using ((select private.reviews_enabled()));

create or replace function private.review_message(p_reason text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_reason
    when 'not_paid' then 'Só avalia quem pagou esta sessão.'
    when 'not_finished' then 'A avaliação abre quando a sessão termina.'
    when 'cancelled' then 'Sessão cancelada não recebe avaliação.'
    when 'refunded' then 'Reserva estornada não recebe avaliação.'
    when 'not_member' then 'Você não jogou esta sessão.'
    when 'already_reviewed' then 'Você já avaliou esta sessão.'
    when 'house_insider' then 'Quem é da casa não avalia a própria casa.'
    when 'shared_cpf' then 'Esta conta não pode avaliar esta casa.'
    when 'shared_phone' then 'Esta conta não pode avaliar esta casa.'
    when 'shared_card' then 'Esta conta não pode avaliar esta casa.'
    when 'player_owns_venue' then 'Esta conta não pode avaliar esta casa.'
    when 'shared_document' then 'Esta conta não pode avaliar esta casa.'
    else 'Não foi possível avaliar.'
  end;
$$;

revoke all on function private.review_message(text)
  from public, anon, authenticated, service_role;

create or replace function private.review_shares_card(
  p_user uuid,
  p_others uuid[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.saved_cards mine
    join public.saved_cards theirs
      on extensions.pgp_sym_decrypt(
        mine.credit_card_token,
        private.card_token_key()
      ) = extensions.pgp_sym_decrypt(
        theirs.credit_card_token,
        private.card_token_key()
      )
      or (
        lower(mine.brand) = lower(theirs.brand)
        and mine.last4 = theirs.last4
      )
    where mine.user_id = p_user
      and theirs.user_id = any (p_others)
      and theirs.user_id is distinct from p_user
  );
$$;

comment on function private.review_shares_card(uuid, uuid[]) is
  'O mesmo token, já decifrado, ou a mesma chave bandeira + 4 finais usada na antifraude.';

revoke all on function private.review_shares_card(uuid, uuid[])
  from public, anon, authenticated, service_role;

create or replace function private.review_block_reason(
  p_group_id uuid,
  p_user uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cancelled timestamptz;
  v_starts timestamptz;
  v_duration integer;
  v_venue uuid;
  v_owner uuid;
  v_payment text;
  v_refund text;
  v_attendance text;
  v_other uuid;
  v_staff uuid;
  v_conflict text;
  v_related uuid[] := array[]::uuid[];
begin
  select g.cancelled_at, g.starts_at, r.duration_minutes, r.venue_id, v.owner_id
    into v_cancelled, v_starts, v_duration, v_venue, v_owner
  from public.groups g
  join public.rooms r on r.id = g.room_id
  join public.venues v on v.id = r.venue_id
  where g.id = p_group_id;

  if v_venue is null then
    return 'not_member';
  end if;
  if v_cancelled is not null then
    return 'cancelled';
  end if;

  select m.payment_status, m.refund_status, m.attendance
    into v_payment, v_refund, v_attendance
  from public.group_members m
  where m.group_id = p_group_id
    and m.user_id = p_user;

  if v_payment is null or v_attendance = 'cancelled' then
    return 'not_member';
  end if;
  if v_refund = 'refunded' then
    return 'refunded';
  end if;
  if v_payment is distinct from 'paid' then
    return 'not_paid';
  end if;
  if v_starts + pg_catalog.make_interval(mins => v_duration) > pg_catalog.now() then
    return 'not_finished';
  end if;
  if exists (
    select 1
    from public.room_reviews review
    where review.group_id = p_group_id
      and review.author_id = p_user
  ) then
    return 'already_reviewed';
  end if;
  if v_owner = p_user or exists (
    select 1
    from public.venue_staff staff
    where staff.venue_id = v_venue
      and staff.user_id = p_user
  ) then
    return 'house_insider';
  end if;

  v_related := array_append(v_related, v_owner);
  v_conflict := private.identity_conflict(p_user, v_owner, v_venue, null);
  if v_conflict is not null then
    return v_conflict;
  end if;

  for v_staff in
    select staff.user_id
    from public.venue_staff staff
    where staff.venue_id = v_venue
      and staff.user_id is distinct from p_user
  loop
    v_related := array_append(v_related, v_staff);
    v_conflict := private.identity_conflict(p_user, v_staff, null, null);
    if v_conflict is not null then
      return v_conflict;
    end if;
  end loop;

  for v_other in
    select review.author_id
    from public.room_reviews review
    where review.group_id = p_group_id
      and review.author_id is distinct from p_user
  loop
    v_related := array_append(v_related, v_other);
    v_conflict := private.identity_conflict(p_user, v_other, null, null);
    if v_conflict is not null then
      return v_conflict;
    end if;
  end loop;

  if coalesce(pg_catalog.array_length(v_related, 1), 0) > 0
    and private.review_shares_card(p_user, v_related)
  then
    return 'shared_card';
  end if;
  return null;
end;
$$;

revoke all on function private.review_block_reason(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function private.rebuild_room_rollup(p_room uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
  v_city text;
  v_country text;
  v_count integer;
begin
  select r.venue_id, v.city_id, c.country_code
    into v_venue, v_city, v_country
  from public.rooms r
  join public.venues v on v.id = r.venue_id
  join public.cities c on c.id = v.city_id
  where r.id = p_room;

  if v_venue is null then
    delete from public.room_rating_rollups where room_id = p_room;
    return;
  end if;

  select count(*)::integer
    into v_count
  from public.room_reviews review
  where review.room_id = p_room
    and review.hidden_at is null;

  if v_count = 0 then
    delete from public.room_rating_rollups where room_id = p_room;
    return;
  end if;

  insert into public.room_rating_rollups (
    room_id, venue_id, city_id, country_code, review_count,
    sum_story, sum_puzzles, sum_immersion, sum_service, sum_comfort, sum_value,
    sum_overall, dist_1, dist_2, dist_3, dist_4, dist_5, monthly, updated_at
  )
  select
    p_room,
    v_venue,
    v_city,
    v_country,
    count(*)::integer,
    sum(review.story)::integer,
    sum(review.puzzles)::integer,
    sum(review.immersion)::integer,
    sum(review.service)::integer,
    sum(review.comfort)::integer,
    sum(review.value)::integer,
    sum(review.overall),
    count(*) filter (where pg_catalog.round(review.overall) = 1)::integer,
    count(*) filter (where pg_catalog.round(review.overall) = 2)::integer,
    count(*) filter (where pg_catalog.round(review.overall) = 3)::integer,
    count(*) filter (where pg_catalog.round(review.overall) = 4)::integer,
    count(*) filter (where pg_catalog.round(review.overall) = 5)::integer,
    (
      select coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'month', months.month_key,
            'count', months.month_count,
            'sum', months.month_sum
          )
          order by months.month_key
        ),
        '[]'::jsonb
      )
      from (
        select
          pg_catalog.to_char(item.created_at at time zone 'UTC', 'YYYY-MM') as month_key,
          count(*)::integer as month_count,
          sum(item.overall) as month_sum
        from public.room_reviews item
        where item.room_id = p_room
          and item.hidden_at is null
        group by 1
      ) months
    ),
    pg_catalog.now()
  from public.room_reviews review
  where review.room_id = p_room
    and review.hidden_at is null
  on conflict (room_id) do update
  set
    venue_id = excluded.venue_id,
    city_id = excluded.city_id,
    country_code = excluded.country_code,
    review_count = excluded.review_count,
    sum_story = excluded.sum_story,
    sum_puzzles = excluded.sum_puzzles,
    sum_immersion = excluded.sum_immersion,
    sum_service = excluded.sum_service,
    sum_comfort = excluded.sum_comfort,
    sum_value = excluded.sum_value,
    sum_overall = excluded.sum_overall,
    dist_1 = excluded.dist_1,
    dist_2 = excluded.dist_2,
    dist_3 = excluded.dist_3,
    dist_4 = excluded.dist_4,
    dist_5 = excluded.dist_5,
    monthly = excluded.monthly,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on function private.rebuild_room_rollup(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.room_reviews_rollup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.rebuild_room_rollup(coalesce(new.room_id, old.room_id));
  if tg_op = 'UPDATE' and old.room_id is distinct from new.room_id then
    perform private.rebuild_room_rollup(old.room_id);
  end if;
  return null;
end;
$$;

revoke all on function private.room_reviews_rollup()
  from public, anon, authenticated, service_role;

drop trigger if exists room_reviews_rollup on public.room_reviews;
create trigger room_reviews_rollup
  after insert or update or delete on public.room_reviews
  for each row execute function private.room_reviews_rollup();

create or replace function public.reviews_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.reviews_enabled();
$$;

revoke all on function public.reviews_enabled()
  from public, anon, authenticated, service_role;
grant execute on function public.reviews_enabled() to anon, authenticated;

create or replace function public.submit_room_review(
  p_group_id uuid,
  p_story integer,
  p_puzzles integer,
  p_immersion integer,
  p_service integer,
  p_comfort integer,
  p_value integer,
  p_comment text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_reason text;
  v_comment text;
  v_room uuid;
  v_venue uuid;
  v_city text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.reviews_enabled() then
    raise exception 'As avaliações estão desligadas.' using errcode = '22023';
  end if;
  if p_story not between 1 and 5
    or p_puzzles not between 1 and 5
    or p_immersion not between 1 and 5
    or p_service not between 1 and 5
    or p_comfort not between 1 and 5
    or p_value not between 1 and 5
  then
    raise exception 'Cada nota vai de 1 a 5.' using errcode = '22023';
  end if;
  v_comment := pg_catalog.btrim(coalesce(p_comment, ''));
  if pg_catalog.char_length(v_comment) > 280 then
    raise exception 'O comentário passa de 280 caracteres.' using errcode = '22023';
  end if;

  v_reason := private.review_block_reason(p_group_id, v_user);
  if v_reason is not null then
    raise exception '%', private.review_message(v_reason)
      using errcode = 'P0001';
  end if;

  select r.id, r.venue_id, v.city_id
    into v_room, v_venue, v_city
  from public.groups g
  join public.rooms r on r.id = g.room_id
  join public.venues v on v.id = r.venue_id
  where g.id = p_group_id;

  insert into public.room_reviews (
    group_id, room_id, venue_id, city_id, author_id,
    story, puzzles, immersion, service, comfort, value, comment
  ) values (
    p_group_id, v_room, v_venue, v_city, v_user,
    p_story, p_puzzles, p_immersion, p_service, p_comfort, p_value, v_comment
  )
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Você já avaliou esta sessão.' using errcode = '23505';
end;
$$;

revoke all on function public.submit_room_review(uuid, integer, integer, integer, integer, integer, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_room_review(uuid, integer, integer, integer, integer, integer, integer, text)
  to authenticated;

create or replace function public.reply_room_review(
  p_review_id uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_venue uuid;
  v_hidden timestamptz;
  v_comment text;
  v_body text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.reviews_enabled() then
    raise exception 'As avaliações estão desligadas.' using errcode = '22023';
  end if;
  v_body := pg_catalog.btrim(coalesce(p_body, ''));
  if pg_catalog.char_length(v_body) < 1 or pg_catalog.char_length(v_body) > 280 then
    raise exception 'A resposta fica entre 1 e 280 caracteres.' using errcode = '22023';
  end if;

  select review.venue_id, review.hidden_at, review.comment
    into v_venue, v_hidden, v_comment
  from public.room_reviews review
  where review.id = p_review_id;

  if v_venue is null or v_hidden is not null or v_comment = '' then
    raise exception 'Comentário indisponível.' using errcode = 'P0002';
  end if;
  if not (
    private.owns_venue(v_venue)
    or exists (
      select 1
      from public.venue_staff staff
      where staff.venue_id = v_venue
        and staff.user_id = v_user
    )
  ) then
    raise exception 'not owner' using errcode = '42501';
  end if;

  insert into public.review_replies (review_id, venue_id, author_id, body)
  values (p_review_id, v_venue, v_user, v_body)
  on conflict (review_id) do update
  set body = excluded.body,
      author_id = excluded.author_id,
      updated_at = pg_catalog.now();
end;
$$;

revoke all on function public.reply_room_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.reply_room_review(uuid, text) to authenticated;

create or replace function public.report_room_review(
  p_review_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_reason text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.reviews_enabled() then
    raise exception 'As avaliações estão desligadas.' using errcode = '22023';
  end if;
  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(v_reason) < 1 or pg_catalog.char_length(v_reason) > 280 then
    raise exception 'A denúncia fica entre 1 e 280 caracteres.' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.room_reviews review
    where review.id = p_review_id
      and review.hidden_at is null
      and review.comment <> ''
  ) then
    raise exception 'Comentário indisponível.' using errcode = 'P0002';
  end if;

  insert into public.review_reports (review_id, reporter_id, reason)
  values (p_review_id, v_user, v_reason)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Você já denunciou este comentário.' using errcode = '23505';
end;
$$;

revoke all on function public.report_room_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.report_room_review(uuid, text) to authenticated;

create or replace function public.room_review_comments(p_room_id uuid)
returns table (
  id uuid,
  first_name text,
  comment text,
  overall numeric,
  created_at timestamptz,
  reply text,
  reply_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    review.id,
    pg_catalog.split_part(profile.display_name, ' ', 1),
    review.comment,
    review.overall,
    review.created_at,
    reply.body,
    reply.created_at
  from public.room_reviews review
  join public.profiles profile on profile.id = review.author_id
  left join public.review_replies reply on reply.review_id = review.id
  where private.reviews_enabled()
    and review.room_id = p_room_id
    and review.hidden_at is null
    and review.comment <> ''
  order by review.created_at desc;
$$;

comment on function public.room_review_comments(uuid) is
  'Comentário visível com o primeiro nome e a nota geral. Sem nota por categoria e sem o id de quem avaliou.';

revoke all on function public.room_review_comments(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.room_review_comments(uuid) to anon, authenticated;

create or replace function public.room_rating(p_room_id uuid)
returns table (
  review_count integer,
  overall numeric,
  story numeric,
  puzzles numeric,
  immersion numeric,
  service numeric,
  comfort numeric,
  value numeric,
  publish boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    rollup.review_count,
    rollup.sum_overall / rollup.review_count,
    rollup.sum_story::numeric / rollup.review_count,
    rollup.sum_puzzles::numeric / rollup.review_count,
    rollup.sum_immersion::numeric / rollup.review_count,
    rollup.sum_service::numeric / rollup.review_count,
    rollup.sum_comfort::numeric / rollup.review_count,
    rollup.sum_value::numeric / rollup.review_count,
    rollup.review_count >= settings.ranking_min
  from public.room_rating_rollups rollup
  cross join public.review_settings settings
  where settings.id = 1
    and settings.enabled
    and rollup.room_id = p_room_id;
$$;

revoke all on function public.room_rating(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.room_rating(uuid) to anon, authenticated;

create or replace function public.venue_rating(p_venue_id uuid)
returns table (
  review_count integer,
  overall numeric,
  story numeric,
  puzzles numeric,
  immersion numeric,
  service numeric,
  comfort numeric,
  value numeric,
  publish boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    sum(rollup.review_count)::integer,
    sum(rollup.sum_overall) / sum(rollup.review_count),
    sum(rollup.sum_story)::numeric / sum(rollup.review_count),
    sum(rollup.sum_puzzles)::numeric / sum(rollup.review_count),
    sum(rollup.sum_immersion)::numeric / sum(rollup.review_count),
    sum(rollup.sum_service)::numeric / sum(rollup.review_count),
    sum(rollup.sum_comfort)::numeric / sum(rollup.review_count),
    sum(rollup.sum_value)::numeric / sum(rollup.review_count),
    sum(rollup.review_count) >= min(settings.ranking_min)
  from public.room_rating_rollups rollup
  cross join public.review_settings settings
  where settings.id = 1
    and settings.enabled
    and rollup.venue_id = p_venue_id
  group by settings.ranking_min;
$$;

comment on function public.venue_rating(uuid) is
  'Nota da casa: média das salas ponderada pela quantidade de avaliações de cada uma.';

revoke all on function public.venue_rating(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.venue_rating(uuid) to anon, authenticated;

create or replace function public.venue_review_insights(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_city text;
  v_count integer;
  v_overall numeric;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.reviews_enabled() then
    return jsonb_build_object('enabled', false);
  end if;
  if not (
    private.owns_venue(p_venue_id)
    or exists (
      select 1
      from public.venue_staff staff
      where staff.venue_id = p_venue_id
        and staff.user_id = v_user
    )
  ) then
    raise exception 'not owner' using errcode = '42501';
  end if;

  select v.city_id into v_city from public.venues v where v.id = p_venue_id;
  select coalesce(sum(rollup.review_count), 0)::integer,
         case
           when coalesce(sum(rollup.review_count), 0) = 0 then null
           else sum(rollup.sum_overall) / sum(rollup.review_count)
         end
    into v_count, v_overall
  from public.room_rating_rollups rollup
  where rollup.venue_id = p_venue_id;

  return pg_catalog.jsonb_build_object(
    'enabled', true,
    'review_count', v_count,
    'overall', v_overall,
    'categories', (
      select pg_catalog.jsonb_build_object(
        'story', sum(rollup.sum_story)::numeric / nullif(sum(rollup.review_count), 0),
        'puzzles', sum(rollup.sum_puzzles)::numeric / nullif(sum(rollup.review_count), 0),
        'immersion', sum(rollup.sum_immersion)::numeric / nullif(sum(rollup.review_count), 0),
        'service', sum(rollup.sum_service)::numeric / nullif(sum(rollup.review_count), 0),
        'comfort', sum(rollup.sum_comfort)::numeric / nullif(sum(rollup.review_count), 0),
        'value', sum(rollup.sum_value)::numeric / nullif(sum(rollup.review_count), 0)
      )
      from public.room_rating_rollups rollup
      where rollup.venue_id = p_venue_id
    ),
    'city_categories', (
      select pg_catalog.jsonb_build_object(
        'story', sum(rollup.sum_story)::numeric / nullif(sum(rollup.review_count), 0),
        'puzzles', sum(rollup.sum_puzzles)::numeric / nullif(sum(rollup.review_count), 0),
        'immersion', sum(rollup.sum_immersion)::numeric / nullif(sum(rollup.review_count), 0),
        'service', sum(rollup.sum_service)::numeric / nullif(sum(rollup.review_count), 0),
        'comfort', sum(rollup.sum_comfort)::numeric / nullif(sum(rollup.review_count), 0),
        'value', sum(rollup.sum_value)::numeric / nullif(sum(rollup.review_count), 0)
      )
      from public.room_rating_rollups rollup
      where rollup.city_id = v_city
    ),
    'rooms', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'room_id', rollup.room_id,
          'name', room.name,
          'average', rollup.sum_overall / rollup.review_count,
          'count', rollup.review_count
        )
        order by rollup.sum_overall / rollup.review_count desc, room.name
      )
      from public.room_rating_rollups rollup
      join public.rooms room on room.id = rollup.room_id
      where rollup.venue_id = p_venue_id
    ), '[]'::jsonb),
    'months', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'month', bucket.month,
          'count', bucket.month_count,
          'average', bucket.month_sum / bucket.month_count
        )
        order by bucket.month
      )
      from (
        select
          item->>'month' as month,
          sum((item->>'count')::integer) as month_count,
          sum((item->>'sum')::numeric) as month_sum
        from public.room_rating_rollups rollup
        cross join lateral pg_catalog.jsonb_array_elements(rollup.monthly) item
        where rollup.venue_id = p_venue_id
        group by 1
      ) bucket
    ), '[]'::jsonb),
    'distribution', (
      select pg_catalog.jsonb_build_object(
        '1', coalesce(sum(rollup.dist_1), 0),
        '2', coalesce(sum(rollup.dist_2), 0),
        '3', coalesce(sum(rollup.dist_3), 0),
        '4', coalesce(sum(rollup.dist_4), 0),
        '5', coalesce(sum(rollup.dist_5), 0)
      )
      from public.room_rating_rollups rollup
      where rollup.venue_id = p_venue_id
    ),
    'comments', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'id', review.id,
          'first_name', pg_catalog.split_part(profile.display_name, ' ', 1),
          'comment', review.comment,
          'overall', review.overall,
          'reply', reply.body,
          'created_at', review.created_at
        )
        order by review.created_at desc
      )
      from public.room_reviews review
      join public.profiles profile on profile.id = review.author_id
      left join public.review_replies reply on reply.review_id = review.id
      where review.venue_id = p_venue_id
        and review.hidden_at is null
        and review.comment <> ''
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.venue_review_insights(uuid) is
  'Painel da casa. Agregados e o primeiro nome no comentário. Sem a nota de cada categoria ligada a uma pessoa.';

revoke all on function public.venue_review_insights(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.venue_review_insights(uuid) to authenticated;

create or replace function public.review_rankings(
  p_kind text,
  p_scope text,
  p_city_id text,
  p_country_code text
)
returns table (
  rank integer,
  subject_id uuid,
  subject_name text,
  venue_name text,
  city_id text,
  country_code text,
  review_count integer,
  average numeric,
  bayesian numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_m integer;
  v_min integer;
  v_mean numeric;
begin
  if p_kind not in ('room', 'venue') or p_scope not in ('city', 'country', 'world') then
    raise exception 'ranking inválido' using errcode = '22023';
  end if;
  if p_scope = 'city' and (p_city_id is null or p_city_id = '') then
    raise exception 'cidade obrigatória' using errcode = '22023';
  end if;
  if p_scope = 'country' and (p_country_code is null or p_country_code = '') then
    raise exception 'país obrigatório' using errcode = '22023';
  end if;
  if not private.reviews_enabled() then
    return;
  end if;

  select settings.bayesian_m, settings.ranking_min
    into v_m, v_min
  from public.review_settings settings
  where settings.id = 1;

  select sum(rollup.sum_overall) / nullif(sum(rollup.review_count), 0)
    into v_mean
  from public.room_rating_rollups rollup;

  if v_mean is null then
    return;
  end if;

  if p_kind = 'room' then
    return query
    select
      row_number() over (
        order by scored.bayesian desc, scored.review_count desc, scored.subject_name
      )::integer,
      scored.subject_id,
      scored.subject_name,
      scored.venue_name,
      scored.city_id,
      scored.country_code,
      scored.review_count,
      scored.average,
      scored.bayesian
    from (
      select
        rollup.room_id as subject_id,
        room.name as subject_name,
        venue.name as venue_name,
        rollup.city_id,
        rollup.country_code,
        rollup.review_count,
        rollup.sum_overall / rollup.review_count as average,
        (v_mean * v_m + rollup.sum_overall) / (v_m + rollup.review_count) as bayesian
      from public.room_rating_rollups rollup
      join public.rooms room on room.id = rollup.room_id
      join public.venues venue on venue.id = rollup.venue_id
      where rollup.review_count >= v_min
        and (
          p_scope = 'world'
          or (p_scope = 'city' and rollup.city_id = p_city_id)
          or (p_scope = 'country' and rollup.country_code = p_country_code)
        )
    ) scored;
    return;
  end if;

  return query
  select
    row_number() over (
      order by scored.bayesian desc, scored.review_count desc, scored.subject_name
    )::integer,
    scored.subject_id,
    scored.subject_name,
    scored.venue_name,
    scored.city_id,
    scored.country_code,
    scored.review_count,
    scored.average,
    scored.bayesian
  from (
    select
      rollup.venue_id as subject_id,
      venue.name as subject_name,
      venue.name as venue_name,
      min(rollup.city_id) as city_id,
      min(rollup.country_code) as country_code,
      sum(rollup.review_count)::integer as review_count,
      sum(rollup.sum_overall) / sum(rollup.review_count) as average,
      (v_mean * v_m + sum(rollup.sum_overall))
        / (v_m + sum(rollup.review_count)) as bayesian
    from public.room_rating_rollups rollup
    join public.venues venue on venue.id = rollup.venue_id
    where
      p_scope = 'world'
      or (p_scope = 'city' and rollup.city_id = p_city_id)
      or (p_scope = 'country' and rollup.country_code = p_country_code)
    group by rollup.venue_id, venue.name
    having sum(rollup.review_count) >= v_min
  ) scored;
end;
$$;

comment on function public.review_rankings(text, text, text, text) is
  'Ranking de salas ou casas por cidade, país ou mundo. Prior = média global. m e o mínimo vêm de review_settings.';

revoke all on function public.review_rankings(text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.review_rankings(text, text, text, text)
  to anon, authenticated;

create or replace function public.admin_review_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := private.admin_require();
  return (
    select pg_catalog.jsonb_build_object(
      'enabled', settings.enabled,
      'bayesian_m', settings.bayesian_m,
      'ranking_min', settings.ranking_min,
      'updated_at', settings.updated_at
    )
    from public.review_settings settings
    where settings.id = 1
  );
end;
$$;

revoke all on function public.admin_review_settings()
  from public, anon, authenticated, service_role;
grant execute on function public.admin_review_settings() to authenticated;

create or replace function public.admin_save_review_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_enabled boolean;
  v_m integer;
  v_min integer;
  v_after jsonb;
begin
  v_actor := private.admin_require();
  if p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object' then
    raise exception 'ajuste inválido' using errcode = '22023';
  end if;

  select settings.enabled, settings.bayesian_m, settings.ranking_min,
         pg_catalog.jsonb_build_object(
           'enabled', settings.enabled,
           'bayesian_m', settings.bayesian_m,
           'ranking_min', settings.ranking_min
         )
    into v_enabled, v_m, v_min, v_before
  from public.review_settings settings
  where settings.id = 1;

  if p_patch ? 'enabled' then
    if pg_catalog.jsonb_typeof(p_patch -> 'enabled') <> 'boolean' then
      raise exception 'enabled é booleano' using errcode = '22023';
    end if;
    v_enabled := (p_patch ->> 'enabled')::boolean;
  end if;
  if p_patch ? 'bayesian_m' then
    v_m := (p_patch ->> 'bayesian_m')::integer;
    if v_m is null or v_m < 1 or v_m > 1000 then
      raise exception 'm fica entre 1 e 1000' using errcode = '22023';
    end if;
  end if;
  if p_patch ? 'ranking_min' then
    v_min := (p_patch ->> 'ranking_min')::integer;
    if v_min is null or v_min < 1 or v_min > 10000 then
      raise exception 'o mínimo fica entre 1 e 10000' using errcode = '22023';
    end if;
  end if;

  update public.review_settings
  set enabled = v_enabled,
      bayesian_m = v_m,
      ranking_min = v_min,
      updated_at = pg_catalog.now(),
      updated_by = v_actor
  where id = 1;

  v_after := pg_catalog.jsonb_build_object(
    'enabled', v_enabled,
    'bayesian_m', v_m,
    'ranking_min', v_min
  );
  perform private.admin_audit(
    v_actor,
    'save_review_settings',
    'review_settings',
    '1',
    v_before,
    v_after
  );
  return v_after;
end;
$$;

revoke all on function public.admin_save_review_settings(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_save_review_settings(jsonb) to authenticated;

create or replace function public.admin_review_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := private.admin_require();
  return coalesce((
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', review.id,
        'first_name', pg_catalog.split_part(profile.display_name, ' ', 1),
        'comment', review.comment,
        'overall', review.overall,
        'room_name', room.name,
        'venue_name', venue.name,
        'created_at', review.created_at,
        'hidden', review.hidden_at is not null,
        'hidden_reason', review.hidden_reason,
        'reports', (
          select count(*)::integer
          from public.review_reports report
          where report.review_id = review.id
        )
      )
      order by review.hidden_at nulls first, review.created_at desc
    )
    from public.room_reviews review
    join public.profiles profile on profile.id = review.author_id
    join public.rooms room on room.id = review.room_id
    join public.venues venue on venue.id = review.venue_id
    where review.comment <> ''
  ), '[]'::jsonb);
end;
$$;

comment on function public.admin_review_queue() is
  'Fila de moderação. Primeiro nome e comentário. Sem o id da conta e sem nota por categoria.';

revoke all on function public.admin_review_queue()
  from public, anon, authenticated, service_role;
grant execute on function public.admin_review_queue() to authenticated;

create or replace function public.admin_hide_review(
  p_review_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_reason text;
  v_hidden timestamptz;
begin
  v_actor := private.admin_require();
  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(v_reason) < 1 or pg_catalog.char_length(v_reason) > 280 then
    raise exception 'O motivo fica entre 1 e 280 caracteres.' using errcode = '22023';
  end if;
  select review.hidden_at into v_hidden
  from public.room_reviews review
  where review.id = p_review_id;
  if v_hidden is null and not found then
    raise exception 'avaliação não encontrada' using errcode = 'P0002';
  end if;
  if v_hidden is not null then
    raise exception 'já oculto' using errcode = 'P0001';
  end if;

  update public.room_reviews
  set hidden_at = pg_catalog.now(),
      hidden_by = v_actor,
      hidden_reason = v_reason
  where id = p_review_id;

  insert into public.review_moderation_events (review_id, actor_id, action, reason)
  values (p_review_id, v_actor, 'hide', v_reason);
  perform private.admin_audit(
    v_actor, 'hide_review', 'room_reviews', p_review_id::text,
    jsonb_build_object('hidden', false),
    jsonb_build_object('hidden', true, 'reason', v_reason)
  );
end;
$$;

revoke all on function public.admin_hide_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_hide_review(uuid, text) to authenticated;

create or replace function public.admin_unhide_review(
  p_review_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_reason text;
  v_hidden timestamptz;
begin
  v_actor := private.admin_require();
  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if pg_catalog.char_length(v_reason) < 1 or pg_catalog.char_length(v_reason) > 280 then
    raise exception 'O motivo fica entre 1 e 280 caracteres.' using errcode = '22023';
  end if;
  select review.hidden_at into v_hidden
  from public.room_reviews review
  where review.id = p_review_id;
  if v_hidden is null then
    raise exception 'avaliação não está oculta' using errcode = 'P0002';
  end if;

  update public.room_reviews
  set hidden_at = null,
      hidden_by = null,
      hidden_reason = ''
  where id = p_review_id;

  insert into public.review_moderation_events (review_id, actor_id, action, reason)
  values (p_review_id, v_actor, 'unhide', v_reason);
  perform private.admin_audit(
    v_actor, 'unhide_review', 'room_reviews', p_review_id::text,
    jsonb_build_object('hidden', true),
    jsonb_build_object('hidden', false, 'reason', v_reason)
  );
end;
$$;

revoke all on function public.admin_unhide_review(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_unhide_review(uuid, text) to authenticated;

create or replace function public.admin_review_audit()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := private.admin_require();
  return coalesce((
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'review_id', event.review_id,
        'action', event.action,
        'reason', event.reason,
        'created_at', event.created_at
      )
      order by event.created_at desc
    )
    from public.review_moderation_events event
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_review_audit()
  from public, anon, authenticated, service_role;
grant execute on function public.admin_review_audit() to authenticated;

create or replace function public.set_venue_staff(
  p_venue_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.owns_venue(p_venue_id) then
    perform private.admin_require();
  end if;
  if p_role is null or pg_catalog.btrim(p_role) = '' then
    delete from public.venue_staff
    where venue_id = p_venue_id
      and user_id = p_user_id;
    return;
  end if;
  if p_role not in ('partner', 'staff') then
    raise exception 'papel inválido' using errcode = '22023';
  end if;
  insert into public.venue_staff (venue_id, user_id, role)
  values (p_venue_id, p_user_id, p_role)
  on conflict (venue_id, user_id) do update
  set role = excluded.role;
end;
$$;

revoke all on function public.set_venue_staff(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_venue_staff(uuid, uuid, text) to authenticated;

alter table public.room_rating_rollups replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'room_rating_rollups'
    )
  then
    alter publication supabase_realtime add table public.room_rating_rollups;
  end if;
end $$;
