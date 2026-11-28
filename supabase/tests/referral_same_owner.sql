-- Unidade irmã (mesmo dono, outra cidade, outro CNPJ, outro telefone) não
-- se indica. Casa de outro dono continua. Dono sem CPF também não indica
-- a própria casa, nem como jogador nem como casa. Desfaz no fim.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('a2810000-0000-4000-8000-000000000001', 'same-owner-a@example.com', '{"display_name":"Dono A"}'),
  ('a2810000-0000-4000-8000-000000000002', 'same-owner-b@example.com', '{"display_name":"Dono B"}'),
  ('a2810000-0000-4000-8000-000000000003', 'same-owner-player@example.com', '{"display_name":"Dono sem CPF"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, created_at
) values
  ('a2810000-0000-4000-8000-0000000000a1', 'a2810000-0000-4000-8000-000000000001',
   'curitiba', 'Casa Matriz', 'Centro', 'Rua Um', '1', '80020010',
   -25.43, -49.27, 5000, 'cnpj', '28110000000101', '41988881101', 'approved',
   now() - interval '2 days'),
  ('a2810000-0000-4000-8000-0000000000b2', 'a2810000-0000-4000-8000-000000000001',
   'sao-paulo', 'Casa Filial', 'Centro', 'Rua Dois', '2', '01310100',
   -23.55, -46.63, 5000, 'cnpj', '28110000000202', '11988882202', 'pending',
   now()),
  ('a2810000-0000-4000-8000-0000000000c3', 'a2810000-0000-4000-8000-000000000002',
   'rio-de-janeiro', 'Casa De Outro', 'Centro', 'Rua Tres', '3', '20040020',
   -22.91, -43.17, 5000, 'cnpj', '28110000000303', '21988883303', 'pending',
   now()),
  ('a2810000-0000-4000-8000-0000000000d4', 'a2810000-0000-4000-8000-000000000003',
   'belo-horizonte', 'Casa Do Dono Jogador', 'Centro', 'Rua Quatro', '4', '30130010',
   -19.92, -43.93, 5000, 'cnpj', '28110000000404', '31988884404', 'approved',
   now());

do $$
declare
  v_code_a text;
  v_code_d text;
  v_code_z text;
  v_result text;
  v_status text;
  v_reason text;
  v_referred uuid;
begin
  if has_function_privilege(
      'public',
      'private.identity_conflict(uuid,uuid,uuid,uuid)',
      'execute'
    )
    or has_function_privilege(
      'anon',
      'private.identity_conflict(uuid,uuid,uuid,uuid)',
      'execute'
    )
    or has_function_privilege(
      'authenticated',
      'private.identity_conflict(uuid,uuid,uuid,uuid)',
      'execute'
    )
  then
    raise exception 'identity_conflict ficou executável fora do dono';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'identity_conflict'
      and p.pronargs = 4
      and p.prosecdef
      and 'search_path=""' = any (p.proconfig)
  ) then
    raise exception 'identity_conflict sem security definer ou search_path vazio';
  end if;

  if (
    select owner_id from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000a1'
  ) is distinct from (
    select owner_id from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000b2'
  ) or (
    select document_number from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000a1'
  ) is not distinct from (
    select document_number from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000b2'
  ) or (
    select phone from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000a1'
  ) is not distinct from (
    select phone from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000b2'
  ) or (
    select city_id from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000a1'
  ) is not distinct from (
    select city_id from public.venues
    where id = 'a2810000-0000-4000-8000-0000000000b2'
  ) then
    raise exception 'a fixture da filial não separou dono, CNPJ, telefone e cidade';
  end if;

  if exists (
    select 1 from public.profiles
    where id = 'a2810000-0000-4000-8000-000000000003'
      and (cpf is not null or phone is not null)
  ) then
    raise exception 'o dono sem CPF nasceu com CPF ou telefone';
  end if;

  v_code_a := private.ensure_venue_code('a2810000-0000-4000-8000-0000000000a1');

  v_result := private.attach_referral(
    'venue', null, 'a2810000-0000-4000-8000-0000000000b2', v_code_a, true
  );
  if v_result is distinct from 'blocked' then
    raise exception 'unidade irmã não bloqueou: %', v_result;
  end if;
  select status, block_reason
    into v_status, v_reason
  from public.referral_attributions
  where subject_venue_id = 'a2810000-0000-4000-8000-0000000000b2';
  if v_status is distinct from 'blocked' or v_reason is distinct from 'same_owner' then
    raise exception 'unidade irmã ficou % / %', v_status, v_reason;
  end if;
  select referred_by into v_referred
  from public.venues
  where id = 'a2810000-0000-4000-8000-0000000000b2';
  if v_referred is not null then
    raise exception 'unidade irmã gravou referred_by';
  end if;

  v_result := private.attach_referral(
    'venue', null, 'a2810000-0000-4000-8000-0000000000c3', v_code_a, true
  );
  if v_result is distinct from 'ok' then
    raise exception 'casa de outro dono não entrou: %', v_result;
  end if;
  select status, block_reason
    into v_status, v_reason
  from public.referral_attributions
  where subject_venue_id = 'a2810000-0000-4000-8000-0000000000c3';
  if v_status is distinct from 'active' or v_reason is not null then
    raise exception 'casa de outro dono ficou % / %', v_status, v_reason;
  end if;
  select referred_by into v_referred
  from public.venues
  where id = 'a2810000-0000-4000-8000-0000000000c3';
  if v_referred is distinct from 'a2810000-0000-4000-8000-0000000000a1' then
    raise exception 'casa de outro dono não apontou referred_by para a indicadora';
  end if;

  v_result := private.attach_referral(
    'player', 'a2810000-0000-4000-8000-000000000002', null, v_code_a, true
  );
  if v_result is distinct from 'ok' then
    raise exception 'jogador que não é dono da casa indicadora não entrou: %', v_result;
  end if;

  v_code_d := private.ensure_venue_code('a2810000-0000-4000-8000-0000000000d4');
  v_result := private.attach_referral(
    'player', 'a2810000-0000-4000-8000-000000000003', null, v_code_d, true
  );
  if v_result is distinct from 'blocked' then
    raise exception 'dono sem CPF usou o código da própria casa: %', v_result;
  end if;
  select status, block_reason
    into v_status, v_reason
  from public.referral_attributions
  where subject_user_id = 'a2810000-0000-4000-8000-000000000003';
  if v_status is distinct from 'blocked'
    or v_reason is distinct from 'player_owns_venue'
  then
    raise exception 'dono-jogador ficou % / %', v_status, v_reason;
  end if;

  v_code_z := private.ensure_player_code('a2810000-0000-4000-8000-000000000003');
  v_result := private.attach_referral(
    'venue', null, 'a2810000-0000-4000-8000-0000000000d4', v_code_z, true
  );
  if v_result is distinct from 'blocked' then
    raise exception 'casa aceitou o código do próprio dono: %', v_result;
  end if;
  select status, block_reason
    into v_status, v_reason
  from public.referral_attributions
  where subject_venue_id = 'a2810000-0000-4000-8000-0000000000d4';
  if v_status is distinct from 'blocked'
    or v_reason is distinct from 'player_owns_venue'
  then
    raise exception 'casa do dono ficou % / %', v_status, v_reason;
  end if;
  select referred_by into v_referred
  from public.venues
  where id = 'a2810000-0000-4000-8000-0000000000d4';
  if v_referred is not null then
    raise exception 'casa do dono gravou referred_by';
  end if;
end
$$;

rollback;
