-- Idempotência da reserva de pontos. Não aplicar no remoto.
-- O claim já grava pending antes do Asaas. Esta migration guarda a data
-- dessa linha, distingue a autorização de evento crítico e permite concluir
-- uma perna que ficou nesse estado quando a transferência virar DONE.

alter table public.point_reserve_transfers
  drop constraint point_reserve_transfers_status_check;

alter table public.point_reserve_transfers
  add constraint point_reserve_transfers_status_check
  check (status in (
    'pending', 'sending', 'awaiting_authorization', 'done', 'failed'
  ));

create or replace function public.claim_points_reserve_transfer(
  p_charge_id uuid,
  p_purpose text,
  p_amount_cents integer,
  p_wallet_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if p_purpose not in (
    'house', 'platform_return', 'cashback_in', 'cashback_out', 'cashback_excess'
  ) then
    raise exception 'finalidade invalida' using errcode = '22023';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or p_wallet_id is null then
    raise exception 'transferencia invalida' using errcode = '22023';
  end if;
  insert into public.point_reserve_transfers (
    payment_charge_id, purpose, amount_cents, destination_wallet_id, status
  ) values (
    p_charge_id, p_purpose, p_amount_cents, p_wallet_id, 'pending'
  )
  on conflict (payment_charge_id, purpose) do nothing;

  select status into v_status
  from public.point_reserve_transfers
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
  for update;
  if v_status = 'done' then
    return 'done';
  end if;
  if v_status in ('sending', 'awaiting_authorization') then
    return 'skip';
  end if;
  update public.point_reserve_transfers
  set status = 'sending',
      amount_cents = p_amount_cents,
      destination_wallet_id = p_wallet_id
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status in ('pending', 'failed');
  return 'send';
end;
$$;

create or replace function public.complete_points_reserve_transfer(
  p_charge_id uuid,
  p_purpose text,
  p_provider_ref text,
  p_ok boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.point_reserve_transfers
  set status = case when p_ok then 'done' else 'failed' end,
      provider_ref = coalesce(p_provider_ref, provider_ref)
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status in ('sending', 'awaiting_authorization');
end;
$$;

create or replace function public.points_reserve_transfer_anchor(
  p_charge_id uuid,
  p_purpose text
)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (created_at at time zone 'America/Sao_Paulo')::date
  from public.point_reserve_transfers
  where payment_charge_id = p_charge_id
    and purpose = p_purpose;
$$;

create or replace function public.note_points_reserve_awaiting(
  p_charge_id uuid,
  p_purpose text,
  p_provider_ref text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_provider_ref is null or length(p_provider_ref) = 0 then
    return;
  end if;
  update public.point_reserve_transfers
  set status = 'awaiting_authorization',
      provider_ref = p_provider_ref
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status in ('sending', 'awaiting_authorization');
end;
$$;

create or replace function public.remember_points_reserve_transfer(
  p_charge_id uuid,
  p_purpose text,
  p_provider_ref text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_provider_ref is null or length(p_provider_ref) = 0 then
    return;
  end if;
  update public.point_reserve_transfers
  set provider_ref = p_provider_ref
  where payment_charge_id = p_charge_id
    and purpose = p_purpose
    and status = 'sending';
end;
$$;

revoke all on function public.points_reserve_transfer_anchor(uuid, text)
  from public, anon, authenticated;
revoke all on function public.note_points_reserve_awaiting(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.remember_points_reserve_transfer(uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.points_reserve_transfer_anchor(uuid, text)
  to service_role;
grant execute on function public.note_points_reserve_awaiting(uuid, text, text)
  to service_role;
grant execute on function public.remember_points_reserve_transfer(uuid, text, text)
  to service_role;
