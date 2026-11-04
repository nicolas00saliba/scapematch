-- A casa cancela o grupo dela. O dono do grupo continua com delete_group.
-- Não marca refunded: o dinheiro só muda depois do estorno no Asaas.
-- O botão chama a Edge Function cancel-house-group, que usa esta função
-- e então estorna o Pix ou cancela a autorização do cartão.
-- Não aplicada neste ambiente.

do $$
declare
  v_name text;
begin
  select con.conname
    into v_name
  from pg_constraint con
  where con.conrelid = 'public.group_members'::regclass
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) ilike '%refund_status%';
  if v_name is not null then
    execute format('alter table public.group_members drop constraint %I', v_name);
  end if;
end $$;

alter table public.group_members
  add constraint group_members_refund_status_check
  check (refund_status in ('none', 'pending', 'refunded', 'denied'));

create or replace function public.house_cancel_group(
  p_group_id uuid,
  p_reason text default 'Cancelada pela casa'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_reason text;
  v_member record;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if not (public.owns_venue(v_group.venue_id) or public.is_admin()) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'already cancelled' using errcode = 'P0001';
  end if;
  if now() > v_group.starts_at - interval '2 hours' then
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
    set cancelled_at = now(), cancel_reason = v_reason
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
      set cancelled_at = now()
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
    perform public.post_app_notice(
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

revoke all on function public.house_cancel_group(uuid, text) from public, anon;
grant execute on function public.house_cancel_group(uuid, text) to authenticated, service_role;
