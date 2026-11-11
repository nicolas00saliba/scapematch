-- Passaporte de salas. Flag desligada. Não aplicado no remoto.
-- Um carimbo por sala e por jogador. Jogar de novo soma a visita
-- e não abre outro carimbo. Marcos saem em pontos do programa
-- passport: desconto no teto atual, sem pagar a vaga. Estorno ou
-- cancelamento tira o carimbo e o marco. O mimo é da casa.

alter table public.referral_program_settings
  add column if not exists passport_enabled boolean not null default false,
  add column if not exists passport_rooms_5 integer not null default 5,
  add column if not exists passport_points_5 integer not null default 500,
  add column if not exists passport_rooms_10 integer not null default 10,
  add column if not exists passport_points_10 integer not null default 1000,
  add column if not exists passport_rooms_25 integer not null default 25,
  add column if not exists passport_points_25 integer not null default 3000,
  add column if not exists passport_house_points integer not null default 300;

alter table public.referral_program_settings
  drop constraint if exists referral_program_settings_passport_order;

alter table public.referral_program_settings
  add constraint referral_program_settings_passport_order
  check (
    passport_rooms_5 > 0
    and passport_rooms_10 > passport_rooms_5
    and passport_rooms_25 > passport_rooms_10
    and passport_points_5 >= 0
    and passport_points_10 >= 0
    and passport_points_25 >= 0
    and passport_house_points >= 0
  );

comment on column public.referral_program_settings.passport_enabled is
  'Passaporte de salas. Nasce desligado. O jogador e a casa só veem com a flag ligada.';

comment on column public.referral_program_settings.passport_house_points is
  'Pontos ao fechar todas as salas de uma casa com duas ou mais. Uma vez por casa. 0 desliga.';

alter table public.scape_point_entries
  drop constraint if exists scape_point_entries_program_check;

alter table public.scape_point_entries
  add constraint scape_point_entries_program_check
  check (
    program is null
    or program in ('c2c', 'c2b', 'cashback', 'redeem', 'welcome', 'passport')
  );

create table public.passport_stamps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  play_count integer not null default 1 check (play_count > 0),
  first_completed_at timestamptz not null,
  last_completed_at timestamptz not null,
  unique (user_id, room_id)
);

create index passport_stamps_by_user
  on public.passport_stamps (user_id, first_completed_at);

create index passport_stamps_by_venue
  on public.passport_stamps (venue_id, user_id);

create table public.passport_plays (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  payment_charge_id uuid not null unique references public.payment_charges (id) on delete cascade,
  completed_at timestamptz not null,
  reversed_at timestamptz
);

create index passport_plays_by_user_room
  on public.passport_plays (user_id, room_id)
  where reversed_at is null;

create table public.passport_milestones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  milestone_key text not null,
  points integer not null check (points > 0),
  room_ids uuid[] not null default '{}',
  entry_id uuid references public.scape_point_entries (id),
  grant_seq integer not null default 1 check (grant_seq > 0),
  reversed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (user_id, milestone_key)
);

create table public.passport_gifts (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  room_id uuid references public.rooms (id) on delete cascade,
  trigger_kind text not null check (trigger_kind in ('stamp', 'house_complete')),
  title text not null check (pg_catalog.char_length(title) between 2 and 80),
  details text not null default '' check (pg_catalog.char_length(details) <= 400),
  active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    (room_id is not null and trigger_kind = 'stamp')
    or (room_id is null and trigger_kind in ('stamp', 'house_complete'))
  )
);

create unique index passport_gifts_one_room
  on public.passport_gifts (venue_id, room_id, trigger_kind)
  where room_id is not null;

create unique index passport_gifts_one_house
  on public.passport_gifts (venue_id, trigger_kind)
  where room_id is null;

create table public.passport_gift_claims (
  id uuid primary key default gen_random_uuid(),
  gift_id uuid not null references public.passport_gifts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9]{8}$'),
  status text not null default 'available' check (
    status in ('available', 'delivered', 'revoked')
  ),
  delivered_at timestamptz,
  delivered_by uuid references auth.users (id),
  created_at timestamptz not null default pg_catalog.now(),
  unique (gift_id, user_id)
);

create index passport_gift_claims_by_user
  on public.passport_gift_claims (user_id, created_at desc);

comment on table public.passport_stamps is
  'Um carimbo por sala e jogador. Só entra com reserva paga e comparecimento confirmado pela casa.';

create table public.session_checkins (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  room_id uuid not null references public.rooms (id) on delete cascade,
  marked_by uuid not null references auth.users (id),
  marked_at timestamptz not null default pg_catalog.now(),
  unique (group_id, user_id)
);

create index session_checkins_by_venue
  on public.session_checkins (venue_id, marked_at desc);

create index session_checkins_by_user
  on public.session_checkins (user_id, marked_at desc);

create index session_checkins_by_marked_by
  on public.session_checkins (marked_by);

comment on table public.session_checkins is
  'Comparecimento confirmado pela casa, um por jogador na sessão. A auditoria fica em admin_audit_log.';

alter table public.session_checkins enable row level security;

revoke all on table public.session_checkins
  from public, anon, authenticated, service_role;

create policy session_checkins_select on public.session_checkins
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.owns_venue(venue_id)
    or private.is_admin_aal2()
  );

grant select on table public.session_checkins to authenticated;

comment on table public.passport_gifts is
  'Mimo opcional da casa. O custo é dela. Nada é obrigatório.';

alter table public.passport_stamps enable row level security;
alter table public.passport_plays enable row level security;
alter table public.passport_milestones enable row level security;
alter table public.passport_gifts enable row level security;
alter table public.passport_gift_claims enable row level security;

revoke all on table public.passport_stamps from public, anon, authenticated, service_role;
revoke all on table public.passport_plays from public, anon, authenticated, service_role;
revoke all on table public.passport_milestones from public, anon, authenticated, service_role;
revoke all on table public.passport_gifts from public, anon, authenticated, service_role;
revoke all on table public.passport_gift_claims from public, anon, authenticated, service_role;

create policy passport_stamps_select on public.passport_stamps
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.owns_venue(venue_id)
    or private.is_admin_aal2()
  );

create policy passport_plays_select on public.passport_plays
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.owns_venue(venue_id)
    or private.is_admin_aal2()
  );

create policy passport_milestones_select on public.passport_milestones
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_admin_aal2()
  );

-- Helpers security definer quebram o ciclo entre as duas policies:
-- gifts olha claims e claims olha gifts. Sem eles o Postgres detecta
-- recursão infinita no select do dono.
create or replace function private.passport_gift_visible(p_gift_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.passport_gift_claims c
    where c.gift_id = p_gift_id
      and c.user_id = (select auth.uid())
      and c.status <> 'revoked'
  );
$$;

create or replace function private.passport_claim_owned(p_gift_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.passport_gifts g
    where g.id = p_gift_id
      and private.owns_venue(g.venue_id)
  );
$$;

create policy passport_gifts_select on public.passport_gifts
  for select to authenticated
  using (
    private.owns_venue(venue_id)
    or private.is_admin_aal2()
    or private.passport_gift_visible(id)
  );

create policy passport_gift_claims_select on public.passport_gift_claims
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.is_admin_aal2()
    or private.passport_claim_owned(gift_id)
  );

grant select on table public.passport_stamps to authenticated;
grant select on table public.passport_plays to authenticated;
grant select on table public.passport_milestones to authenticated;
grant select on table public.passport_gifts to authenticated;
grant select on table public.passport_gift_claims to authenticated;

create or replace function private.point_pools(p_user_id uuid)
returns table (slot_points integer, discount_points integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_slot integer := 0;
  v_discount integer := 0;
  v_redeemed integer := 0;
begin
  select
    coalesce(sum(r.points) filter (
      where r.program in ('welcome', 'passport')
    ), 0)::integer,
    coalesce(sum(r.points) filter (
      where r.program is null or r.program not in ('welcome', 'passport')
    ), 0)::integer
  into v_discount, v_slot
  from public.scape_point_entries r
  where r.user_id = p_user_id
    and r.kind = 'release';

  v_discount := v_discount - coalesce((
    select sum(v.points)::integer
    from public.scape_point_entries v
    join public.scape_point_entries a on a.id = v.relates_to
    where v.user_id = p_user_id
      and v.kind = 'reversal'
      and a.program in ('welcome', 'passport')
      and exists (
        select 1
        from public.scape_point_entries rel
        where rel.relates_to = a.id
          and rel.kind = 'release'
      )
  ), 0);

  v_slot := v_slot - coalesce((
    select sum(v.points)::integer
    from public.scape_point_entries v
    join public.scape_point_entries a on a.id = v.relates_to
    where v.user_id = p_user_id
      and v.kind = 'reversal'
      and (a.program is null or a.program not in ('welcome', 'passport'))
      and exists (
        select 1
        from public.scape_point_entries rel
        where rel.relates_to = a.id
          and rel.kind = 'release'
      )
  ), 0);

  select coalesce(sum(s.points), 0)::integer
  into v_redeemed
  from public.scape_point_entries s
  where s.user_id = p_user_id
    and s.kind = 'redemption'
    and not exists (
      select 1
      from public.scape_point_entries back
      where back.relates_to = s.id
        and back.kind = 'redemption_reversal'
    );

  v_slot := greatest(v_slot, 0);
  v_discount := greatest(v_discount, 0);
  slot_points := greatest(v_slot - v_redeemed, 0);
  discount_points := greatest(
    v_discount - greatest(v_redeemed - v_slot, 0),
    0
  );
  return next;
end;
$$;

create or replace function private.subsidy_quote(
  p_user_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_points integer,
  p_lock boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point integer;
  v_available integer;
  v_fee integer;
  v_house integer;
  v_room integer;
  v_cap_cents integer;
  v_max_points integer;
  v_min integer;
  v_max_bps integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
  v_slot integer;
  v_discount integer;
  v_hard integer;
  v_hard_points integer;
  v_cap_points integer;
  v_slot_max integer;
  v_discount_max integer;
begin
  if p_lock then
    perform 1 from public.profiles where id = p_user_id for update;
  end if;
  select point_value_cents, redeem_min_points, redeem_max_bps
    into v_point, v_min, v_max_bps
  from public.referral_program_settings where id = 1;
  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := greatest(coalesce(v_available, 0), 0);
  v_fee := private.reward_cents(p_gross, p_commission_bps);
  v_house := p_gross - v_fee;
  v_room := case when p_gross > 1 then p_gross - 1 else 0 end;
  v_cap_cents := private.reward_cents(p_gross, coalesce(v_max_bps, 10000));
  select p.slot_points, p.discount_points
    into v_slot, v_discount
  from private.point_pools(p_user_id) p;
  v_hard := least(greatest(v_fee, 0), v_room);
  v_hard_points := v_hard / v_point;
  v_cap_points := greatest(v_cap_cents, 0) / v_point;
  v_slot_max := least(greatest(coalesce(v_slot, 0), 0), v_hard_points);
  v_discount_max := least(
    greatest(coalesce(v_discount, 0), 0),
    v_cap_points,
    greatest(v_hard_points - v_slot_max, 0)
  );
  v_max_points := least(v_slot_max + v_discount_max, v_available);
  if v_available < coalesce(v_min, 0) or v_max_points < coalesce(v_min, 0) then
    v_max_points := 0;
  end if;
  v_points := least(greatest(coalesce(p_points, 0), 0), v_available, v_max_points);
  if v_points < coalesce(v_min, 0) then
    v_points := 0;
  end if;
  v_subsidy := v_points * v_point;
  v_charged := p_gross - v_subsidy;
  if v_subsidy = 0 then
    v_split := null;
  else
    v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
  end if;
  return pg_catalog.jsonb_build_object(
    'gross_cents', p_gross,
    'charged_cents', v_charged,
    'subsidy_cents', v_subsidy,
    'points', v_points,
    'house_net_cents', v_house,
    'commission_cents', v_fee,
    'split_percent', v_split,
    'max_points', v_max_points,
    'available_points', v_available,
    'point_value_cents', v_point,
    'redeem_min_points', v_min,
    'redeem_max_bps', v_max_bps,
    'slot_points', greatest(coalesce(v_slot, 0), 0),
    'discount_points', greatest(coalesce(v_discount, 0), 0)
  );
end;
$$;

create or replace function private.passport_grant_milestone(
  p_user_id uuid,
  p_key text,
  p_points integer,
  p_room_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.passport_milestones%rowtype;
  v_seq integer;
  v_value integer;
  v_cents integer;
  v_idem text;
  v_accrual uuid;
begin
  if p_user_id is null or coalesce(p_points, 0) <= 0 then
    return;
  end if;
  select * into v_row
  from public.passport_milestones
  where user_id = p_user_id
    and milestone_key = p_key
  for update;
  if v_row.id is not null and v_row.reversed_at is null then
    return;
  end if;
  select point_value_cents into v_value
  from public.referral_program_settings where id = 1;
  v_value := greatest(coalesce(v_value, 1), 1);
  v_seq := coalesce(v_row.grant_seq, 0) + 1;
  v_cents := p_points * v_value;
  v_idem := 'passport:' || p_user_id::text || ':' || p_key || ':' || v_seq::text;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key, available_at
  ) values (
    p_user_id, 'accrual', p_points, v_cents, 'passport',
    v_idem, pg_catalog.now()
  )
  on conflict (idempotency_key) do nothing
  returning id into v_accrual;
  if v_accrual is null then
    return;
  end if;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, relates_to, idempotency_key
  ) values (
    p_user_id, 'release', p_points, v_cents, 'passport', v_accrual,
    'release:' || v_idem
  )
  on conflict (idempotency_key) do nothing;
  if v_row.id is null then
    insert into public.passport_milestones (
      user_id, milestone_key, points, room_ids, entry_id, grant_seq
    ) values (
      p_user_id, p_key, p_points, coalesce(p_room_ids, '{}'), v_accrual, v_seq
    );
  else
    update public.passport_milestones
    set points = p_points,
        room_ids = coalesce(p_room_ids, '{}'),
        entry_id = v_accrual,
        grant_seq = v_seq,
        reversed_at = null,
        created_at = pg_catalog.now()
    where id = v_row.id;
  end if;
end;
$$;

create or replace function private.passport_reverse_milestone(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.passport_milestones%rowtype;
begin
  select * into v_row
  from public.passport_milestones
  where id = p_id
  for update;
  if v_row.id is null or v_row.reversed_at is not null or v_row.entry_id is null then
    return;
  end if;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, relates_to, idempotency_key
  )
  select
    e.user_id, 'reversal', e.points, e.amount_cents, e.program, e.id,
    'reversal:' || e.id::text
  from public.scape_point_entries e
  where e.id = v_row.entry_id
    and e.kind = 'accrual'
    and not exists (
      select 1
      from public.scape_point_entries r
      where r.relates_to = e.id
        and r.kind = 'reversal'
    );
  update public.passport_milestones
  set reversed_at = pg_catalog.now()
  where id = v_row.id;
end;
$$;

create or replace function private.passport_sync_counts(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_have integer;
  v_rooms integer;
  v_points integer;
  v_key text;
  v_row public.passport_milestones%rowtype;
begin
  select count(*)::integer into v_have
  from public.passport_stamps
  where user_id = p_user_id;
  for v_rooms, v_points in
    select rooms, points
    from public.referral_program_settings s
    cross join lateral (
      values
        (s.passport_rooms_5, s.passport_points_5),
        (s.passport_rooms_10, s.passport_points_10),
        (s.passport_rooms_25, s.passport_points_25)
    ) as rule(rooms, points)
    where s.id = 1
  loop
    v_key := 'count:' || v_rooms::text;
    select * into v_row
    from public.passport_milestones
    where user_id = p_user_id
      and milestone_key = v_key;
    if v_points > 0 and v_have >= v_rooms then
      perform private.passport_grant_milestone(
        p_user_id, v_key, v_points, '{}'::uuid[]
      );
    elsif v_row.id is not null and v_row.reversed_at is null then
      perform private.passport_reverse_milestone(v_row.id);
    end if;
  end loop;
end;
$$;

create or replace function private.passport_sync_house(
  p_user_id uuid,
  p_venue_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_points integer;
  v_key text;
  v_rooms uuid[];
  v_open public.passport_milestones%rowtype;
  v_closed boolean;
begin
  select passport_house_points into v_points
  from public.referral_program_settings where id = 1;
  v_key := 'house:' || p_venue_id::text;
  select * into v_open
  from public.passport_milestones
  where user_id = p_user_id
    and milestone_key = v_key;
  if v_open.id is not null and v_open.reversed_at is null then
    if coalesce(v_points, 0) <= 0
      or coalesce(cardinality(v_open.room_ids), 0) < 2
      or exists (
        select 1
        from unnest(v_open.room_ids) as needed(room_id)
        where not exists (
          select 1
          from public.passport_stamps s
          where s.user_id = p_user_id
            and s.room_id = needed.room_id
        )
      )
    then
      perform private.passport_reverse_milestone(v_open.id);
    end if;
    return;
  end if;
  select coalesce(array_agg(r.id order by r.id), '{}')
  into v_rooms
  from public.rooms r
  where r.venue_id = p_venue_id;
  v_closed := coalesce(v_points, 0) > 0
    and coalesce(cardinality(v_rooms), 0) >= 2
    and not exists (
      select 1
      from unnest(v_rooms) as needed(room_id)
      where not exists (
        select 1
        from public.passport_stamps s
        where s.user_id = p_user_id
          and s.room_id = needed.room_id
      )
    );
  if v_closed then
    perform private.passport_grant_milestone(
      p_user_id, v_key, v_points, v_rooms
    );
  end if;
end;
$$;

create or replace function private.passport_gift_code()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_try integer := 0;
begin
  loop
    v_try := v_try + 1;
    v_code := pg_catalog.upper(
      pg_catalog.substr(pg_catalog.md5(gen_random_uuid()::text), 1, 8)
    );
    exit when not exists (
      select 1 from public.passport_gift_claims where code = v_code
    );
    if v_try >= 8 then
      raise exception 'codigo do mimo esgotou' using errcode = '55000';
    end if;
  end loop;
  return v_code;
end;
$$;

create or replace function private.passport_issue_claim(
  p_gift_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_try integer := 0;
begin
  if exists (
    select 1
    from public.passport_gift_claims
    where gift_id = p_gift_id
      and user_id = p_user_id
      and status <> 'revoked'
  ) then
    return;
  end if;
  loop
    v_try := v_try + 1;
    v_code := private.passport_gift_code();
    begin
      insert into public.passport_gift_claims (gift_id, user_id, code)
      values (p_gift_id, p_user_id, v_code)
      on conflict (gift_id, user_id) do update
      set status = 'available'
      where public.passport_gift_claims.status = 'revoked';
      return;
    exception
      when unique_violation then
        if v_try >= 8 then
          raise;
        end if;
    end;
  end loop;
end;
$$;

create or replace function private.passport_sync_gifts(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gift uuid;
begin
  for v_gift in
    select g.id
    from public.passport_gifts g
    where g.active
      and (
        (
          g.trigger_kind = 'stamp'
          and g.room_id is not null
          and exists (
            select 1
            from public.passport_stamps s
            where s.user_id = p_user_id
              and s.room_id = g.room_id
          )
        )
        or (
          g.trigger_kind = 'stamp'
          and g.room_id is null
          and exists (
            select 1
            from public.passport_stamps s
            where s.user_id = p_user_id
              and s.venue_id = g.venue_id
          )
        )
        or (
          g.trigger_kind = 'house_complete'
          and exists (
            select 1
            from public.passport_milestones m
            where m.user_id = p_user_id
              and m.milestone_key = 'house:' || g.venue_id::text
              and m.reversed_at is null
          )
        )
      )
  loop
    perform private.passport_issue_claim(v_gift, p_user_id);
  end loop;

  update public.passport_gift_claims c
  set status = 'revoked'
  where c.user_id = p_user_id
    and c.status = 'available'
    and not exists (
      select 1
      from public.passport_gifts g
      where g.id = c.gift_id
        and g.active
        and (
          (
            g.trigger_kind = 'stamp'
            and g.room_id is not null
            and exists (
              select 1 from public.passport_stamps s
              where s.user_id = p_user_id and s.room_id = g.room_id
            )
          )
          or (
            g.trigger_kind = 'stamp'
            and g.room_id is null
            and exists (
              select 1 from public.passport_stamps s
              where s.user_id = p_user_id and s.venue_id = g.venue_id
            )
          )
          or (
            g.trigger_kind = 'house_complete'
            and exists (
              select 1 from public.passport_milestones m
              where m.user_id = p_user_id
                and m.milestone_key = 'house:' || g.venue_id::text
                and m.reversed_at is null
            )
          )
        )
    );
end;
$$;

create or replace function private.passport_sync_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue uuid;
begin
  if p_user_id is null then
    return;
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  perform private.passport_sync_counts(p_user_id);
  for v_venue in
    select distinct s.venue_id
    from public.passport_stamps s
    where s.user_id = p_user_id
    union
    select pg_catalog.split_part(m.milestone_key, ':', 2)::uuid
    from public.passport_milestones m
    where m.user_id = p_user_id
      and m.milestone_key like 'house:%'
      and m.reversed_at is null
  loop
    perform private.passport_sync_house(p_user_id, v_venue);
  end loop;
  perform private.passport_sync_gifts(p_user_id);
end;
$$;

create or replace function private.passport_reverse_play(p_play_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_play public.passport_plays%rowtype;
  v_count integer;
begin
  select * into v_play
  from public.passport_plays
  where id = p_play_id
  for update;
  if v_play.id is null or v_play.reversed_at is not null then
    return;
  end if;
  perform 1 from public.profiles where id = v_play.user_id for update;
  update public.passport_plays
  set reversed_at = pg_catalog.now()
  where id = v_play.id;
  select play_count into v_count
  from public.passport_stamps
  where user_id = v_play.user_id
    and room_id = v_play.room_id
  for update;
  if v_count is null then
    perform private.passport_sync_user(v_play.user_id);
    return;
  end if;
  if v_count <= 1 then
    delete from public.passport_stamps
    where user_id = v_play.user_id
      and room_id = v_play.room_id;
  else
    update public.passport_stamps
    set play_count = play_count - 1
    where user_id = v_play.user_id
      and room_id = v_play.room_id;
  end if;
  perform private.passport_sync_user(v_play.user_id);
end;
$$;

create or replace function private.passport_bump_stamp(
  p_user_id uuid,
  p_room_id uuid,
  p_venue_id uuid,
  p_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.passport_stamps (
    user_id, room_id, venue_id, play_count, first_completed_at, last_completed_at
  ) values (
    p_user_id, p_room_id, p_venue_id, 1, p_at, p_at
  )
  on conflict (user_id, room_id) do update
  set play_count = public.passport_stamps.play_count + 1,
      last_completed_at = excluded.last_completed_at;
end;
$$;

create or replace function private.passport_apply_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_play public.passport_plays%rowtype;
  v_on boolean;
  v_bad boolean;
  v_checked boolean;
  v_at timestamptz;
  v_inserted uuid;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null then
    return;
  end if;
  select passport_enabled into v_on
  from public.referral_program_settings where id = 1;
  select * into v_play
  from public.passport_plays
  where payment_charge_id = p_charge_id;
  if not coalesce(v_on, false) and v_play.id is null then
    return;
  end if;

  select * into v_group from public.groups where id = v_charge.group_id;
  select * into v_member
  from public.group_members
  where group_id = v_charge.group_id
    and user_id = v_charge.user_id;

  v_bad := v_charge.status is distinct from 'paid'
    or v_charge.refunded_at is not null
    or v_group.id is null
    or v_group.cancelled_at is not null
    or v_member.id is null
    or v_member.payment_status is distinct from 'paid'
    or v_member.refund_status is distinct from 'none'
    or v_member.attendance = 'cancelled';
  v_checked := exists (
    select 1
    from public.session_checkins k
    where k.group_id = v_charge.group_id
      and k.user_id = v_charge.user_id
  );

  if v_play.id is not null and v_play.reversed_at is null and v_bad then
    perform private.passport_reverse_play(v_play.id);
    return;
  end if;
  if v_bad
    or not coalesce(v_on, false)
    or not v_checked
    or v_group.starts_at > pg_catalog.now()
  then
    return;
  end if;
  if v_play.id is not null and v_play.reversed_at is null then
    return;
  end if;

  select k.marked_at into v_at
  from public.session_checkins k
  where k.group_id = v_charge.group_id
    and k.user_id = v_charge.user_id;

  perform 1 from public.profiles where id = v_charge.user_id for update;
  if v_play.id is null then
    insert into public.passport_plays (
      user_id, room_id, venue_id, payment_charge_id, completed_at
    ) values (
      v_charge.user_id, v_group.room_id, v_group.venue_id,
      v_charge.id, v_at
    )
    on conflict (payment_charge_id) do nothing
    returning id into v_inserted;
    if v_inserted is null then
      return;
    end if;
  else
    update public.passport_plays
    set reversed_at = null
    where id = v_play.id
      and reversed_at is not null;
    if not found then
      return;
    end if;
  end if;
  perform private.passport_bump_stamp(
    v_charge.user_id, v_group.room_id, v_group.venue_id, v_at
  );
  perform private.passport_sync_user(v_charge.user_id);
end;
$$;

create or replace function private.passport_catch_up()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_n integer := 0;
begin
  if not coalesce((
    select passport_enabled
    from public.referral_program_settings
    where id = 1
  ), false) then
    return 0;
  end if;
  for v_id in
    select c.id
    from public.payment_charges c
    where exists (
      select 1
      from public.session_checkins k
      where k.group_id = c.group_id
        and k.user_id = c.user_id
    )
    or exists (
      select 1
      from public.passport_plays p
      where p.payment_charge_id = c.id
        and p.reversed_at is null
    )
  loop
    perform private.passport_apply_charge(v_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function private.passport_on_charge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.passport_apply_charge(new.id);
  return new;
end;
$$;

create or replace function private.passport_on_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select c.id
    from public.payment_charges c
    where c.group_id = new.group_id
      and c.user_id = new.user_id
  loop
    perform private.passport_apply_charge(v_id);
  end loop;
  return new;
end;
$$;

create or replace function private.passport_on_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if new.cancelled_at is not distinct from old.cancelled_at then
    return new;
  end if;
  for v_id in
    select c.id from public.payment_charges c where c.group_id = new.id
  loop
    perform private.passport_apply_charge(v_id);
  end loop;
  return new;
end;
$$;

drop trigger if exists passport_charge_sync on public.payment_charges;
create trigger passport_charge_sync
  after insert or update of status, refunded_at
  on public.payment_charges
  for each row execute function private.passport_on_charge();

drop trigger if exists passport_member_sync on public.group_members;
create trigger passport_member_sync
  after insert or update of payment_status, refund_status, attendance
  on public.group_members
  for each row execute function private.passport_on_member();

drop trigger if exists passport_group_sync on public.groups;
create trigger passport_group_sync
  after update of cancelled_at
  on public.groups
  for each row execute function private.passport_on_group();

create or replace function public.passport_program_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select passport_enabled
    from public.referral_program_settings
    where id = 1
  ), false);
$$;

create or replace function public.my_passport()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_on boolean;
  v_have integer;
  v_next_rooms integer;
  v_next_points integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_on := public.passport_program_enabled();
  if not v_on then
    return pg_catalog.jsonb_build_object('enabled', false);
  end if;
  for v_id in
    select c.id
    from public.payment_charges c
    where c.user_id = v_uid
      and (
        exists (
          select 1
          from public.session_checkins k
          where k.group_id = c.group_id
            and k.user_id = c.user_id
        )
        or exists (
          select 1
          from public.passport_plays p
          where p.payment_charge_id = c.id
            and p.reversed_at is null
        )
      )
  loop
    perform private.passport_apply_charge(v_id);
  end loop;
  select count(*)::integer into v_have
  from public.passport_stamps
  where user_id = v_uid;
  select rooms, points into v_next_rooms, v_next_points
  from public.referral_program_settings s
  cross join lateral (
    values
      (s.passport_rooms_5, s.passport_points_5),
      (s.passport_rooms_10, s.passport_points_10),
      (s.passport_rooms_25, s.passport_points_25)
  ) as rule(rooms, points)
  where s.id = 1
    and points > 0
    and rooms > v_have
  order by rooms
  limit 1;
  return pg_catalog.jsonb_build_object(
    'enabled', true,
    'distinct_rooms', v_have,
    'next_rooms', v_next_rooms,
    'next_points', v_next_points,
    'stamps', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'room_id', s.room_id,
        'room_name', r.name,
        'venue_id', s.venue_id,
        'venue_name', v.name,
        'play_count', s.play_count,
        'first_completed_at', s.first_completed_at
      ) order by s.first_completed_at)
      from public.passport_stamps s
      join public.rooms r on r.id = s.room_id
      join public.venues v on v.id = s.venue_id
      where s.user_id = v_uid
    ), '[]'::jsonb),
    'milestones', coalesce((
      select pg_catalog.jsonb_agg(item order by item ->> 'key')
      from (
        select pg_catalog.jsonb_build_object(
          'key', 'count:' || rule.rooms::text,
          'rooms', rule.rooms,
          'points', rule.points,
          'reached', exists (
            select 1
            from public.passport_milestones m
            where m.user_id = v_uid
              and m.milestone_key = 'count:' || rule.rooms::text
              and m.reversed_at is null
          )
        ) as item
        from public.referral_program_settings s
        cross join lateral (
          values
            (s.passport_rooms_5, s.passport_points_5),
            (s.passport_rooms_10, s.passport_points_10),
            (s.passport_rooms_25, s.passport_points_25)
        ) as rule(rooms, points)
        where s.id = 1
          and rule.points > 0
        union all
        select pg_catalog.jsonb_build_object(
          'key', m.milestone_key,
          'rooms', null,
          'points', m.points,
          'reached', true,
          'venue_id', pg_catalog.split_part(m.milestone_key, ':', 2)
        )
        from public.passport_milestones m
        where m.user_id = v_uid
          and m.milestone_key like 'house:%'
          and m.reversed_at is null
      ) listed
    ), '[]'::jsonb),
    'gifts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'title', g.title,
        'details', g.details,
        'code', c.code,
        'status', c.status,
        'venue_name', v.name,
        'room_name', r.name
      ) order by c.created_at)
      from public.passport_gift_claims c
      join public.passport_gifts g on g.id = c.gift_id
      join public.venues v on v.id = g.venue_id
      left join public.rooms r on r.id = g.room_id
      where c.user_id = v_uid
        and c.status <> 'revoked'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.save_passport_gift(
  p_venue_id uuid,
  p_room_id uuid,
  p_trigger text,
  p_title text,
  p_details text,
  p_active boolean,
  p_gift_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_details text;
  v_room_venue uuid;
  v_id uuid;
  v_user uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.owns_venue(p_venue_id) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if not public.passport_program_enabled() then
    raise exception 'passaporte desligado' using errcode = '55000';
  end if;
  if p_trigger not in ('stamp', 'house_complete') then
    raise exception 'gatilho invalido' using errcode = '22023';
  end if;
  if p_room_id is not null and p_trigger <> 'stamp' then
    raise exception 'mimo de sala so no carimbo' using errcode = '22023';
  end if;
  if p_room_id is not null then
    select venue_id into v_room_venue from public.rooms where id = p_room_id;
    if v_room_venue is distinct from p_venue_id then
      raise exception 'sala de outra casa' using errcode = '22023';
    end if;
  end if;
  v_title := pg_catalog.btrim(coalesce(p_title, ''));
  v_details := pg_catalog.btrim(coalesce(p_details, ''));
  if pg_catalog.char_length(v_title) < 2 or pg_catalog.char_length(v_title) > 80
    or pg_catalog.char_length(v_details) > 400
  then
    raise exception 'texto do mimo invalido' using errcode = '22023';
  end if;
  if p_gift_id is not null then
    update public.passport_gifts
    set room_id = p_room_id,
        trigger_kind = p_trigger,
        title = v_title,
        details = v_details,
        active = coalesce(p_active, true),
        updated_at = pg_catalog.now()
    where id = p_gift_id
      and venue_id = p_venue_id
    returning id into v_id;
    if v_id is null then
      raise exception 'mimo nao encontrado' using errcode = '22023';
    end if;
  elsif p_room_id is null then
    insert into public.passport_gifts (
      venue_id, room_id, trigger_kind, title, details, active
    ) values (
      p_venue_id, null, p_trigger, v_title, v_details, coalesce(p_active, true)
    )
    on conflict (venue_id, trigger_kind) where room_id is null
    do update set
      title = excluded.title,
      details = excluded.details,
      active = excluded.active,
      updated_at = pg_catalog.now()
    returning id into v_id;
  else
    insert into public.passport_gifts (
      venue_id, room_id, trigger_kind, title, details, active
    ) values (
      p_venue_id, p_room_id, p_trigger, v_title, v_details, coalesce(p_active, true)
    )
    on conflict (venue_id, room_id, trigger_kind) where room_id is not null
    do update set
      title = excluded.title,
      details = excluded.details,
      active = excluded.active,
      updated_at = pg_catalog.now()
    returning id into v_id;
  end if;
  for v_user in
    select distinct s.user_id
    from public.passport_stamps s
    where s.venue_id = p_venue_id
  loop
    perform private.passport_sync_user(v_user);
  end loop;
  return v_id;
end;
$$;

create or replace function public.my_passport_desk(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.owns_venue(p_venue_id) and not private.is_admin_aal2() then
    raise exception 'not owner' using errcode = '42501';
  end if;
  return pg_catalog.jsonb_build_object(
    'enabled', public.passport_program_enabled(),
    'gifts', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', g.id,
        'room_id', g.room_id,
        'room_name', r.name,
        'trigger_kind', g.trigger_kind,
        'title', g.title,
        'details', g.details,
        'active', g.active
      ) order by g.created_at)
      from public.passport_gifts g
      left join public.rooms r on r.id = g.room_id
      where g.venue_id = p_venue_id
    ), '[]'::jsonb),
    'claims', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', c.id,
        'code', c.code,
        'status', c.status,
        'title', g.title,
        'room_name', r.name,
        'player_name', p.display_name,
        'delivered_at', c.delivered_at
      ) order by c.created_at desc)
      from public.passport_gift_claims c
      join public.passport_gifts g on g.id = c.gift_id
      left join public.rooms r on r.id = g.room_id
      left join public.profiles p on p.id = c.user_id
      where g.venue_id = p_venue_id
        and c.status <> 'revoked'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.deliver_passport_gift(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.passport_gift_claims%rowtype;
  v_venue uuid;
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_code := pg_catalog.upper(pg_catalog.btrim(coalesce(p_code, '')));
  select c.* into v_claim
  from public.passport_gift_claims c
  where c.code = v_code
  for update;
  if v_claim.id is null then
    raise exception 'codigo nao encontrado' using errcode = '22023';
  end if;
  select g.venue_id into v_venue
  from public.passport_gifts g
  where g.id = v_claim.gift_id;
  if not private.owns_venue(v_venue) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_claim.status <> 'available' then
    raise exception 'mimo ja tratado' using errcode = '55000';
  end if;
  update public.passport_gift_claims
  set status = 'delivered',
      delivered_at = pg_catalog.now(),
      delivered_by = auth.uid()
  where id = v_claim.id;
  return pg_catalog.jsonb_build_object('id', v_claim.id, 'status', 'delivered');
end;
$$;

create or replace function public.admin_passport_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row public.referral_program_settings%rowtype;
begin
  perform private.admin_require();
  select * into v_row from public.referral_program_settings where id = 1;
  return pg_catalog.jsonb_build_object(
    'passport_enabled', v_row.passport_enabled,
    'passport_rooms_5', v_row.passport_rooms_5,
    'passport_points_5', v_row.passport_points_5,
    'passport_rooms_10', v_row.passport_rooms_10,
    'passport_points_10', v_row.passport_points_10,
    'passport_rooms_25', v_row.passport_rooms_25,
    'passport_points_25', v_row.passport_points_25,
    'passport_house_points', v_row.passport_house_points
  );
end;
$$;

create or replace function public.admin_save_passport_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_row public.referral_program_settings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_was boolean;
  v_key text;
begin
  if p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object' then
    raise exception 'patch invalido' using errcode = '22023';
  end if;
  for v_key in select pg_catalog.jsonb_object_keys(p_patch)
  loop
    if v_key not in (
      'passport_enabled',
      'passport_rooms_5', 'passport_points_5',
      'passport_rooms_10', 'passport_points_10',
      'passport_rooms_25', 'passport_points_25',
      'passport_house_points'
    ) then
      raise exception 'campo % nao editavel', v_key using errcode = '22023';
    end if;
  end loop;
  select * into v_row
  from public.referral_program_settings
  where id = 1
  for update;
  v_before := pg_catalog.to_jsonb(v_row);
  v_was := v_row.passport_enabled;
  if p_patch ? 'passport_enabled' then
    if pg_catalog.jsonb_typeof(p_patch -> 'passport_enabled') <> 'boolean' then
      raise exception 'flag invalida' using errcode = '22023';
    end if;
    v_row.passport_enabled := (p_patch ->> 'passport_enabled')::boolean;
  end if;
  v_row.passport_rooms_5 := private.admin_int(
    p_patch, 'passport_rooms_5', v_row.passport_rooms_5, 1, 1000000
  );
  v_row.passport_points_5 := private.admin_int(
    p_patch, 'passport_points_5', v_row.passport_points_5, 0, 100000000
  );
  v_row.passport_rooms_10 := private.admin_int(
    p_patch, 'passport_rooms_10', v_row.passport_rooms_10, 1, 1000000
  );
  v_row.passport_points_10 := private.admin_int(
    p_patch, 'passport_points_10', v_row.passport_points_10, 0, 100000000
  );
  v_row.passport_rooms_25 := private.admin_int(
    p_patch, 'passport_rooms_25', v_row.passport_rooms_25, 1, 1000000
  );
  v_row.passport_points_25 := private.admin_int(
    p_patch, 'passport_points_25', v_row.passport_points_25, 0, 100000000
  );
  v_row.passport_house_points := private.admin_int(
    p_patch, 'passport_house_points', v_row.passport_house_points, 0, 100000000
  );
  if v_row.passport_rooms_10 <= v_row.passport_rooms_5
    or v_row.passport_rooms_25 <= v_row.passport_rooms_10
  then
    raise exception 'os marcos de salas precisam crescer' using errcode = '22023';
  end if;
  update public.referral_program_settings
  set passport_enabled = v_row.passport_enabled,
      passport_rooms_5 = v_row.passport_rooms_5,
      passport_points_5 = v_row.passport_points_5,
      passport_rooms_10 = v_row.passport_rooms_10,
      passport_points_10 = v_row.passport_points_10,
      passport_rooms_25 = v_row.passport_rooms_25,
      passport_points_25 = v_row.passport_points_25,
      passport_house_points = v_row.passport_house_points,
      updated_at = pg_catalog.now()
  where id = 1;
  if v_row.passport_enabled and not v_was then
    perform private.passport_catch_up();
  end if;
  select pg_catalog.to_jsonb(s) into v_after
  from public.referral_program_settings s where s.id = 1;
  insert into public.reward_settings_changes (actor_id, before_state, after_state)
  values (v_uid, v_before, v_after);
  perform private.admin_audit(
    v_uid, 'save_passport_settings', 'referral_program_settings', '1',
    v_before, v_after
  );
  return public.admin_passport_settings();
end;
$$;

create or replace function public.confirm_session_attendance(
  p_group_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_id uuid;
  v_charge uuid;
  v_had boolean;
  v_has boolean;
  v_already boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id;
  if v_group.id is null then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if not private.owns_venue(v_group.venue_id) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'group cancelled' using errcode = 'P0001';
  end if;
  if v_group.starts_at > pg_catalog.now() then
    raise exception 'session not started' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where group_id = p_group_id
    and user_id = p_user_id
    and attendance <> 'cancelled';
  if v_member.id is null then
    raise exception 'not member' using errcode = 'P0002';
  end if;
  if v_member.refund_status is distinct from 'none' then
    raise exception 'reserva estornada' using errcode = 'P0001';
  end if;
  if v_member.payment_status is distinct from 'paid' then
    raise exception 'reserva nao paga' using errcode = 'P0001';
  end if;
  if not exists (
    select 1
    from public.payment_charges c
    where c.group_id = p_group_id
      and c.user_id = p_user_id
      and c.status = 'paid'
      and c.refunded_at is null
  ) then
    raise exception 'reserva nao paga' using errcode = 'P0001';
  end if;

  insert into public.session_checkins (
    venue_id, group_id, user_id, room_id, marked_by
  ) values (
    v_group.venue_id, p_group_id, p_user_id, v_group.room_id, v_uid
  )
  on conflict (group_id, user_id) do nothing
  returning id into v_id;
  v_already := v_id is null;
  if v_already then
    select id into v_id
    from public.session_checkins
    where group_id = p_group_id
      and user_id = p_user_id;
  else
    perform private.admin_audit(
      v_uid,
      'confirm_session_attendance',
      'session_checkins',
      v_id::text,
      null,
      pg_catalog.jsonb_build_object(
        'group_id', p_group_id,
        'user_id', p_user_id,
        'venue_id', v_group.venue_id,
        'room_id', v_group.room_id
      )
    );
  end if;

  select exists (
    select 1
    from public.passport_plays p
    join public.payment_charges c on c.id = p.payment_charge_id
    where c.group_id = p_group_id
      and c.user_id = p_user_id
      and p.reversed_at is null
  ) into v_had;
  for v_charge in
    select c.id
    from public.payment_charges c
    where c.group_id = p_group_id
      and c.user_id = p_user_id
  loop
    perform private.passport_apply_charge(v_charge);
  end loop;
  select exists (
    select 1
    from public.passport_plays p
    join public.payment_charges c on c.id = p.payment_charge_id
    where c.group_id = p_group_id
      and c.user_id = p_user_id
      and p.reversed_at is null
  ) into v_has;

  return pg_catalog.jsonb_build_object(
    'already', v_already,
    'stamped', v_has and not v_had
  );
end;
$$;

revoke all on function private.point_pools(uuid) from public, anon, authenticated, service_role;
revoke all on function private.subsidy_quote(uuid, integer, integer, integer, boolean)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_grant_milestone(uuid, text, integer, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function private.passport_reverse_milestone(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_sync_counts(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_sync_house(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_gift_visible(uuid)
  from public, anon, service_role;
revoke all on function private.passport_claim_owned(uuid)
  from public, anon, service_role;
grant execute on function private.passport_gift_visible(uuid) to authenticated;
grant execute on function private.passport_claim_owned(uuid) to authenticated;
revoke all on function private.passport_gift_code()
  from public, anon, authenticated, service_role;
revoke all on function private.passport_issue_claim(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_sync_gifts(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_sync_user(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_reverse_play(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_bump_stamp(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_apply_charge(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.passport_catch_up()
  from public, anon, authenticated, service_role;
revoke all on function private.passport_on_charge() from public, anon, authenticated;
revoke all on function private.passport_on_member() from public, anon, authenticated;
revoke all on function private.passport_on_group() from public, anon, authenticated;
grant execute on function private.passport_on_charge() to service_role;
grant execute on function private.passport_on_member() to service_role;
grant execute on function private.passport_on_group() to service_role;

revoke all on function public.passport_program_enabled() from public, anon, service_role;
revoke all on function public.my_passport() from public, anon, service_role;
revoke all on function public.save_passport_gift(uuid, uuid, text, text, text, boolean, uuid)
  from public, anon, service_role;
revoke all on function public.my_passport_desk(uuid) from public, anon, service_role;
revoke all on function public.deliver_passport_gift(text) from public, anon, service_role;
revoke all on function public.admin_passport_settings() from public, anon, service_role;
revoke all on function public.admin_save_passport_settings(jsonb)
  from public, anon, service_role;
revoke all on function public.confirm_session_attendance(uuid, uuid)
  from public, anon, service_role;

grant execute on function public.passport_program_enabled() to authenticated;
grant execute on function public.my_passport() to authenticated;
grant execute on function public.save_passport_gift(uuid, uuid, text, text, text, boolean, uuid)
  to authenticated;
grant execute on function public.my_passport_desk(uuid) to authenticated;
grant execute on function public.deliver_passport_gift(text) to authenticated;
grant execute on function public.admin_passport_settings() to authenticated;
grant execute on function public.admin_save_passport_settings(jsonb) to authenticated;
grant execute on function public.confirm_session_attendance(uuid, uuid) to authenticated;
