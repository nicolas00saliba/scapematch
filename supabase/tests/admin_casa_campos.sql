-- Admin, tela da casa: admin_venue devolve o que a tela precisa para mostrar
-- o valor gravado e admin_update_venue diz qual campo errou.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('c4a11111-1111-4111-8111-111111111111', 'casa-campos-admin@example.com', '{"display_name":"Admin Campos"}'),
  ('c4a22222-2222-4222-8222-222222222222', 'casa-campos-dono@example.com', '{"display_name":"Dono Campos"}');

insert into public.admins (user_id)
values ('c4a11111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'c4b11111-1111-4111-8111-111111111111',
  'c4a22222-2222-4222-8222-222222222222',
  'curitiba', 'Casa Campos', 'Centro', 'Rua dos Campos', '10',
  '80020010', -25.43, -49.27, 4000, 'cnpj', '19000000000901', '4191000901',
  'approved'
);

begin;
select set_config('request.jwt.claim.sub', 'c4a11111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_house jsonb;
  v_message text;
  v_case text;
begin
  v_house := public.admin_venue('c4b11111-1111-4111-8111-111111111111');
  if v_house ->> 'is_test' <> 'false'
    or v_house ->> 'city_name' <> 'Curitiba'
    or v_house ->> 'city_state_code' <> 'PR'
    or not v_house ? 'official_email'
    or not v_house ? 'official_phone'
    or not v_house ? 'merged_into'
  then
    raise exception 'admin_venue sem os campos novos: %', v_house;
  end if;

  perform public.admin_set_account_test(
    'venue', 'c4b11111-1111-4111-8111-111111111111', true
  );
  perform public.admin_set_venue_contacts(
    'c4b11111-1111-4111-8111-111111111111',
    'Oficial@Casa.Example', '(41) 99999-0001'
  );
  v_house := public.admin_venue('c4b11111-1111-4111-8111-111111111111');
  if v_house ->> 'is_test' <> 'true'
    or v_house ->> 'official_email' <> 'oficial@casa.example'
    or v_house ->> 'official_phone' <> '41999990001'
  then
    raise exception 'admin_venue nao leu o que foi gravado: %', v_house;
  end if;

  -- Cada recusa diz o campo e mantém o sqlstate 22023.
  foreach v_case in array array[
    'postal_code|123|CEP',
    'phone|(41) 9999|Telefone',
    'category|nada|Categoria',
    'city_id|nao-existe|Cidade',
    'name|x|Nome',
    'neighborhood|x|Bairro'
  ]
  loop
    begin
      perform public.admin_update_venue(
        'c4b11111-1111-4111-8111-111111111111',
        jsonb_build_object(split_part(v_case, '|', 1), split_part(v_case, '|', 2))
      );
      raise exception 'gravou campo invalido: %', v_case;
    exception
      when sqlstate '22023' then
        get stacked diagnostics v_message = message_text;
        if position(split_part(v_case, '|', 3) in v_message) <> 1 then
          raise exception 'mensagem sem o campo (%): %', v_case, v_message;
        end if;
    end;
  end loop;

  v_house := public.admin_update_venue(
    'c4b11111-1111-4111-8111-111111111111',
    '{"neighborhood":"Batel","postal_code":"80020020"}'::jsonb
  );
  if v_house ->> 'neighborhood' <> 'Batel'
    or v_house ->> 'postal_code' <> '80020020'
    or v_house ->> 'city_id' <> 'curitiba'
  then
    raise exception 'update valido nao gravou: %', v_house;
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'c4a22222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
begin
  perform public.admin_venue('c4b11111-1111-4111-8111-111111111111');
  raise exception 'dono leu a casa pelo admin';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
set local role anon;
do $$
begin
  perform public.admin_venue('c4b11111-1111-4111-8111-111111111111');
  raise exception 'anon leu a casa pelo admin';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;
