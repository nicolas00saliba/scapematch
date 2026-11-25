-- Admin: salas, sessões, grupos e reservas.
-- Excluir sessão ou cancelar grupo com jogador pago pede reembolso
-- integral pela fila private.enqueue_member_refund, motivo
-- organizer_cancelled_event. Não chama a PagBank daqui.
-- Não aplicada no remoto.

create or replace function private.admin_queue_member_refund(
  p_group_id uuid,
  p_member_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.group_members%rowtype;
  v_queued boolean;
begin
  if p_reason not in ('organizer_cancelled_event', 'organizer_removed_member') then
    raise exception 'motivo invalido' using errcode = '22023';
  end if;
  select * into v_member
  from public.group_members
  where id = p_member_id
    and group_id = p_group_id
    and attendance <> 'cancelled'
  for update;
  if not found then
    return false;
  end if;
  v_queued := private.enqueue_member_refund(
    p_group_id, v_member.user_id, v_member.id
  );
  update public.group_members
  set attendance = 'cancelled',
      refund_status = case
        when v_queued then 'refund_pending'
        when payment_status = 'paid' then 'refunded'
        else 'none'
      end,
      refund_reason = case
        when payment_status = 'paid' or v_queued then p_reason
        else 'hold_released'
      end,
      payment_status = case
        when payment_status = 'paid' then payment_status
        when v_queued then payment_status
        else 'released'
      end
  where id = v_member.id;
  return v_queued;
end;
$$;

revoke all on function private.admin_queue_member_refund(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.admin_page_limit(p_limit integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select least(greatest(coalesce(p_limit, 40), 1), 100);
$$;

revoke all on function private.admin_page_limit(integer)
  from public, anon, authenticated;

create or replace function public.admin_list_rooms(
  p_venue_id uuid default null,
  p_query text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb;
  v_total integer;
begin
  perform private.admin_require();
  select count(*)::integer into v_total
  from public.rooms r
  join public.venues v on v.id = r.venue_id
  where (p_venue_id is null or r.venue_id = p_venue_id)
    and (p_include_test or not v.is_test)
    and (
      v_blank
      or r.name ilike v_like
      or v.name ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.venue_name, s.name), '[]'::jsonb)
    into v_rows
  from (
    select
      r.id,
      r.venue_id,
      v.name as venue_name,
      v.is_test as venue_is_test,
      r.name,
      r.capacity,
      r.minimum_players,
      r.price_cents
    from public.rooms r
    join public.venues v on v.id = r.venue_id
    where (p_venue_id is null or r.venue_id = p_venue_id)
      and (p_include_test or not v.is_test)
      and (
        v_blank
        or r.name ilike v_like
        or v.name ilike v_like
      )
    order by v.name, r.name
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_list_sessions(
  p_venue_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_status text default null,
  p_query text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb;
  v_total integer;
begin
  perform private.admin_require();
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;
  if v_status is not null and v_status not in ('open', 'cancelled') then
    raise exception 'status invalido' using errcode = '22023';
  end if;

  select count(*)::integer into v_total
  from public.room_sessions s
  join public.rooms r on r.id = s.room_id
  join public.venues v on v.id = r.venue_id
  where (p_venue_id is null or r.venue_id = p_venue_id)
    and (p_include_test or not v.is_test)
    and (p_from is null or s.starts_at >= p_from)
    and (p_to is null or s.starts_at < p_to)
    and (
      v_status is null
      or (v_status = 'open' and s.cancelled_at is null)
      or (v_status = 'cancelled' and s.cancelled_at is not null)
    )
    and (
      v_blank
      or r.name ilike v_like
      or v.name ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.starts_at desc nulls last), '[]'::jsonb)
    into v_rows
  from (
    select
      s.id,
      r.venue_id,
      v.name as venue_name,
      v.is_test as venue_is_test,
      r.id as room_id,
      r.name as room_name,
      s.starts_at,
      s.cancelled_at,
      s.cancelled_at is not null as cancelled,
      (
        select count(*)::integer
        from public.groups g
        where g.session_id = s.id and g.cancelled_at is null
      ) as open_groups,
      (
        select count(*)::integer
        from public.group_members m
        join public.groups g on g.id = m.group_id
        where g.session_id = s.id
          and g.cancelled_at is null
          and m.attendance <> 'cancelled'
          and m.payment_status = 'paid'
      ) as paid_members
    from public.room_sessions s
    join public.rooms r on r.id = s.room_id
    join public.venues v on v.id = r.venue_id
    where (p_venue_id is null or r.venue_id = p_venue_id)
      and (p_include_test or not v.is_test)
      and (p_from is null or s.starts_at >= p_from)
      and (p_to is null or s.starts_at < p_to)
      and (
        v_status is null
        or (v_status = 'open' and s.cancelled_at is null)
        or (v_status = 'cancelled' and s.cancelled_at is not null)
      )
      and (
        v_blank
        or r.name ilike v_like
        or v.name ilike v_like
      )
    order by s.starts_at desc nulls last
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_list_groups(
  p_venue_id uuid default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_status text default null,
  p_query text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb;
  v_total integer;
begin
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;
  perform private.admin_require();
  if v_status is not null and v_status not in ('open', 'closed', 'cancelled') then
    raise exception 'status invalido' using errcode = '22023';
  end if;

  select count(*)::integer into v_total
  from public.groups g
  join public.venues v on v.id = g.venue_id
  join public.rooms r on r.id = g.room_id
  where (p_venue_id is null or g.venue_id = p_venue_id)
    and (p_include_test or not v.is_test)
    and (p_from is null or g.starts_at >= p_from)
    and (p_to is null or g.starts_at < p_to)
    and (
      v_status is null
      or (v_status = 'cancelled' and g.cancelled_at is not null)
      or (v_status = 'closed' and g.cancelled_at is null and g.closed_at is not null)
      or (v_status = 'open' and g.cancelled_at is null and g.closed_at is null)
    )
    and (
      v_blank
      or v.name ilike v_like
      or r.name ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.starts_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      g.id,
      g.venue_id,
      v.name as venue_name,
      v.is_test as venue_is_test,
      g.room_id,
      r.name as room_name,
      g.session_id,
      g.starts_at,
      case
        when g.cancelled_at is not null then 'cancelled'
        when g.closed_at is not null then 'closed'
        else 'open'
      end as status,
      g.total_spots,
      private.group_filled_spots(g.id) as filled_spots,
      g.created_by as host_user_id,
      coalesce(host.display_name, 'Host') as host_name
    from public.groups g
    join public.venues v on v.id = g.venue_id
    join public.rooms r on r.id = g.room_id
    left join public.profiles host on host.id = g.created_by
    where (p_venue_id is null or g.venue_id = p_venue_id)
      and (p_include_test or not v.is_test)
      and (p_from is null or g.starts_at >= p_from)
      and (p_to is null or g.starts_at < p_to)
      and (
        v_status is null
        or (v_status = 'cancelled' and g.cancelled_at is not null)
        or (v_status = 'closed' and g.cancelled_at is null and g.closed_at is not null)
        or (v_status = 'open' and g.cancelled_at is null and g.closed_at is null)
      )
      and (
        v_blank
        or v.name ilike v_like
        or r.name ilike v_like
      )
    order by g.starts_at desc
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_group(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group public.groups%rowtype;
  v_room_name text;
  v_venue_name text;
  v_host text;
  v_members jsonb;
begin
  perform private.admin_require();
  select * into v_group from public.groups where id = p_group_id;
  if not found then
    raise exception 'grupo nao encontrado' using errcode = 'P0002';
  end if;
  select r.name, v.name into v_room_name, v_venue_name
  from public.rooms r
  join public.venues v on v.id = r.venue_id
  where r.id = v_group.room_id;
  select display_name into v_host
  from public.profiles where id = v_group.created_by;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.is_creator desc, s.display_name), '[]'::jsonb)
    into v_members
  from (
    select
      m.id,
      m.user_id,
      m.display_name,
      m.is_creator,
      m.attendance,
      m.payment_status,
      m.refund_status,
      m.refund_reason,
      c.id as charge_id,
      c.status as charge_status,
      c.amount_cents,
      c.charged_amount_cents,
      c.billing_type,
      c.subsidy_cents,
      c.points_redeemed,
      c.first_booking_discount_cents,
      c.buyer_interest_cents,
      c.house_fixed_cents,
      case
        when c.custody_released_at is not null then 'liberada'
        when c.custody_release_failed_at is not null then 'falha'
        when c.status = 'paid'
          and c.provider_split_id is not null
          and c.refund_requested_at is null
          then 'HELD'
        else 'sem_custodia'
      end as custody,
      c.custody_release_attempts,
      q.status as refund_queue_status
    from public.group_members m
    left join public.payment_charges c
      on c.group_id = m.group_id and c.user_id = m.user_id
    left join public.member_refund_queue q on q.charge_id = c.id
    where m.group_id = p_group_id
  ) s;

  return pg_catalog.jsonb_build_object(
    'id', v_group.id,
    'venue_id', v_group.venue_id,
    'venue_name', v_venue_name,
    'room_id', v_group.room_id,
    'room_name', v_room_name,
    'session_id', v_group.session_id,
    'starts_at', v_group.starts_at,
    'status', case
      when v_group.cancelled_at is not null then 'cancelled'
      when v_group.closed_at is not null then 'closed'
      else 'open'
    end,
    'cancel_reason', v_group.cancel_reason,
    'total_spots', v_group.total_spots,
    'filled_spots', private.group_filled_spots(v_group.id),
    'host_user_id', v_group.created_by,
    'host_name', coalesce(v_host, 'Host'),
    'members', v_members
  );
end;
$$;

create or replace function public.admin_delete_session(
  p_session_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_session public.room_sessions%rowtype;
  v_group public.groups%rowtype;
  v_member record;
  v_queued integer := 0;
  v_groups integer := 0;
begin
  if p_confirm is distinct from 'EXCLUIR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;
  if not found then
    raise exception 'sessao nao encontrada' using errcode = 'P0002';
  end if;
  if v_session.cancelled_at is not null then
    raise exception 'sessao ja excluida' using errcode = 'P0001';
  end if;

  for v_group in
    select *
    from public.groups
    where session_id = p_session_id
      and cancelled_at is null
    for update
  loop
    v_groups := v_groups + 1;
    for v_member in
      select id, user_id
      from public.group_members
      where group_id = v_group.id
        and attendance <> 'cancelled'
    loop
      if private.admin_queue_member_refund(
        v_group.id, v_member.id, 'organizer_cancelled_event'
      ) then
        v_queued := v_queued + 1;
      end if;
      perform private.post_app_notice(
        v_member.user_id,
        'group_cancelled',
        'Sessão cancelada',
        'O admin cancelou a sessão. Se você pagou, o estorno integral entrou na fila.',
        v_group.id,
        'admin-session-' || p_session_id::text || '-' || v_member.user_id::text
      );
    end loop;
    update public.groups
    set cancelled_at = pg_catalog.now(),
        cancel_reason = 'Sessão excluída pelo admin'
    where id = v_group.id;
  end loop;

  update public.room_sessions
  set cancelled_at = pg_catalog.now()
  where id = p_session_id;

  perform private.admin_audit(
    v_actor,
    'delete_session',
    'room_sessions',
    p_session_id::text,
    pg_catalog.jsonb_build_object('cancelled_at', null),
    pg_catalog.jsonb_build_object(
      'groups', v_groups,
      'refunds_queued', v_queued
    )
  );
  return pg_catalog.jsonb_build_object(
    'session_id', p_session_id,
    'groups', v_groups,
    'refunds_queued', v_queued
  );
end;
$$;

create or replace function public.admin_cancel_group(
  p_group_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_group public.groups%rowtype;
  v_member record;
  v_queued integer := 0;
  v_session uuid;
begin
  if p_confirm is distinct from 'CANCELAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select session_id into v_session from public.groups where id = p_group_id;
  if v_session is not null then
    perform 1 from public.room_sessions where id = v_session for update;
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'grupo nao encontrado' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'grupo ja cancelado' using errcode = 'P0001';
  end if;

  for v_member in
    select id, user_id
    from public.group_members
    where group_id = p_group_id
      and attendance <> 'cancelled'
  loop
    if private.admin_queue_member_refund(
      p_group_id, v_member.id, 'organizer_cancelled_event'
    ) then
      v_queued := v_queued + 1;
    end if;
    perform private.post_app_notice(
      v_member.user_id,
      'group_cancelled',
      'Sessão cancelada',
      'O admin cancelou o grupo. Se você pagou, o estorno integral entrou na fila.',
      p_group_id,
      'admin-group-' || p_group_id::text || '-' || v_member.user_id::text
    );
  end loop;

  update public.groups
  set cancelled_at = pg_catalog.now(),
      cancel_reason = 'Grupo cancelado pelo admin'
  where id = p_group_id;

  perform private.admin_audit(
    v_actor,
    'cancel_group',
    'groups',
    p_group_id::text,
    pg_catalog.jsonb_build_object('cancelled_at', null, 'session_id', v_group.session_id),
    pg_catalog.jsonb_build_object('refunds_queued', v_queued, 'session_kept', true)
  );
  return pg_catalog.jsonb_build_object(
    'group_id', p_group_id,
    'refunds_queued', v_queued,
    'session_id', v_group.session_id
  );
end;
$$;

create or replace function public.admin_remove_group_member(
  p_group_id uuid,
  p_member_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_group public.groups%rowtype;
  v_member public.group_members%rowtype;
  v_queued boolean;
begin
  if p_confirm is distinct from 'REMOVER' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'grupo nao encontrado' using errcode = 'P0002';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'grupo cancelado' using errcode = 'P0001';
  end if;
  select * into v_member
  from public.group_members
  where id = p_member_id and group_id = p_group_id;
  if not found then
    raise exception 'membro nao encontrado' using errcode = 'P0002';
  end if;
  if v_member.attendance = 'cancelled' then
    raise exception 'membro ja saiu' using errcode = 'P0001';
  end if;

  v_queued := private.admin_queue_member_refund(
    p_group_id, p_member_id, 'organizer_removed_member'
  );
  update public.groups
  set closed_at = null
  where id = p_group_id
    and private.group_filled_spots(p_group_id) < total_spots;
  perform private.offer_waitlist(p_group_id);
  perform private.admin_audit(
    v_actor,
    'remove_group_member',
    'group_members',
    p_member_id::text,
    pg_catalog.jsonb_build_object(
      'user_id', v_member.user_id,
      'payment_status', v_member.payment_status
    ),
    pg_catalog.jsonb_build_object(
      'refund_queued', v_queued,
      'reason', 'organizer_removed_member'
    )
  );
  return pg_catalog.jsonb_build_object(
    'member_id', p_member_id,
    'refund_queued', v_queued
  );
end;
$$;

do $$
declare
  v_sig text;
begin
  for v_sig in
    select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'admin_list_rooms',
        'admin_list_sessions',
        'admin_list_groups',
        'admin_group',
        'admin_delete_session',
        'admin_cancel_group',
        'admin_remove_group_member'
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, service_role',
      v_sig
    );
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;
