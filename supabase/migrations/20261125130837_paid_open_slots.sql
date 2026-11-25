-- Reserva com menos de 1 h entra. O horário some só quando as vagas
-- pagas enchem o máximo do host. Sessão com hora já está publicada
-- (proposed não é rascunho). A casa que apaga um horário com gente
-- paga estorna todo mundo. Não aplicado no remoto.
--
-- Não mexe em preço, desconto, pontos, indicação nem em
-- post_referral_rewards, subsidy_quote, quote_redemption ou
-- player_payable_cents. Corre depois da auditoria 20261125120937.

create or replace function public.app_time_zone()
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select 'America/Sao_Paulo'::text;
$$;

comment on function public.app_time_zone() is
  'Fuso do calendário. Hoje só Curitiba. Uma configuração futura da pessoa troca este retorno.';

revoke all on function public.app_time_zone() from public;
grant execute on function public.app_time_zone()
  to anon, authenticated, service_role;

drop function if exists public.venue_open_days(uuid);
drop function if exists public.venue_open_slots(uuid);

create or replace function public.venue_open_slots(p_venue_id uuid)
returns table (
  session_id uuid,
  room_id uuid,
  room_name text,
  starts_at timestamptz,
  day date,
  starts_hm text,
  near_start boolean,
  group_id uuid,
  spots_left integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    s.id,
    r.id,
    r.name,
    s.starts_at,
    (s.starts_at at time zone public.app_time_zone())::date,
    pg_catalog.to_char(
      s.starts_at at time zone public.app_time_zone(),
      'HH24:MI'
    ),
    s.starts_at <= pg_catalog.now() + interval '1 hour',
    open_group.id,
    case
      when open_group.id is null then null
      else open_group.total_spots - open_group.paid_spots
    end
  from public.room_sessions s
  join public.rooms r on r.id = s.room_id
  left join lateral (
    select
      g.id,
      g.total_spots,
      (
        select count(*)::integer
        from public.group_members m
        where m.group_id = g.id
          and m.attendance <> 'cancelled'
          and m.payment_status in ('paid', 'reserved')
      ) as paid_spots
    from public.groups g
    where g.cancelled_at is null
      and (
        g.session_id = s.id
        or (g.room_id = s.room_id and g.starts_at = s.starts_at)
      )
    limit 1
  ) open_group on true
  where r.venue_id = p_venue_id
    and s.cancelled_at is null
    and s.starts_at is not null
    and s.starts_at > pg_catalog.now()
    and (
      open_group.id is null
      or open_group.paid_spots < open_group.total_spots
    )
  order by 3, s.starts_at;
$$;

comment on function public.venue_open_slots(uuid) is
  'Horários ainda reserváveis. Dia em app_time_zone(). Inclui a última hora (near_start). Some só com as vagas pagas cheias. proposed com hora entra igual à grade.';

create or replace function public.venue_open_days(p_venue_id uuid)
returns table (day date)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct s.day
  from public.venue_open_slots(p_venue_id) s
  order by s.day;
$$;

comment on function public.venue_open_days(uuid) is
  'Dias em que a casa tem pelo menos um horário com vaga paga.';

revoke all on function public.venue_open_slots(uuid) from public;
revoke all on function public.venue_open_days(uuid) from public;
grant execute on function public.venue_open_slots(uuid)
  to anon, authenticated, service_role;
grant execute on function public.venue_open_days(uuid)
  to anon, authenticated, service_role;

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
  elsif v_session.starts_at - interval '1 hour' > pg_catalog.now() then
    v_closes := v_session.starts_at - interval '1 hour';
  else
    v_closes := v_session.starts_at;
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

create or replace function public.confirm_attendance(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_room public.rooms%rowtype;
  v_payment text;
  v_attendance text;
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
  if v_group.starts_at + make_interval(mins => v_room.duration_minutes) <= pg_catalog.now() then
    raise exception 'session ended' using errcode = 'P0001';
  end if;

  select attendance, payment_status
    into v_attendance, v_payment
  from public.group_members
  where group_id = p_group_id
    and user_id = v_user
    and attendance <> 'cancelled';
  if not found then
    raise exception 'not member' using errcode = 'P0002';
  end if;
  if v_attendance = 'confirmed' then
    return;
  end if;
  if v_payment not in ('paid', 'reserved') then
    raise exception 'payment required' using errcode = 'P0001';
  end if;

  update public.group_members
    set attendance = 'confirmed'
    where group_id = p_group_id
      and user_id = v_user
      and attendance = 'joined';
end;
$$;

create or replace function private.sync_charge_member(
  p_charge public.payment_charges
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment text;
  v_refund text;
  v_reason text;
  v_attendance text;
  v_current_refund text;
  v_updated integer;
begin
  select attendance, refund_status, refund_reason
    into v_attendance, v_current_refund, v_reason
  from public.group_members
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id
  for update;

  if v_attendance = 'cancelled'
    and v_current_refund in ('refund_pending', 'pending', 'denied', 'refunded')
  then
    v_payment := case p_charge.status
      when 'paid' then 'paid'
      when 'authorized' then 'reserved'
      when 'refunded' then 'released'
      when 'cancelled' then 'released'
      when 'failed' then 'released'
      else 'pending'
    end;
    v_refund := case
      when p_charge.status = 'refunded' then 'refunded'
      when p_charge.status = 'cancelled'
        and v_current_refund in ('refund_pending', 'pending') then 'refunded'
      else v_current_refund
    end;
    if v_reason is null or v_reason = 'none' then
      v_reason := case
        when v_refund = 'refunded' then 'group_did_not_close'
        else 'hold_released'
      end;
    end if;
  else
    v_payment := case p_charge.status
      when 'paid' then 'paid'
      when 'authorized' then 'reserved'
      when 'refunded' then 'released'
      when 'cancelled' then 'released'
      when 'failed' then 'released'
      else 'pending'
    end;
    v_refund := case
      when p_charge.status = 'refunded' then 'refunded'
      else 'none'
    end;
    if p_charge.status = 'refunded' then
      if v_reason is null or v_reason = 'none' then
        v_reason := 'group_did_not_close';
      end if;
    elsif p_charge.status = 'cancelled' or p_charge.status = 'failed' then
      if v_reason is null or v_reason = 'none' then
        v_reason := 'hold_released';
      end if;
    else
      v_reason := 'none';
    end if;
  end if;

  update public.group_members
  set
    payment_status = v_payment,
    refund_status = v_refund,
    refund_reason = v_reason,
    attendance = case
      when attendance = 'joined' and v_payment in ('paid', 'reserved')
        then 'confirmed'
      else attendance
    end
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'member_missing' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.remove_room_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_venue uuid;
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_queued boolean;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;

  select room.venue_id
    into v_venue
  from public.rooms room
  where room.id = v_session.room_id;

  if v_venue is null then
    raise exception 'unknown session' using errcode = 'P0002';
  end if;

  if not private.owns_venue(v_venue) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
  end if;

  if v_session.cancelled_at is not null then
    return;
  end if;

  for v_group in
    select *
    from public.groups
    where session_id = v_session.id
      and cancelled_at is null
    for update
  loop
    update public.groups
      set cancelled_at = pg_catalog.now(),
          cancel_reason = 'Horário removido pela casa'
      where id = v_group.id;

    for v_member in
      select *
      from public.group_members
      where group_id = v_group.id
        and attendance <> 'cancelled'
      for update
    loop
      v_queued := private.enqueue_member_refund(
        v_group.id, v_member.user_id, v_member.id
      );
      update public.group_members
        set attendance = 'cancelled',
            refund_status = case
              when payment_status = 'paid' or v_queued then 'refund_pending'
              else 'none'
            end,
            refund_reason = case
              when payment_status = 'paid' or v_queued then 'organizer_cancelled_event'
              else 'hold_released'
            end,
            payment_status = case
              when payment_status = 'paid' then payment_status
              when v_queued then payment_status
              else 'released'
            end
        where id = v_member.id;

      perform private.post_app_notice(
        v_member.user_id,
        'group_cancelled',
        'Sessão cancelada',
        'A casa cancelou a sessão. Se você pagou, o estorno integral está em andamento.',
        v_group.id,
        'session-removed-' || v_session.id::text || '-' || v_member.user_id::text
      );
    end loop;
  end loop;

  update public.room_sessions
    set cancelled_at = pg_catalog.now()
  where id = v_session.id
    and cancelled_at is null;
end;
$$;
