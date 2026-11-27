-- Unidades: o dono desativa (remove) uma unidade pelo Parceiro.
--
-- Aditiva: duas colunas novas, um RPC novo e o mesmo venues_guard com uma
-- exceção para o RPC. Nada é apagado: a unidade desativada fica com
-- suspended_at (o mesmo corte que já esconde casa suspensa do jogador, das
-- cidades, do ranking e das reservas) e deactivated_at/deactivated_by, para
-- distinguir da suspensão feita pelo Admin.
--
-- O RPC recusa quando:
--   - a unidade não é do login (42501);
--   - não sobra outra unidade ativa do mesmo login (unit_last);
--   - há grupo futuro não cancelado na unidade (unit_future_groups);
--   - há saque pendente ou cobrança a caminho, pela mesma regra da troca de
--     conta PagBank, private.venue_pagbank_in_flight (unit_pending_money).
-- Não aplicar em produção antes do ok do Nícolas.

alter table public.venues
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivated_by uuid references auth.users (id);

comment on column public.venues.deactivated_at is
  'Quando o dono desativou (removeu) a unidade pelo Parceiro. Junto com suspended_at.';

grant select (deactivated_at) on table public.venues to authenticated;

CREATE OR REPLACE FUNCTION private.venues_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.pagbank_account_id := null;
      new.suspended_at := null;
      new.deactivated_at := null;
      new.deactivated_by := null;
      new.featured_rank := null;
      new.official_email := null;
      new.official_phone := null;
      new.claimed_at := pg_catalog.now();
      if new.invite_id is not null then
        select i.badge
          into new.badge
        from public.partner_invites i
        where i.id = new.invite_id
          and i.active;
        if not found then
          raise exception 'unknown invite' using errcode = 'P0002';
        end if;
      else
        new.badge := null;
      end if;
    end if;
    if new.latitude is null or new.longitude is null then
      select c.latitude, c.longitude
        into new.latitude, new.longitude
      from public.cities c
      where c.id = new.city_id;
    end if;
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  if not private.is_admin_aal2() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.invite_id := old.invite_id;
    new.pagbank_account_id := old.pagbank_account_id;
    -- Só deactivate_my_unit liga esta chave, na própria transação, depois de
    -- conferir dono, outra unidade ativa, grupos futuros e dinheiro a caminho.
    if current_setting('scapematch.unit_deactivation', true) is distinct from 'on' then
      new.suspended_at := old.suspended_at;
      new.deactivated_at := old.deactivated_at;
      new.deactivated_by := old.deactivated_by;
    end if;
    new.featured_rank := old.featured_rank;
    new.official_email := old.official_email;
    new.official_phone := old.official_phone;
    new.claimed_at := old.claimed_at;
    if old.status is distinct from 'pending'
      or old.pagbank_account_id is not null
    then
      new.company_type := old.company_type;
    end if;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  -- Admin reativando (suspended_at volta a nulo) desfaz também a
  -- desativação do dono, para a unidade voltar a aparecer no Parceiro.
  if new.suspended_at is null and new.deactivated_at is not null then
    new.deactivated_at := null;
    new.deactivated_by := null;
  end if;
  return new;
end;
$function$;

create or replace function public.deactivate_my_unit(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_venue public.venues%rowtype;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_venue
  from public.venues
  where id = p_venue_id
  for update;
  if not found or v_venue.owner_id is distinct from v_uid then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_venue.deactivated_at is not null then
    return pg_catalog.jsonb_build_object('ok', true, 'already', true);
  end if;

  if not exists (
    select 1
    from public.venues other
    where other.owner_id = v_uid
      and other.id <> p_venue_id
      and other.deactivated_at is null
      and other.status in ('pending', 'approved')
  ) then
    raise exception 'unit_last' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.groups g
    where g.venue_id = p_venue_id
      and g.cancelled_at is null
      and g.starts_at > pg_catalog.now()
  ) then
    raise exception 'unit_future_groups' using errcode = 'P0001';
  end if;

  if private.venue_pagbank_in_flight(p_venue_id) > 0 then
    raise exception 'unit_pending_money' using errcode = 'P0001';
  end if;

  perform pg_catalog.set_config('scapematch.unit_deactivation', 'on', true);
  update public.venues
  set suspended_at = coalesce(suspended_at, pg_catalog.now()),
      deactivated_at = pg_catalog.now(),
      deactivated_by = v_uid
  where id = p_venue_id;
  perform pg_catalog.set_config('scapematch.unit_deactivation', 'off', true);

  insert into public.admin_audit_log (
    actor_id, action, target_table, target_id, before_state, after_state
  ) values (
    v_uid,
    'deactivate_unit',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('suspended_at', v_venue.suspended_at),
    pg_catalog.jsonb_build_object('deactivated', true)
  );

  return pg_catalog.jsonb_build_object('ok', true, 'already', false);
end;
$$;

revoke all on function public.deactivate_my_unit(uuid) from public, anon, authenticated;
grant execute on function public.deactivate_my_unit(uuid) to authenticated;
