-- Reivindicação oficial. Não fala com Asaas nem com o projeto remoto.
-- O job duplicates-sql sobe postgres sem pgTAP. O harness já usado no CI
-- executa este arquivo.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
    'perfil-ninja@example.com',
    '{"display_name":"Perfil Ninja"}'
  ),
  (
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
    'dona-ninja@example.com',
    '{"display_name":"Dona Ninja"}'
  ),
  (
    'c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3',
    'admin-claim@example.com',
    '{"display_name":"Admin Claim"}'
  ),
  (
    'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4',
    'primeiro-pedido@example.com',
    '{"display_name":"Primeiro Pedido"}'
  ),
  (
    'a4a4a4a4-a4a4-44a4-84a4-a4a4a4a4a4a4',
    'segundo-pedido@example.com',
    '{"display_name":"Segundo Pedido"}'
  )
on conflict (id) do nothing;

insert into public.profiles (id, display_name)
values
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', 'Dona Ninja'),
  ('c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3', 'Admin Claim')
on conflict (id) do nothing;

insert into public.admins (user_id)
values ('c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3')
on conflict (user_id) do nothing;

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, official_email, official_phone, status
) values (
  'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
  'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
  'curitiba',
  'Ninja Escape Room',
  'Batel',
  'Rua do Perfil',
  '20',
  '80420010',
  -25.44,
  -49.29,
  8000,
  'cnpj',
  '33445566000199',
  '41910001991',
  'oficial@ninja.example',
  '41910001992',
  'approved'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'e6e6e6e6-e6e6-46e6-86e6-e6e6e6e6e6e6',
  'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
  'curitiba',
  'Casa Sem Contato',
  'Centro',
  'Rua Sem Contato',
  '2',
  '80010000',
  -25.42,
  -49.27,
  4000,
  'cnpj',
  '33445566000198',
  '41910001993',
  'approved'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
  'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1',
  'curitiba',
  'Casa Dois Pedidos',
  'Centro',
  'Rua Dois Pedidos',
  '7',
  '80010010',
  -25.43,
  -49.28,
  4000,
  'cnpj',
  '33445566000197',
  '41910001994',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'f7f7f7f7-f7f7-47f7-87f7-f7f7f7f7f7f7',
  'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
  'Sala do Perfil',
  6, 2, 60, 'medium', 12000
);

insert into public.room_photos (id, room_id, storage_path)
values (
  'f8f8f8f8-f8f8-48f8-88f8-f8f8f8f8f8f8',
  'f7f7f7f7-f7f7-47f7-87f7-f7f7f7f7f7f7',
  'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5/sala.jpg'
);

do $$
begin
  if has_column_privilege(
    'authenticated', 'public.venues', 'official_email', 'select'
  ) or has_column_privilege(
    'anon', 'public.venues', 'official_phone', 'select'
  ) or has_column_privilege(
    'authenticated', 'public.venues', 'claimed_at', 'select'
  ) then
    raise exception 'contato oficial vazou para o app';
  end if;
  if has_table_privilege('anon', 'private.venue_claim_codes', 'select')
    or has_table_privilege('authenticated', 'private.venue_claim_codes', 'select')
    or has_table_privilege('anon', 'private.venue_claim_audit', 'select')
    or has_table_privilege('authenticated', 'private.venue_claim_audit', 'select')
  then
    raise exception 'código ou auditoria abertos na API';
  end if;
  if has_function_privilege(
    'authenticated',
    'private.issue_venue_claim_code(uuid, uuid)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.issue_venue_claim_code(uuid, uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.confirm_venue_claim_code(uuid, uuid, text)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.find_claimable_venue(text)',
    'execute'
  ) then
    raise exception 'anon ou authenticated emite o código';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.venue_finance_ready(uuid)', 'execute'
  ) then
    raise exception 'o app não consulta se a casa pode receber';
  end if;
end $$;

begin;
select set_config(
  'request.jwt.claim.sub',
  'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
  true
);
set local role authenticated;

do $$
declare
  v_found jsonb;
  v_text text;
begin
  v_found := public.find_claimable_venue('33.445.566/0001-99');
  if v_found ->> 'path' <> 'otp' then
    raise exception 'CNPJ da Ninja não ofereceu reivindicação: %', v_found;
  end if;
  if v_found ->> 'name' <> 'Ninja Escape Room' then
    raise exception 'nome público da casa sumiu';
  end if;
  if (v_found ->> 'has_official_email')::boolean is not true
    or (v_found ->> 'has_official_phone')::boolean is not true
  then
    raise exception 'a busca não avisou que há contato oficial';
  end if;
  v_text := v_found::text;
  if v_text like '%oficial@ninja.example%' or v_text like '%41910001992%' then
    raise exception 'a busca devolveu o contato oficial';
  end if;
  if public.find_claimable_venue('33445566000198') ->> 'path' <> 'manual' then
    raise exception 'casa sem contato não caiu em aprovação manual';
  end if;
end $$;

reset role;
commit;

insert into private.venue_claim_codes (
  venue_id, claimant_id, code_hash, expires_at, created_at
)
select
  'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
  'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
  'hash-falso-so-para-o-limite-de-taxa-0001',
  pg_catalog.now() + interval '10 minutes',
  pg_catalog.now()
from pg_catalog.generate_series(1, 5);

set role service_role;

do $$
declare
  v_issued jsonb;
begin
  v_issued := private.issue_venue_claim_code(
    'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
  );
  if v_issued ->> 'status' <> 'rate' then
    raise exception 'limite de códigos não segurou: %', v_issued;
  end if;
end $$;

reset role;

delete from private.venue_claim_codes
where venue_id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5';

set role service_role;

do $$
declare
  v_issued jsonb;
  v_code text;
  v_wrong jsonb;
  v_ok jsonb;
  v_manual jsonb;
begin
  v_manual := private.issue_venue_claim_code(
    'e6e6e6e6-e6e6-46e6-86e6-e6e6e6e6e6e6',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
  );
  if v_manual ->> 'status' <> 'manual' or v_manual ? 'code' then
    raise exception 'sem contato devolveu código: %', v_manual;
  end if;

  v_issued := private.issue_venue_claim_code(
    'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
  );
  if v_issued ->> 'status' <> 'otp' then
    raise exception 'não emitiu código: %', v_issued ->> 'status';
  end if;
  if v_issued ->> 'email' <> 'oficial@ninja.example'
    or v_issued ->> 'phone' <> '41910001992'
  then
    raise exception 'o código não saiu do contato do perfil';
  end if;
  v_code := v_issued ->> 'code';
  if v_code !~ '^[0-9]{6}$' then
    raise exception 'código fora do formato';
  end if;

  v_wrong := private.confirm_venue_claim_code(
    'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
    '000000'
  );
  if v_wrong ->> 'status' <> 'mismatch' then
    raise exception 'código errado passou: %', v_wrong;
  end if;

  v_ok := private.confirm_venue_claim_code(
    'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
    v_code
  );
  if v_ok ->> 'status' <> 'confirmed' then
    raise exception 'código certo não ligou a casa: %', v_ok;
  end if;
  perform set_config('scapematch.claim_probe', v_issued::text, false);
end $$;

reset role;

do $$
declare
  v_issued jsonb := current_setting('scapematch.claim_probe')::jsonb;
  v_code text := v_issued ->> 'code';
  v_owner uuid;
  v_photos integer;
begin
  if (
    select owner_id from public.venues
    where id = 'e6e6e6e6-e6e6-46e6-86e6-e6e6e6e6e6e6'
  ) is distinct from 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1' then
    raise exception 'aprovação manual já trocou o dono';
  end if;
  if exists (
    select 1 from private.venue_claim_codes
    where code_hash = v_code
  ) then
    raise exception 'o código ficou em claro';
  end if;
  if (
    select attempts from private.venue_claim_codes
    where id = (v_issued ->> 'code_id')::uuid
  ) <> 1 then
    raise exception 'tentativa não contou';
  end if;
  select owner_id into v_owner
  from public.venues
  where id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5';
  if v_owner is distinct from 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2' then
    raise exception 'a conta não virou dona';
  end if;
  if (
    select claimed_at is null from public.venues
    where id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5'
  ) then
    raise exception 'a casa continuou não reivindicada';
  end if;
  select count(*) into v_photos
  from public.room_photos photo
  join public.rooms room on room.id = photo.room_id
  where room.venue_id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5';
  if v_photos <> 1 then
    raise exception 'a foto da sala não ficou na mesma casa';
  end if;
  if (
    select count(*) from public.venues
    where document_digits = '33445566000199'
      and status not in ('rejected', 'merged')
  ) <> 1 then
    raise exception 'a reivindicação criou outra casa';
  end if;
  if not exists (
    select 1 from private.venue_claim_audit
    where venue_id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5'
      and action = 'confirm'
  ) then
    raise exception 'confirmação sem auditoria';
  end if;
end $$;

select set_config('scapematch.claim_issue', 'on', false);
insert into public.venue_claims (id, venue_id, claimant_id, note)
values
  (
    'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1',
    'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
    'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4',
    'primeiro'
  ),
  (
    'c2c2c2c2-c2c2-42c2-82c2-c2c2c2c2c2c2',
    'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
    'a4a4a4a4-a4a4-44a4-84a4-a4a4a4a4a4a4',
    'segundo'
  ),
  (
    'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4',
    'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
    'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4',
    'casa ja reivindicada'
  );
select set_config('scapematch.claim_issue', 'off', false);

begin;
select set_config(
  'request.jwt.claim.sub',
  'c3c3c3c3-c3c3-43c3-83c3-c3c3c3c3c3c3',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;

do $$
declare
  v_claim uuid;
  v_owner uuid;
begin
  select id into v_claim
  from public.venue_claims
  where venue_id = 'e6e6e6e6-e6e6-46e6-86e6-e6e6e6e6e6e6'
    and status = 'pending';
  if v_claim is null then
    raise exception 'admin não achou a reivindicação manual';
  end if;
  if jsonb_array_length(public.admin_list_venue_claims()) < 1 then
    raise exception 'a fila do admin veio vazia';
  end if;
  perform public.admin_review_venue_claim(v_claim, 'approved');
  select owner_id into v_owner
  from public.venues
  where id = 'e6e6e6e6-e6e6-46e6-86e6-e6e6e6e6e6e6';
  if v_owner is distinct from 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2' then
    raise exception 'aprovar não passou a casa';
  end if;
end $$;

do $$
declare
  v_owner uuid;
  v_status text;
begin
  perform public.admin_review_venue_claim(
    'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1',
    'approved'
  );
  select owner_id into v_owner
  from public.venues
  where id = 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7';
  if v_owner is distinct from 'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4' then
    raise exception 'o primeiro pedido não virou dono';
  end if;
  select status into v_status
  from public.venue_claims
  where id = 'c2c2c2c2-c2c2-42c2-82c2-c2c2c2c2c2c2';
  if v_status is distinct from 'rejected' then
    raise exception 'o outro pedido pendente não foi recusado: %', v_status;
  end if;

  begin
    perform public.admin_review_venue_claim(
      'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4',
      'approved'
    );
    raise exception 'casa já reivindicada foi aprovada';
  exception
    when sqlstate 'P0001' then
      if sqlerrm is distinct from 'already_claimed' then
        raise;
      end if;
  end;

  if (
    select status from public.venue_claims
    where id = 'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4'
  ) is distinct from 'pending' then
    raise exception 'already_claimed marcou o pedido como aprovado';
  end if;
  if (
    select owner_id from public.venues
    where id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5'
  ) is distinct from 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2' then
    raise exception 'a casa já reivindicada trocou de dono';
  end if;
end $$;

reset role;
commit;

do $$
begin
  if (
    select claimed_at is null from public.venues
    where id = 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7'
  ) then
    raise exception 'a casa de dois pedidos ficou sem claimed_at';
  end if;
  if public.venue_finance_ready('e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5') then
    raise exception 'casa sem subconta e sem banco já recebe';
  end if;
end $$;

update public.venues
set asaas_wallet_id = 'wal_ninja_claim'
where id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5';

do $$
begin
  if public.venue_finance_ready('e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5') then
    raise exception 'subconta sem conta bancária já recebe';
  end if;
end $$;

insert into public.venue_bank_accounts (
  venue_id, destination, pix_key, pix_key_type, owner_name, owner_document,
  operation_type, updated_by
) values (
  'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5',
  'pix',
  '33445566000199',
  'CNPJ',
  'Ninja Escape Room',
  '33445566000199',
  'PIX',
  'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2'
);

do $$
begin
  if not public.venue_finance_ready('e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5') then
    raise exception 'subconta e Pix não liberaram o recebimento';
  end if;
  if not exists (
    select 1 from public.venues_vitrine
    where id = 'e5e5e5e5-e5e5-45e5-85e5-e5e5e5e5e5e5'
      and finance_ready
  ) then
    raise exception 'a vitrine não mostra que a casa pode receber';
  end if;
end $$;
