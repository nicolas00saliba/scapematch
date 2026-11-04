-- delete_group já aplicada marcava refunded sem falar com o Asaas.
-- Esta função substitui a de 20261104120300_group_functions.sql.
-- refunded e refunded_at só entram pelo webhook PAYMENT_REFUNDED
-- ou pela resposta de sucesso da API, na Edge Function.
-- Não aplicada no projeto remoto.

create or replace function public.delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_group public.groups%rowtype;
  v_member record;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;
  if v_group.created_by is distinct from v_user then
    raise exception 'not creator' using errcode = '42501';
  end if;
  if v_group.cancelled_at is not null then
    raise exception 'already cancelled' using errcode = 'P0001';
  end if;
  if now() > v_group.starts_at - interval '2 hours' then
    raise exception 'too close to delete' using errcode = 'P0001';
  end if;

  update public.groups
    set cancelled_at = now(), cancel_reason = 'organizer'
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
      'O organizador cancelou a sessão. Se você pagou, o estorno está em andamento.',
      p_group_id,
      'delete-group-' || p_group_id::text
    );
  end loop;
end;
$$;

revoke all on function public.delete_group(uuid) from public, anon;
grant execute on function public.delete_group(uuid) to authenticated, service_role;

revoke truncate, references, trigger on public.venues, public.profiles from anon, authenticated;
revoke insert, update, delete on public.venues from anon;
