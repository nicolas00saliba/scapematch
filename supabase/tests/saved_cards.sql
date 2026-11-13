-- Usuário B não lê o token do A e não vê o cartão do A.
-- A cobrança em si está no teste Deno cardForCharge.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('d1111111-1111-1111-1111-111111111111', 'carta@example.com', '{"display_name":"Ana"}'),
  ('d2222222-2222-2222-2222-222222222222', 'cartb@example.com', '{"display_name":"Bruno"}');

update public.profiles
set asaas_customer_id = 'cus_ana'
where id = 'd1111111-1111-1111-1111-111111111111';

update public.profiles
set asaas_customer_id = 'cus_bruno'
where id = 'd2222222-2222-2222-2222-222222222222';

select private.insert_saved_card(
  'd1111111-1111-1111-1111-111111111111',
  'cus_ana',
  'tok_ana_nao_vaza',
  '1111',
  'VISA',
  'e1111111-1111-1111-1111-111111111111'
);

select private.insert_saved_card(
  'd2222222-2222-2222-2222-222222222222',
  'cus_bruno',
  'tok_bruno_nao_vaza',
  '2222',
  'MASTERCARD',
  'e2222222-2222-2222-2222-222222222222'
);

do $$
begin
  if has_table_privilege('anon', 'public.saved_cards', 'select')
    or has_table_privilege('authenticated', 'public.saved_cards', 'select')
    or has_table_privilege('anon', 'public.saved_cards', 'insert')
    or has_table_privilege('authenticated', 'public.saved_cards', 'insert')
  then
    raise exception 'anon ou authenticated ainda acessa saved_cards';
  end if;

  if pg_get_function_result('public.my_saved_cards()'::regprocedure) ilike '%credit_card_token%'
  then
    raise exception 'my_saved_cards devolve o token';
  end if;

  if has_function_privilege('anon', 'public.my_saved_cards()', 'execute') then
    raise exception 'anon executa my_saved_cards';
  end if;

  if not has_function_privilege('authenticated', 'public.my_saved_cards()', 'execute') then
    raise exception 'authenticated não executa my_saved_cards';
  end if;
end $$;

select public.deactivate_customer_saved_cards(
  'd1111111-1111-1111-1111-111111111111',
  'cus_ana'
);

update public.profiles
set asaas_customer_id = 'cus_ana_nova'
where id = 'd1111111-1111-1111-1111-111111111111';

do $$
declare
  v_default text;
begin
  if not public.saved_card_needs_reregister(
    'd1111111-1111-1111-1111-111111111111',
    'e1111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'cartão órfão não pediu recadastro';
  end if;
  if public.saved_card_needs_reregister(
    'd2222222-2222-2222-2222-222222222222',
    'e2222222-2222-2222-2222-222222222222'
  ) then
    raise exception 'cartão ativo pediu recadastro';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.deactivate_customer_saved_cards(uuid, text)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.saved_card_needs_reregister(uuid, uuid)',
    'execute'
  ) then
    raise exception 'authenticated desativa cartão ou lê recadastro';
  end if;
  select column_default into v_default
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'venues'
    and column_name = 'company_type';
  if v_default is null or position('LIMITED' in v_default) = 0 then
    raise exception 'company_type sem default LIMITED: %', v_default;
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', 'd2222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_count integer;
  v_last4 text;
  v_brand text;
begin
  select count(*) into v_count from public.my_saved_cards();
  if v_count <> 1 then
    raise exception 'B viu % cartões', v_count;
  end if;
  select last4, brand into v_last4, v_brand from public.my_saved_cards();
  if v_last4 <> '2222' or v_brand <> 'MASTERCARD' then
    raise exception 'B não viu o próprio cartão';
  end if;
  if exists (
    select 1 from public.my_saved_cards()
    where last4 = '1111' or id = 'e1111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'B viu o cartão do A';
  end if;
end $$;

do $$
begin
  perform credit_card_token from public.saved_cards;
  raise exception 'authenticated leu o token';
exception
  when insufficient_privilege then
    null;
end $$;

reset role;
commit;
