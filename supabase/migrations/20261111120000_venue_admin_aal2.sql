-- Admin sem aal2 não cancela sessão nem grupo de casa que não é dele.
-- O dono (venues.owner_id) segue em aal1: o Parceiro não pede o segundo
-- fator. Quem não é dono passa por private.admin_require(), o mesmo
-- portão do console: admin e aal2, senão 'mfa obrigatorio'. Quem não é
-- admin continua recebendo 'not owner'.
--
-- As policies de room_sessions não chamam admin_require. O EXECUTE
-- está revogado para anon e authenticated, e a função levanta exceção:
-- um SELECT de horário cancelado derrubaria a leitura inteira.
-- private.is_admin_aal2() devolve o mesmo critério (admin e aal2) em
-- boolean. O dono continua no ramo owns_venue, sem olhar o aal.
--
-- venue_is_visible segue com private.is_admin() sem aal. Horário
-- aberto de casa aprovada continua público. O aal2 entra só no ramo
-- que alarga a policy: insert em casa alheia e leitura de horário
-- já cancelado. Mudar venue_is_visible esconderia casa não aprovada
-- do admin aal1 no app inteiro, fora deste ajuste.

create or replace function private.is_admin_aal2()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin()
    and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

comment on function private.is_admin_aal2() is
  'Admin com sessão aal2. O mesmo critério de private.admin_require(), em boolean, para policy.';

revoke all on function private.is_admin_aal2() from public;
grant execute on function private.is_admin_aal2()
  to anon, authenticated, service_role;

create or replace function private.admin_require()
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
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  -- private.is_admin() não olha o aal: a casa e o jogador seguem
  -- com a sessão comum. O console e o ramo admin das policies de
  -- room_sessions exigem aal2, via private.is_admin_aal2().
  if not private.is_admin_aal2() then
    raise exception 'mfa obrigatorio' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

revoke all on function private.admin_require()
  from public, anon, authenticated, service_role;

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

  perform 1
  from public.groups g
  where g.session_id = v_session.id
    and g.cancelled_at is null
  for update;

  perform 1
  from public.payment_charges c
  where c.group_id in (
    select g.id
    from public.groups g
    where g.session_id = v_session.id
      and g.cancelled_at is null
  )
  for update;

  if exists (
    select 1
    from public.groups g
    where g.session_id = v_session.id
      and g.cancelled_at is null
      and (
        exists (
          select 1
          from public.group_members m
          where m.group_id = g.id
            and m.attendance <> 'cancelled'
            and m.payment_status in ('pending', 'reserved', 'paid')
        )
        or exists (
          select 1
          from public.payment_charges c
          where c.group_id = g.id
            and c.status in ('creating', 'pending', 'authorized', 'paid')
        )
      )
  ) then
    raise exception 'Esse horário já tem reserva' using errcode = 'P0001';
  end if;

  update public.groups
    set cancelled_at = pg_catalog.now(),
        cancel_reason = 'Horário removido pela casa'
  where session_id = v_session.id
    and cancelled_at is null;

  update public.room_sessions
    set cancelled_at = pg_catalog.now()
  where id = v_session.id
    and cancelled_at is null;
end;
$$;

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
  if not private.owns_venue(v_group.venue_id) then
    if not private.is_admin() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    perform private.admin_require();
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

drop policy if exists room_sessions_insert on public.room_sessions;
create policy room_sessions_insert on public.room_sessions
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.rooms r
      where r.id = room_sessions.room_id
        and (
          private.owns_venue(r.venue_id)
          or private.is_admin_aal2()
        )
    )
  );

drop policy if exists room_sessions_select on public.room_sessions;
create policy room_sessions_select on public.room_sessions
  for select to anon, authenticated
  using (
    exists (
      select 1
      from public.rooms r
      where r.id = room_sessions.room_id
        and private.venue_is_visible(r.venue_id)
        and (
          room_sessions.cancelled_at is null
          or private.owns_venue(r.venue_id)
          or private.is_admin_aal2()
        )
    )
  );
