-- O dono corrige o tipo da empresa só enquanto a casa está pendente
-- e ainda não tem subconta. Depois disso, o valor fica com o admin aal2.
-- Desativar cartão não exige que o perfil ainda aponte para o customer:
-- a corrida pode gravar o id novo antes do outro pedido desativar o cartão.
-- Não aplicar no remoto até publicar as funções deste PR.

create or replace function private.saved_cards_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and new.asaas_customer_id is not distinct from old.asaas_customer_id
  then
    return new;
  end if;
  if not exists (
    select 1
    from public.profiles p
    where p.id = new.user_id
      and p.asaas_customer_id = new.asaas_customer_id
  ) then
    raise exception 'customer do cartão não é o do jogador';
  end if;
  return new;
end;
$$;

create or replace function private.venues_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.asaas_wallet_id := null;
      new.suspended_at := null;
      new.featured_rank := null;
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
    new.asaas_wallet_id := old.asaas_wallet_id;
    new.suspended_at := old.suspended_at;
    new.featured_rank := old.featured_rank;
    if old.status is distinct from 'pending'
      or old.asaas_wallet_id is not null
    then
      new.company_type := old.company_type;
    end if;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$$;
