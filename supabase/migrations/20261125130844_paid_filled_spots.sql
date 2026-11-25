-- A vaga ocupada é a mesma da lista pública: pagamento paid ou
-- reserved (custódia HELD). Quem só entrou, no modelo antigo, não ocupa.
-- Dois pagamentos da última vaga travam a linha do grupo. O segundo
-- já cobrado vai para a fila de estorno e sai do grupo.
-- Versão 20261125151000 para não repetir 20261125150000 da auditoria
-- de recompensas. Não redefine player_payable_cents, quote_redemption
-- nem create-charge. Não aplicado no remoto.

create or replace function private.group_filled_spots(p_group_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.group_members
  where group_id = p_group_id
    and attendance <> 'cancelled'
    and payment_status in ('paid', 'reserved');
$$;

comment on function private.group_filled_spots(uuid) is
  'Vagas ocupadas: presença não cancelada e pagamento paid ou reserved. Igual à lista pública.';

-- A view foi criada antes de team_name. create or replace não pode
-- mudar a ordem das colunas, então a lista continua a de então.
create or replace view public.groups_with_counts
with (security_invoker = true) as
select
  g.id,
  g.city_id,
  g.venue_id,
  g.room_id,
  g.session_id,
  g.starts_at,
  g.total_spots,
  g.minimum_spots,
  g.price_cents,
  g.price_mode,
  g.note,
  g.cancel_window_minutes,
  g.created_by,
  g.created_at,
  g.cancelled_at,
  g.cancel_reason,
  g.closed_at,
  g.closes_at,
  g.confirmed_at,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance <> 'cancelled'
      and m.payment_status in ('paid', 'reserved')
  ) as filled_spots,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance = 'confirmed'
  ) as confirmed_count
from public.groups g;

grant select on public.groups_with_counts to anon, authenticated, service_role;

drop trigger if exists group_members_sync_bounds on public.group_members;
create trigger group_members_sync_bounds
  after insert or delete or update of attendance, payment_status
  on public.group_members
  for each row
  execute function private.sync_bounds_from_member();

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
  v_current_payment text;
  v_member_id uuid;
  v_total integer;
  v_others integer;
  v_queued boolean := false;
  v_updated integer;
begin
  select total_spots
    into v_total
  from public.groups
  where id = p_charge.group_id
  for update;

  if v_total is null then
    raise exception 'group not found' using errcode = 'P0002';
  end if;

  select id, attendance, refund_status, refund_reason, payment_status
    into v_member_id, v_attendance, v_current_refund, v_reason, v_current_payment
  from public.group_members
  where group_id = p_charge.group_id
    and user_id = p_charge.user_id
  for update;

  if v_member_id is null then
    raise exception 'member_missing' using errcode = 'P0002';
  end if;

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

    if v_payment in ('paid', 'reserved')
      and v_attendance is distinct from 'cancelled'
      and v_current_payment not in ('paid', 'reserved')
    then
      select count(*)::integer
        into v_others
      from public.group_members
      where group_id = p_charge.group_id
        and user_id <> p_charge.user_id
        and attendance <> 'cancelled'
        and payment_status in ('paid', 'reserved');
      if v_others >= v_total then
        v_queued := private.enqueue_member_refund(
          p_charge.group_id, p_charge.user_id, v_member_id
        );
        update public.group_members
        set
          attendance = 'cancelled',
          payment_status = v_payment,
          refund_status = case
            when v_payment = 'paid' or v_queued then 'refund_pending'
            else 'none'
          end,
          refund_reason = 'group_did_not_close'
        where id = v_member_id;
        return;
      end if;
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
  where id = v_member_id;
  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'member_missing' using errcode = 'P0002';
  end if;
end;
$$;
