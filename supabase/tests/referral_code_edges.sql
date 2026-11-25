-- Bordas do código de indicação e do desconto da primeira sessão.
-- Código inválido, autoindicação e código fora da janela de 24 h ficam
-- nos 10% sem código. Código válido digitado depois do cadastro, dentro
-- da janela, vira 20%. Arredondamento do centavo: meio centavo sobe.
-- O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_owner uuid := 'e2710000-0000-4000-8000-0000000000b1';
  v_ref uuid := 'e2710000-0000-4000-8000-0000000000d1';
  v_inv uuid := 'e2710000-0000-4000-8000-0000000000c1';
  v_self uuid := 'e2710000-0000-4000-8000-0000000000c2';
  v_late uuid := 'e2710000-0000-4000-8000-0000000000c3';
  v_after uuid := 'e2710000-0000-4000-8000-0000000000c4';
  v_venue uuid := 'e2720000-0000-4000-8000-000000000001';
  v_code text;
  v_self_code text;
  v_result text;
begin
  update public.referral_program_settings
  set first_booking_discount_bps = 2000,
      organic_first_booking_discount_bps = 1000
  where id = 1;

  insert into auth.users (id, email, raw_user_meta_data) values
    (v_owner, 'borda-dono@example.com', '{"display_name":"Dono"}'),
    (v_ref, 'borda-indicador@example.com', '{"display_name":"Indicador"}'),
    (v_inv, 'borda-invalido@example.com', '{"display_name":"Invalido"}'),
    (v_self, 'borda-proprio@example.com', '{"display_name":"Proprio"}'),
    (v_late, 'borda-atrasado@example.com', '{"display_name":"Atrasado"}'),
    (v_after, 'borda-depois@example.com', '{"display_name":"Depois"}');
  insert into public.venues (
    id, owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, income_value, document_kind,
    document_number, phone, status, pagbank_account_id
  ) values (
    v_venue, v_owner, 'curitiba', 'Casa Borda', 'Centro', 'Rua da Borda', '1',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '61234567000912',
    '4130002712', 'approved',
    'ACCO_21111111-1111-4111-8111-111111111111'
  );

  select code into v_code from public.referral_codes where owner_user_id = v_ref;
  select code into v_self_code from public.referral_codes where owner_user_id = v_self;
  if v_code is null or v_self_code is null then
    raise exception 'o cadastro nao gerou codigo de jogador';
  end if;

  v_result := private.attach_referral('player', v_inv, null, 'ZZZZ9999', true);
  if v_result <> 'invalid'
    or (select signup_referred from public.profiles where id = v_inv)
    or private.first_booking_discount_for(v_inv, v_venue, 10000, 2500, 0, null) <> 1000
  then
    raise exception 'codigo invalido saiu de 10%%: %', v_result;
  end if;

  v_result := private.attach_referral('player', v_self, null, v_self_code, true);
  if v_result <> 'self'
    or (select signup_referred from public.profiles where id = v_self)
    or private.first_booking_discount_for(v_self, v_venue, 10000, 2500, 0, null) <> 1000
  then
    raise exception 'autoindicacao saiu de 10%%: %', v_result;
  end if;

  update public.profiles
  set created_at = pg_catalog.now() - interval '25 hours'
  where id = v_late;
  v_result := private.attach_referral('player', v_late, null, v_code, true);
  if v_result <> 'late'
    or (select signup_referred from public.profiles where id = v_late)
    or private.first_booking_discount_for(v_late, v_venue, 10000, 2500, 0, null) <> 1000
  then
    raise exception 'codigo depois de 24 h saiu de 10%%: %', v_result;
  end if;

  -- Minúsculas e separadores são normalizados.
  v_result := private.attach_referral(
    'player', v_after, null,
    pg_catalog.lower(substr(v_code, 1, 4)) || '-' || substr(v_code, 5), true
  );
  if v_result <> 'ok'
    or not (select signup_referred from public.profiles where id = v_after)
    or private.first_booking_discount_for(v_after, v_venue, 10000, 2500, 0, null) <> 2000
  then
    raise exception 'codigo valido depois do cadastro nao deu 20%%: %', v_result;
  end if;
  if private.attach_referral('player', v_after, null, v_code, true) <> 'exists' then
    raise exception 'o segundo codigo nao foi recusado';
  end if;

  -- Meio centavo sobe; R$ 0,01 não tem desconto.
  if private.first_booking_discount_for(v_after, v_venue, 3333, 2500, 0, null) <> 667
    or private.first_booking_discount_for(v_inv, v_venue, 3335, 2500, 0, null) <> 334
    or private.first_booking_discount_for(v_inv, v_venue, 3334, 2500, 0, null) <> 333
    or private.first_booking_discount_for(v_inv, v_venue, 1, 2500, 0, null) <> 0
  then
    raise exception 'arredondamento do desconto fora da regra';
  end if;
end $$;

rollback;
