-- O token cifrado não volta em claro para anon nem authenticated.
-- A service role lê pela função e não pela coluna.

\set ON_ERROR_STOP on

do $$
declare
  v_raw bytea;
begin
  select credit_card_token into v_raw
  from public.saved_cards
  where id = 'e1111111-1111-1111-1111-111111111111';
  if v_raw is null then
    raise exception 'cartão da Ana sumiu';
  end if;
  if position(pg_catalog.convert_to('tok_ana_nao_vaza', 'utf8') in v_raw) <> 0 then
    raise exception 'token em claro na coluna';
  end if;

  if has_column_privilege(
      'anon', 'public.saved_cards', 'credit_card_token', 'select'
    )
    or has_column_privilege(
      'authenticated', 'public.saved_cards', 'credit_card_token', 'select'
    )
    or has_column_privilege(
      'service_role', 'public.saved_cards', 'credit_card_token', 'select'
    )
    or has_table_privilege('service_role', 'public.saved_cards', 'insert')
  then
    raise exception 'a coluna do token ainda pode ser lida ou gravada direto';
  end if;

  if has_function_privilege('anon', 'private.card_token_key()', 'execute')
    or has_function_privilege('authenticated', 'private.card_token_key()', 'execute')
    or has_function_privilege('service_role', 'private.card_token_key()', 'execute')
    or has_function_privilege(
      'anon', 'public.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated', 'public.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'anon', 'private.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated', 'private.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'anon', 'public.insert_saved_card(uuid, text, text, text, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated',
      'public.insert_saved_card(uuid, text, text, text, text, uuid)',
      'execute'
    )
    or has_function_privilege(
      'anon', 'private.insert_saved_card(uuid, text, text, text, text, uuid)', 'execute'
    )
    or has_function_privilege(
      'authenticated',
      'private.insert_saved_card(uuid, text, text, text, text, uuid)',
      'execute'
    )
  then
    raise exception 'anon ou authenticated executa a cifra';
  end if;

  if not has_function_privilege(
      'service_role', 'public.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or not has_function_privilege(
      'service_role', 'private.load_owned_card(uuid, text, uuid)', 'execute'
    )
    or not has_function_privilege(
      'service_role',
      'public.insert_saved_card(uuid, text, text, text, text, uuid)',
      'execute'
    )
  then
    raise exception 'service role não executa a cifra';
  end if;

  if pg_get_function_result('public.my_saved_cards()'::regprocedure)
    ilike '%token%'
  then
    raise exception 'my_saved_cards passou a devolver o token';
  end if;
end $$;

begin;
set local role service_role;

do $$
declare
  v_token text;
  v_other integer;
begin
  select token into v_token
  from public.load_owned_card(
    'd1111111-1111-1111-1111-111111111111',
    'cus_ana',
    'e1111111-1111-1111-1111-111111111111'
  );
  if v_token is distinct from 'tok_ana_nao_vaza' then
    raise exception 'a service role não decifrou o próprio cartão';
  end if;

  select count(*) into v_other
  from public.load_owned_card(
    'd2222222-2222-2222-2222-222222222222',
    'cus_bruno',
    'e1111111-1111-1111-1111-111111111111'
  );
  if v_other <> 0 then
    raise exception 'o cartão da Ana abriu para o Bruno';
  end if;
end $$;

reset role;

do $$
declare
  v_leak text;
begin
  begin
    set local role anon;
    perform public.load_owned_card(
      'd1111111-1111-1111-1111-111111111111',
      'cus_ana',
      'e1111111-1111-1111-1111-111111111111'
    );
    raise exception 'anon chamou load_owned_card';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    set local role authenticated;
    perform private.card_token_key();
    raise exception 'authenticated leu a chave';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    set local role service_role;
    perform private.card_token_key();
    raise exception 'service role leu a chave';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    set local role anon;
    select s.decrypted_secret into v_leak
    from vault.decrypted_secrets s
    limit 1;
    raise exception 'anon leu o vault';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

rollback;
