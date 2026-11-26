-- Admin, tela da casa: o servidor passa a devolver o que a tela precisa para
-- mostrar o valor gravado e a recusa passa a dizer qual campo errou.
--
-- 1) admin_venue devolve is_test, official_email, official_phone,
--    merged_into, city_name e city_state_code. Antes a chave de casa de
--    teste e os campos de contato oficial voltavam sempre vazios depois de
--    gravar, e parecia que o botão não tinha feito nada. Só acrescenta
--    chaves ao JSON; as que existiam continuam iguais.
-- 2) admin_update_venue troca o "dados da casa invalidos" genérico por uma
--    mensagem por campo. As regras e o sqlstate (22023) não mudam.
--
-- Não destrutivo: só create or replace de duas funções, sem tocar em dado.
-- Reverter: reaplicar as definições de 20261124124058_pagbank.sql
-- (admin_venue) e 20261109160000_admin_console.sql (admin_update_venue).

create or replace function public.admin_venue(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_house public.venues%rowtype;
  v_platform integer;
  v_rate integer;
  v_override boolean;
  v_city public.cities%rowtype;
begin
  select * into v_house from public.venues where id = p_venue_id;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  select * into v_city from public.cities where id = v_house.city_id;
  select commission_bps into v_platform
  from public.platform_settings where id = 1;
  select c.commission_bps into v_rate
  from public.venue_commissions c where c.venue_id = p_venue_id;
  v_override := v_rate is not null;
  v_rate := coalesce(v_rate, v_platform);
  return pg_catalog.jsonb_build_object(
    'id', v_house.id,
    'name', v_house.name,
    'city_id', v_house.city_id,
    'city_name', v_city.name,
    'city_state_code', v_city.state_code,
    'neighborhood', v_house.neighborhood,
    'street_address', v_house.street_address,
    'address_number', v_house.address_number,
    'postal_code', v_house.postal_code,
    'phone', v_house.phone,
    'category', v_house.category,
    'badge', v_house.badge,
    'status', v_house.status,
    'suspended', v_house.suspended_at is not null,
    'suspended_at', v_house.suspended_at,
    'is_test', coalesce(v_house.is_test, false),
    'merged_into', v_house.merged_into,
    'official_email', v_house.official_email,
    'official_phone', v_house.official_phone,
    'has_wallet', v_house.pagbank_account_id is not null,
    'document_kind', v_house.document_kind,
    'document_last4', right(v_house.document_number, 4),
    'owner_id', v_house.owner_id,
    'owner_name', (select display_name from public.profiles where id = v_house.owner_id),
    'owner_email', (select email from auth.users where id = v_house.owner_id),
    'invite_code', (
      select i.code from public.partner_invites i where i.id = v_house.invite_id
    ),
    'platform_bps', v_platform,
    'commission_bps', v_rate,
    'commission_override', v_override,
    'featured_rank', v_house.featured_rank,
    'snapshots', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(c) order by c.created_at desc)
      from (
        select id, commission_bps, status, created_at
        from public.payment_charges
        where venue_id = p_venue_id
        order by created_at desc
        limit 8
      ) c
    ), '[]'::jsonb),
    'rooms', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(r) order by r.name)
      from (
        select id, name, featured_rank
        from public.rooms
        where venue_id = p_venue_id
        order by name
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_update_venue(
  p_venue_id uuid,
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_house public.venues%rowtype;
  v_before jsonb;
  v_key text;
  v_name text;
  v_neighborhood text;
  v_street text;
  v_number text;
  v_postal text;
  v_phone text;
  v_category text;
  v_badge text;
  v_city text;
begin
  if p_patch is null or pg_catalog.jsonb_typeof(p_patch) <> 'object' then
    raise exception 'patch invalido' using errcode = '22023';
  end if;
  for v_key in select pg_catalog.jsonb_object_keys(p_patch)
  loop
    if v_key not in (
      'name', 'neighborhood', 'street_address', 'address_number',
      'postal_code', 'phone', 'category', 'badge', 'city_id'
    ) then
      raise exception 'campo % nao editavel', v_key using errcode = '22023';
    end if;
  end loop;
  select * into v_house from public.venues where id = p_venue_id for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  v_before := pg_catalog.jsonb_build_object(
    'name', v_house.name,
    'neighborhood', v_house.neighborhood,
    'street_address', v_house.street_address,
    'address_number', v_house.address_number,
    'postal_code', v_house.postal_code,
    'phone', v_house.phone,
    'category', v_house.category,
    'badge', v_house.badge,
    'city_id', v_house.city_id
  );
  v_name := coalesce(p_patch ->> 'name', v_house.name);
  v_neighborhood := coalesce(p_patch ->> 'neighborhood', v_house.neighborhood);
  v_street := case
    when p_patch ? 'street_address'
      then btrim(coalesce(p_patch ->> 'street_address', ''))
    else v_house.street_address
  end;
  v_number := case
    when p_patch ? 'address_number'
      then btrim(coalesce(p_patch ->> 'address_number', ''))
    else v_house.address_number
  end;
  v_postal := coalesce(p_patch ->> 'postal_code', v_house.postal_code);
  v_phone := coalesce(p_patch ->> 'phone', v_house.phone);
  v_category := coalesce(p_patch ->> 'category', v_house.category);
  v_badge := case
    when p_patch ? 'badge' then nullif(btrim(p_patch ->> 'badge'), '')
    else v_house.badge
  end;
  v_city := coalesce(p_patch ->> 'city_id', v_house.city_id);
  if char_length(btrim(v_name)) not between 2 and 80 then
    raise exception 'Nome: de 2 a 80 caracteres.' using errcode = '22023';
  end if;
  if char_length(btrim(v_neighborhood)) not between 2 and 80 then
    raise exception 'Bairro: de 2 a 80 caracteres.' using errcode = '22023';
  end if;
  if p_patch ? 'street_address'
    and char_length(v_street) not between 2 and 200
  then
    raise exception 'Endereço: de 2 a 200 caracteres.' using errcode = '22023';
  end if;
  if p_patch ? 'address_number'
    and char_length(v_number) not between 1 and 30
  then
    raise exception 'Número: de 1 a 30 caracteres.' using errcode = '22023';
  end if;
  if v_postal !~ '^[0-9]{8}$' then
    raise exception 'CEP: 8 números, sem hífen.' using errcode = '22023';
  end if;
  if v_phone !~ '^[0-9]{10,13}$' then
    raise exception 'Telefone: de 10 a 13 números, com DDD e sem símbolos.'
      using errcode = '22023';
  end if;
  if v_category not in ('escape-room', 'rpg', 'board-game', 'laser-tag', 'immersive') then
    raise exception 'Categoria inválida.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.cities where id = v_city) then
    raise exception 'Cidade inválida: escolha uma cidade da lista.'
      using errcode = '22023';
  end if;
  update public.venues
  set name = btrim(v_name),
      neighborhood = btrim(v_neighborhood),
      street_address = v_street,
      address_number = v_number,
      postal_code = v_postal,
      phone = v_phone,
      category = v_category,
      badge = v_badge,
      city_id = v_city
  where id = p_venue_id;
  perform private.admin_audit(
    v_uid, 'update_venue', 'venues', p_venue_id::text, v_before, p_patch
  );
  return public.admin_venue(p_venue_id);
end;
$$;

-- create or replace mantém os grants anteriores; reafirma para não depender disso.
revoke all on function public.admin_venue(uuid) from public, anon;
grant execute on function public.admin_venue(uuid) to authenticated;
revoke all on function public.admin_update_venue(uuid, jsonb) from public, anon;
grant execute on function public.admin_update_venue(uuid, jsonb) to authenticated;
