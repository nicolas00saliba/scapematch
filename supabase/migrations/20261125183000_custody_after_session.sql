-- A custódia HELD só pode ser liberada quando a sessão já começou.
-- Captura e confirmação do grupo não mudam. Cancelada ou estornada não libera.
-- O saldo da conta PJ alerta abaixo de platform_settings.low_balance_alert_cents.

alter table public.platform_settings
  add column if not exists low_balance_alert_cents integer not null default 100000
    check (low_balance_alert_cents >= 0);

comment on column public.platform_settings.low_balance_alert_cents is
  'Alerta diário quando o saldo disponível da conta PJ fica abaixo deste valor, em centavos. Padrão 100000 (R$ 1.000). O Admin não tem tela para este campo.';

create or replace function public.custody_release_due(
  p_charge_id uuid,
  p_now timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_group public.groups%rowtype;
  v_session public.room_sessions%rowtype;
  v_starts timestamptz;
  v_filled integer;
  v_confirmed boolean;
begin
  if p_charge_id is null or p_now is null then
    return false;
  end if;

  select * into v_charge
  from public.payment_charges
  where id = p_charge_id;

  if not found then
    return false;
  end if;

  if v_charge.status is distinct from 'paid'
    or v_charge.custody_released_at is not null
    or v_charge.refund_requested_at is not null
    or v_charge.provider_split_id is null
    or pg_catalog.btrim(v_charge.provider_split_id) = ''
    or coalesce(v_charge.custody_release_attempts, 0) >= 8
  then
    return false;
  end if;

  select * into v_group
  from public.groups
  where id = v_charge.group_id;

  if not found or v_group.cancelled_at is not null then
    return false;
  end if;

  v_starts := v_group.starts_at;
  if v_group.session_id is not null then
    select * into v_session
    from public.room_sessions
    where id = v_group.session_id;
    if found then
      if v_session.cancelled_at is not null then
        return false;
      end if;
      if v_session.starts_at is not null then
        v_starts := v_session.starts_at;
      end if;
    end if;
  end if;

  if v_starts is null or p_now < v_starts then
    return false;
  end if;

  select count(*)::integer into v_filled
  from public.group_members m
  where m.group_id = v_group.id
    and m.attendance <> 'cancelled';

  v_confirmed := v_group.confirmed_at is not null
    or v_group.closed_at is not null
    or (
      (v_group.closes_at is null or v_group.closes_at > p_now)
      and v_filled >= v_group.minimum_spots
    );

  return v_confirmed;
end;
$$;

comment on function public.custody_release_due(uuid, timestamptz) is
  'True quando a cobrança paga pode soltar a custódia: sessão já começou, grupo confirmado, nem grupo nem sessão cancelados, sem estorno pedido. A PagBank ainda libera sozinha em 90 dias se ninguém chamar o release.';

revoke all on function public.custody_release_due(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.custody_release_due(uuid, timestamptz)
  to service_role;

create or replace function public.list_due_custody_releases(
  p_limit integer default 40,
  p_now timestamptz default pg_catalog.now()
)
returns table (
  id uuid,
  group_id uuid,
  venue_id uuid,
  provider_split_id text,
  custody_release_attempts integer,
  refund_requested_at timestamptz,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    c.group_id,
    c.venue_id,
    c.provider_split_id,
    c.custody_release_attempts,
    c.refund_requested_at,
    c.status
  from public.payment_charges c
  where public.custody_release_due(c.id, p_now)
  order by c.created_at
  limit least(greatest(coalesce(p_limit, 40), 1), 40);
$$;

comment on function public.list_due_custody_releases(integer, timestamptz) is
  'Cobranças cuja custódia o cron pode soltar agora. No máximo 40, da mais antiga.';

revoke all on function public.list_due_custody_releases(integer, timestamptz)
  from public, anon, authenticated;
grant execute on function public.list_due_custody_releases(integer, timestamptz)
  to service_role;

create or replace function public.low_balance_alert_cents()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select s.low_balance_alert_cents from public.platform_settings s where s.id = 1),
    100000
  );
$$;

comment on function public.low_balance_alert_cents() is
  'Limite do alerta de saldo da conta PJ, em centavos.';

revoke all on function public.low_balance_alert_cents()
  from public, anon, authenticated;
grant execute on function public.low_balance_alert_cents()
  to service_role;

create or replace function public.pj_balance_alert_due(p_available_cents bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_available_cents is not null
    and p_available_cents >= 0
    and p_available_cents < public.low_balance_alert_cents();
$$;

comment on function public.pj_balance_alert_due(bigint) is
  'True quando o saldo disponível da conta PJ está abaixo do limite. No limite, não alerta.';

revoke all on function public.pj_balance_alert_due(bigint)
  from public, anon, authenticated;
grant execute on function public.pj_balance_alert_due(bigint)
  to service_role;
