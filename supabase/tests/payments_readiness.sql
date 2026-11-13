-- Prontidão e falha alta do cron de saques. Não fala com o Asaas
-- nem com a rede. O substituto de net.http_post só existe neste arquivo.

\set ON_ERROR_STOP on

insert into auth.users (id, email)
values
  ('c6111111-1111-4111-8111-111111111111', 'admin-pronto@example.com'),
  ('c6222222-2222-4222-8222-222222222222', 'jogador-pronto@example.com');

insert into public.admins (user_id)
values ('c6111111-1111-4111-8111-111111111111');

do $$
begin
  if has_function_privilege(
    'anon', 'public.admin_payments_readiness()', 'execute'
  ) or has_function_privilege(
    'service_role', 'public.admin_payments_readiness()', 'execute'
  ) or not has_function_privilege(
    'authenticated', 'public.admin_payments_readiness()', 'execute'
  ) then
    raise exception 'grant da prontidão saiu do combinado';
  end if;
  if has_function_privilege(
    'authenticated', 'private.venue_withdrawals_vault_flags()', 'execute'
  ) or has_function_privilege(
    'anon', 'private.invoke_venue_withdrawals()', 'execute'
  ) or has_function_privilege(
    'service_role', 'private.invoke_venue_withdrawals()', 'execute'
  ) then
    raise exception 'a função do cron ficou executável pela API';
  end if;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'c6222222-2222-4222-8222-222222222222', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  perform public.admin_payments_readiness();
  raise exception 'jogador leu a prontidão';
exception
  when others then
    if sqlerrm <> 'not admin' then
      raise;
    end if;
end $$;

do $$
begin
  perform set_config(
    'request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal1', true);
  set local role authenticated;
  perform public.admin_payments_readiness();
  raise exception 'admin sem aal2 leu a prontidão';
exception
  when others then
    if sqlerrm <> 'mfa obrigatorio' then
      raise;
    end if;
end $$;

do $$
begin
  perform private.invoke_venue_withdrawals();
  raise exception 'vault vazio não falhou';
exception
  when others then
    if sqlerrm not like 'venue_withdrawals_config_ausente:%' then
      raise;
    end if;
    if sqlerrm not like '%venue_withdrawals_url%'
      or sqlerrm not like '%venue_withdrawals_secret%'
    then
      raise exception 'a falha não citou os itens ausentes: %', sqlerrm;
    end if;
end $$;

select vault.create_secret(
  'url-secreta-nao-vazar',
  'venue_withdrawals_url',
  'teste'
);

do $$
begin
  perform private.invoke_venue_withdrawals();
  raise exception 'segredo do vault ausente não falhou';
exception
  when others then
    if sqlerrm <> 'venue_withdrawals_config_ausente: venue_withdrawals_secret' then
      raise exception 'mensagem inesperada: %', sqlerrm;
    end if;
    if sqlerrm like '%url-secreta-nao-vazar%' then
      raise exception 'a falha vazou o valor do vault';
    end if;
end $$;

do $$
declare
  v_report jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  v_report := public.admin_payments_readiness();
  if v_report ->> 'vault_venue_withdrawals_url' is distinct from 'true' then
    raise exception 'a url do vault não apareceu como presente';
  end if;
  if v_report ->> 'vault_venue_withdrawals_secret' is distinct from 'false' then
    raise exception 'o segredo ausente apareceu como presente';
  end if;
  if v_report::text like '%url-secreta-nao-vazar%'
    or v_report::text like '%decrypted%'
  then
    raise exception 'a prontidão devolveu valor de segredo';
  end if;
end $$;

select vault.create_secret(
  'segredo-cron-nao-vazar',
  'venue_withdrawals_secret',
  'teste'
);

create schema if not exists net;

create table net.ready_calls (
  url text,
  headers jsonb
);

create or replace function net.http_post(
  url text,
  body jsonb default '{}'::jsonb,
  params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint
language plpgsql
as $$
begin
  insert into net.ready_calls (url, headers) values (url, headers);
  return 1;
end;
$$;

do $$
declare
  v_url text;
  v_header text;
begin
  perform private.invoke_venue_withdrawals();
  select url, headers ->> 'x-venue-withdrawals-secret'
    into v_url, v_header
  from net.ready_calls;
  if v_url is distinct from 'url-secreta-nao-vazar'
    or v_header is distinct from 'segredo-cron-nao-vazar'
  then
    raise exception 'o cron configurado não disparou o pedido';
  end if;
  if (select count(*) from net.ready_calls) <> 1 then
    raise exception 'o cron disparou mais de uma vez';
  end if;
end $$;

do $$
declare
  v_report jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true
  );
  perform set_config('request.jwt.claim.aal', 'aal2', true);
  set local role authenticated;
  perform public.admin_set_venue_payouts_enabled(true);
  v_report := public.admin_payments_readiness();
  if v_report ->> 'venue_payouts_enabled' is distinct from 'true'
    or v_report ->> 'vault_venue_withdrawals_secret' is distinct from 'true'
  then
    raise exception 'a prontidão não viu flag e segredo: %', v_report;
  end if;
  if v_report::text like '%segredo-cron-nao-vazar%'
    or v_report::text like '%url-secreta-nao-vazar%'
  then
    raise exception 'a prontidão vazou o vault';
  end if;
  perform public.admin_set_venue_payouts_enabled(false);
  v_report := public.admin_payments_readiness();
  if v_report ->> 'venue_payouts_enabled' is distinct from 'false' then
    raise exception 'desligar a flag não apareceu na prontidão';
  end if;
end $$;

drop function if exists net.http_post(text, jsonb, jsonb, jsonb, integer);
drop table if exists net.ready_calls;
drop schema if exists net;
