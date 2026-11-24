-- Contas fantasmas para teste em produção (jogadores e casas de teste).
--
-- profiles.is_test e venues.is_test. Só service_role ou admin com aal2
-- mudam a marca. Casa criada por dono de teste já nasce de teste.
-- Casa de teste aprovada só aparece para contas de teste e para o admin
-- com aal2. Anon e jogador comum não veem a casa, as salas, os horários,
-- os grupos nem a casa no ranking de avaliações.
-- Contas de teste continuam vendo as casas reais.

alter table public.profiles
  add column is_test boolean not null default false;

alter table public.venues
  add column is_test boolean not null default false;

comment on column public.profiles.is_test is
  'Conta fantasma de teste. Muda só por service_role ou admin aal2.';

comment on column public.venues.is_test is
  'Casa fantasma de teste. Fica fora da vitrine pública.';

-- O app não lê nem grava a marca. Os grants de coluna existentes não
-- incluem colunas novas em profiles. Em venues o update é da tabela,
-- então o trigger abaixo segura a coluna.

create or replace function private.viewer_is_tester()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.is_test from public.profiles p where p.id = (select auth.uid())),
    false
  );
$$;

revoke all on function private.viewer_is_tester() from public;
grant execute on function private.viewer_is_tester()
  to anon, authenticated, service_role;

create or replace function private.venues_test_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or private.is_admin_aal2() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.is_test := coalesce(
      (select p.is_test from public.profiles p where p.id = new.owner_id),
      false
    );
  else
    new.is_test := old.is_test;
  end if;
  return new;
end;
$$;

revoke all on function private.venues_test_flag() from public, anon, authenticated;

-- Roda depois de venues_guard e venues_normalize (ordem alfabética), então
-- o owner_id já é o auth.uid() no insert.
drop trigger if exists venues_test_flag on public.venues;
create trigger venues_test_flag
  before insert or update on public.venues
  for each row execute function private.venues_test_flag();

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
        (
          status = 'approved'
          and suspended_at is null
          and (not is_test or private.viewer_is_tester())
        )
        or owner_id = (select auth.uid())
        or private.is_admin_aal2()
      )
  );
$$;

drop policy if exists venues_select_anon on public.venues;
create policy venues_select_anon on public.venues
  for select to anon
  using (status = 'approved' and suspended_at is null and not is_test);

drop policy if exists venues_select on public.venues;
create policy venues_select on public.venues
  for select to authenticated
  using (
    (
      status = 'approved'
      and suspended_at is null
      and (not is_test or private.viewer_is_tester())
    )
    or owner_id = (select auth.uid())
    or private.is_admin_aal2()
  );

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
  from public.room_rating_rollups rollup
  join public.venues venue on venue.id = rollup.venue_id
  where venue.status = 'approved'
    and not venue.is_test
    and venue.suspended_at is null;

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
        and venue.status = 'approved'
    and not venue.is_test
        and venue.suspended_at is null
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
    where venue.status = 'approved'
    and not venue.is_test
      and venue.suspended_at is null
      and (
        p_scope = 'world'
        or (p_scope = 'city' and rollup.city_id = p_city_id)
        or (p_scope = 'country' and rollup.country_code = p_country_code)
      )
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
