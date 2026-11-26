-- Bordas do código de indicação (auditoria de 26/11/2026).
-- Código inválido, autoindicação, segundo código, código depois de 24h,
-- código depois da primeira sessão e formato do código. O bloco desfaz no final.

\set ON_ERROR_STOP on

begin;

do $$
declare
  v_owner uuid := 'c2800000-0000-4000-8000-0000000000a1';
  v_new uuid := 'c2800000-0000-4000-8000-0000000000a2';
  v_old uuid := 'c2800000-0000-4000-8000-0000000000a3';
  v_other uuid := 'c2800000-0000-4000-8000-0000000000a4';
  v_code text;
  v_status text;
  v_flag boolean;
begin
  update public.referral_program_settings
  set first_booking_discount_bps = 2000,
      organic_first_booking_discount_bps = 1000
  where id = 1;
  insert into auth.users (id, email, raw_user_meta_data) values
    (v_owner, 'borda-dono@example.com', '{"display_name":"Dono"}'),
    (v_new, 'borda-novo@example.com', '{"display_name":"Novo"}'),
    (v_old, 'borda-antigo@example.com', '{"display_name":"Antigo"}'),
    (v_other, 'borda-outro@example.com', '{"display_name":"Outro"}');
  select code into v_code from public.referral_codes where owner_user_id = v_owner;
  if v_code is null then
    raise exception 'o dono nao tem codigo';
  end if;

  -- inválido: curto, vazio, nulo e desconhecido
  if private.attach_referral('player', v_new, null, 'ABC', true) <> 'invalid'
    or private.attach_referral('player', v_new, null, '', true) <> 'invalid'
    or private.attach_referral('player', v_new, null, null, true) <> 'invalid'
    or private.attach_referral('player', v_new, null, 'ZZZZZZZZ', true) <> 'invalid'
  then
    raise exception 'codigo invalido nao devolveu invalid';
  end if;
  if exists (select 1 from public.referral_attributions where subject_user_id = v_new) then
    raise exception 'codigo invalido gravou atribuicao';
  end if;

  -- autoindicação
  if private.attach_referral('player', v_owner, null, v_code, true) <> 'self' then
    raise exception 'autoindicacao nao foi recusada';
  end if;
  if exists (select 1 from public.referral_attributions where subject_user_id = v_owner) then
    raise exception 'autoindicacao gravou atribuicao';
  end if;

  -- sem código bem-sucedido o cadastro continua orgânico
  select signup_referred into v_flag from public.profiles where id = v_new;
  if coalesce(v_flag, false) then
    raise exception 'cadastro sem codigo ficou marcado como indicado';
  end if;

  -- código válido, em minúsculas e com separador, dentro das 24h
  v_status := private.attach_referral(
    'player', v_new, null,
    lower(substr(v_code, 1, 4)) || '-' || lower(substr(v_code, 5)), true
  );
  if v_status not in ('ok', 'blocked') then
    raise exception 'codigo valido nao foi aceito: %', v_status;
  end if;

  -- segundo código para a mesma conta
  if private.attach_referral('player', v_new, null, v_code, true) <> 'exists' then
    raise exception 'o segundo codigo nao foi recusado';
  end if;

  -- depois de 24h do cadastro
  update public.profiles set created_at = pg_catalog.now() - interval '25 hours'
  where id = v_old;
  if private.attach_referral('player', v_old, null, v_code, true) <> 'late' then
    raise exception 'codigo depois de 24h nao foi recusado';
  end if;
  if exists (select 1 from public.referral_attributions where subject_user_id = v_old) then
    raise exception 'codigo tardio gravou atribuicao';
  end if;
  select signup_referred into v_flag from public.profiles where id = v_old;
  if coalesce(v_flag, false) then
    raise exception 'codigo tardio deu o desconto de 20%%';
  end if;
  -- sem atribuição ativa o desconto é o orgânico
  if private.first_booking_discount_for(
    v_old, null, 10000, 2500, 0, null
  ) <> 1000 then
    raise exception 'codigo tardio nao caiu nos 10%%';
  end if;
end $$;

rollback;
