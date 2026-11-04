-- A casa cancela o grupo dela. O dono do grupo continua com delete_group.
-- Não aplicada neste ambiente: rode no projeto quando for usar o botão.

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
          when payment_status = 'paid' then 'refunded'
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
end;
$$;

revoke all on function public.house_cancel_group(uuid, text) from public, anon;
grant execute on function public.house_cancel_group(uuid, text) to authenticated, service_role;
