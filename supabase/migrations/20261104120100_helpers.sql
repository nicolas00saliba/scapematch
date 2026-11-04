-- Funções de apoio. is_admin e owns_venue atravessam o RLS de propósito,
-- senão a política que as chama entra em recursão.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins where user_id = auth.uid()
  );
$$;

create or replace function public.owns_venue(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and owner_id = auth.uid()
  );
$$;

create or replace function public.venue_is_visible(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.venues
    where id = p_venue_id
      and (
        status = 'approved'
        or owner_id = auth.uid()
        or public.is_admin()
      )
  );
$$;

revoke all on function public.is_admin() from public;
revoke all on function public.owns_venue(uuid) from public;
revoke all on function public.venue_is_visible(uuid) from public;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.owns_venue(uuid) to authenticated;
grant execute on function public.venue_is_visible(uuid) to anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_birth date;
begin
  v_name := nullif(trim(new.raw_user_meta_data ->> 'display_name'), '');
  if v_name is null then
    v_name := split_part(coalesce(new.email, 'jogador'), '@', 1);
  end if;
  if char_length(v_name) > 80 then
    v_name := left(v_name, 80);
  end if;
  if char_length(v_name) < 1 then
    v_name := 'Jogador';
  end if;
  begin
    v_birth := nullif(new.raw_user_meta_data ->> 'birth_date', '')::date;
  exception
    when others then
      v_birth := null;
  end;
  insert into public.profiles (id, display_name, birth_date)
  values (new.id, v_name, v_birth)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.venues_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not public.is_admin() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.asaas_wallet_id := null;
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

  -- Sem JWT: SQL editor ou service role da Edge Function (grava o walletId).
  if auth.uid() is null then
    return new;
  end if;

  if not public.is_admin() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.referred_by := old.referred_by;
    new.invite_id := old.invite_id;
    new.asaas_wallet_id := old.asaas_wallet_id;
  end if;
  return new;
end;
$$;

drop trigger if exists venues_guard on public.venues;
create trigger venues_guard
  before insert or update on public.venues
  for each row execute function public.venues_guard();

-- A casa nasce pendente. O admin aprova ou recusa por update direto:
-- o gatilho acima só deixa o status mudar quando is_admin() é verdadeiro.
-- O walletId da subconta Asaas só a função (service role, sem JWT) grava.

create or replace function public.profiles_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.asaas_customer_id := old.asaas_customer_id;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.profiles_guard();
