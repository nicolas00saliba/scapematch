-- 20 cotações em 10 minutos. A 21ª não passa.
-- anon e authenticated não leem a tabela nem executam a função.
-- O total cobrado no cartão tem de ser o principal mais os juros.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'e5555555-5555-4555-8555-555555555555',
  'cotacao@example.com',
  '{"display_name":"Cotação"}'
);

do $$
begin
  if has_function_privilege(
    'anon', 'public.claim_installment_quote(uuid)', 'execute'
  )
  or has_function_privilege(
    'authenticated', 'public.claim_installment_quote(uuid)', 'execute'
  )
  or has_table_privilege(
    'anon', 'public.installment_quote_attempts', 'select'
  )
  or has_table_privilege(
    'authenticated', 'public.installment_quote_attempts', 'select'
  )
  then
    raise exception 'cotação de parcelas exposta na API';
  end if;
  if not has_function_privilege(
    'service_role', 'public.claim_installment_quote(uuid)', 'execute'
  )
  then
    raise exception 'service role não cota parcelas';
  end if;
end $$;

do $$
declare
  v_ok boolean;
  v_n int;
begin
  for v_n in 1..20 loop
    v_ok := public.claim_installment_quote(
      'e5555555-5555-4555-8555-555555555555'
    );
    if v_ok is not true then
      raise exception 'cotação % recusada cedo', v_n;
    end if;
  end loop;
  v_ok := public.claim_installment_quote(
    'e5555555-5555-4555-8555-555555555555'
  );
  if v_ok then
    raise exception 'a 21ª cotação passou';
  end if;
end $$;

do $$
begin
  if (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payment_charges'
      and column_name in ('charged_amount_cents', 'buyer_interest_cents')
  ) <> 2 then
    raise exception 'a cobrança não guarda o total com juros';
  end if;
end $$;
