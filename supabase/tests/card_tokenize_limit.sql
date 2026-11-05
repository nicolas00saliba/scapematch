-- O 6º cartão e a 6ª tentativa na hora não passam.
-- anon e authenticated não leem a tabela nem executam a função.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('d3333333-3333-3333-3333-333333333333', 'cartc@example.com', '{"display_name":"Carla"}'),
  ('d4444444-4444-4444-4444-444444444444', 'cartd@example.com', '{"display_name":"Dora"}');

update public.profiles
set asaas_customer_id = 'cus_carla'
where id = 'd3333333-3333-3333-3333-333333333333';

update public.profiles
set asaas_customer_id = 'cus_dora'
where id = 'd4444444-4444-4444-4444-444444444444';

insert into public.saved_cards (
  id, user_id, asaas_customer_id, credit_card_token, last4, brand
)
values
  ('f3333333-3333-3333-3333-333333333331', 'd3333333-3333-3333-3333-333333333333', 'cus_carla', 'tok_carla_1', '3331', 'VISA'),
  ('f3333333-3333-3333-3333-333333333332', 'd3333333-3333-3333-3333-333333333333', 'cus_carla', 'tok_carla_2', '3332', 'VISA'),
  ('f3333333-3333-3333-3333-333333333333', 'd3333333-3333-3333-3333-333333333333', 'cus_carla', 'tok_carla_3', '3333', 'VISA'),
  ('f3333333-3333-3333-3333-333333333334', 'd3333333-3333-3333-3333-333333333333', 'cus_carla', 'tok_carla_4', '3334', 'VISA'),
  ('f3333333-3333-3333-3333-333333333335', 'd3333333-3333-3333-3333-333333333333', 'cus_carla', 'tok_carla_5', '3335', 'VISA');

insert into public.card_tokenize_attempts (user_id, created_at)
select 'd4444444-4444-4444-4444-444444444444', pg_catalog.now() - interval '2 hours'
from generate_series(1, 5);

do $$
begin
  if has_table_privilege('anon', 'public.card_tokenize_attempts', 'select')
    or has_table_privilege('authenticated', 'public.card_tokenize_attempts', 'select')
    or has_table_privilege('anon', 'public.card_tokenize_attempts', 'insert')
    or has_table_privilege('authenticated', 'public.card_tokenize_attempts', 'insert')
    or has_table_privilege('service_role', 'public.card_tokenize_attempts', 'select')
  then
    raise exception 'a tabela de tentativas está aberta';
  end if;

  if has_function_privilege('anon', 'private.claim_card_tokenize_attempt(uuid)', 'execute')
    or has_function_privilege('authenticated', 'private.claim_card_tokenize_attempt(uuid)', 'execute')
    or has_function_privilege('anon', 'public.claim_card_tokenize_attempt(uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.claim_card_tokenize_attempt(uuid)', 'execute')
  then
    raise exception 'anon ou authenticated executa o limite';
  end if;

  if not has_function_privilege('service_role', 'private.claim_card_tokenize_attempt(uuid)', 'execute')
    or not has_function_privilege('service_role', 'public.claim_card_tokenize_attempt(uuid)', 'execute')
  then
    raise exception 'service role não executa o limite';
  end if;
end $$;

do $$
begin
  begin
    insert into public.saved_cards (
      id, user_id, asaas_customer_id, credit_card_token, last4, brand
    )
    values (
      'f3333333-3333-3333-3333-333333333336',
      'd3333333-3333-3333-3333-333333333333',
      'cus_carla',
      'tok_carla_6',
      '3336',
      'VISA'
    );
    raise exception 'o 6º cartão entrou';
  exception
    when others then
      if sqlerrm not like '%limite de cartões%' then
        raise;
      end if;
  end;
end $$;

begin;
set local role service_role;

do $$
declare
  v_ok boolean;
  v_i integer;
begin
  v_ok := private.claim_card_tokenize_attempt('d3333333-3333-3333-3333-333333333333');
  if v_ok then
    raise exception 'o 6º cartão foi aceito';
  end if;

  for v_i in 1..5 loop
    v_ok := public.claim_card_tokenize_attempt('d4444444-4444-4444-4444-444444444444');
    if not v_ok then
      raise exception 'tentativa % recusada', v_i;
    end if;
  end loop;

  v_ok := public.claim_card_tokenize_attempt('d4444444-4444-4444-4444-444444444444');
  if v_ok then
    raise exception 'a 6ª tentativa passou';
  end if;
end $$;

reset role;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.saved_cards
  where user_id = 'd3333333-3333-3333-3333-333333333333';
  if v_count <> 5 then
    raise exception 'Carla ficou com % cartões', v_count;
  end if;

  select count(*) into v_count
  from public.card_tokenize_attempts
  where user_id = 'd4444444-4444-4444-4444-444444444444';
  if v_count <> 6 then
    raise exception 'Dora ficou com % tentativas na hora', v_count;
  end if;
end $$;

do $$
begin
  begin
    set local role anon;
    perform public.claim_card_tokenize_attempt('d4444444-4444-4444-4444-444444444444');
    raise exception 'anon chamou o limite';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

rollback;
