-- A casa tira um horário da grade sem apagar a linha.
-- room_sessions.cancelled_at já existe: a busca, a sala e a reserva
-- ignoram horário com essa data, e create_group recusa a sessão.
-- Apagar a linha quebraria groups.session_id, o histórico, o fomento
-- e os pontos. Quem remove é o dono da casa (venues.owner_id) ou um
-- admin. Não há papel separado de membro da casa.
-- Horário com reserva ativa (membro ainda sentado, pagamento pendente,
-- reservado ou pago) ou com cobrança em andamento não sai da grade.

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

  if not (private.owns_venue(v_venue) or private.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
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

revoke all on function public.remove_room_session(uuid) from public, anon;
grant execute on function public.remove_room_session(uuid) to authenticated;

-- O cliente não apaga nem desliga o horário na mão. Insert continua
-- com o dono, para o botão Novo horário. O delete direto, mesmo da
-- service role, para enquanto a sala existe. O cascade da sala segue:
-- nesse momento a sala já não está na tabela.

create or replace function private.room_sessions_block_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.rooms where id = old.room_id) then
    raise exception 'use remove_room_session' using errcode = '42501';
  end if;
  return old;
end;
$$;

revoke all on function private.room_sessions_block_delete()
  from public, anon, authenticated;

drop trigger if exists room_sessions_block_delete on public.room_sessions;
create trigger room_sessions_block_delete
  before delete on public.room_sessions
  for each row execute function private.room_sessions_block_delete();

drop policy if exists room_sessions_write on public.room_sessions;
drop policy if exists room_sessions_insert on public.room_sessions;
create policy room_sessions_insert on public.room_sessions
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.rooms r
      where r.id = room_sessions.room_id
        and (private.owns_venue(r.venue_id) or private.is_admin())
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
          or private.is_admin()
        )
    )
  );

revoke update, delete on table public.room_sessions from anon, authenticated;
