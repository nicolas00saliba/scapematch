-- Conta de repasse Woovi e Mercado Pago. Não chama a rede.
-- O token OAuth não fica legível para anon nem authenticated.

\set ON_ERROR_STOP on

do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'provider_payout_accounts'
  ) then
    raise exception 'provider_payout_accounts ausente';
  end if;
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payment_charges'
      and column_name = 'provider_end_to_end_id'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payment_charges'
      and column_name = 'house_pix_key'
  ) then
    raise exception 'colunas do provedor ausentes em payment_charges';
  end if;
  if has_table_privilege('anon', 'public.provider_payout_accounts', 'select')
    or has_table_privilege('authenticated', 'public.provider_payout_accounts', 'select')
    or has_table_privilege('anon', 'private.provider_oauth_tokens', 'select')
    or has_table_privilege('authenticated', 'private.provider_oauth_tokens', 'select')
    or has_table_privilege('service_role', 'private.provider_oauth_tokens', 'select')
  then
    raise exception 'conta de repasse ou token ficou legível';
  end if;
  if has_function_privilege(
      'anon', 'public.read_provider_oauth(uuid, text)', 'execute'
    )
    or has_function_privilege(
      'authenticated', 'public.read_provider_oauth(uuid, text)', 'execute'
    )
    or not has_function_privilege(
      'service_role', 'public.read_provider_oauth(uuid, text)', 'execute'
    )
  then
    raise exception 'leitura do token OAuth saiu da service role';
  end if;
  if public.claim_provider_webhook('woovi', 'evt-teste-1') is not true then
    raise exception 'primeira entrega do webhook não entrou';
  end if;
  if public.claim_provider_webhook('woovi', 'evt-teste-1') is not false then
    raise exception 'webhook duplicado foi aceito de novo';
  end if;
end $$;
