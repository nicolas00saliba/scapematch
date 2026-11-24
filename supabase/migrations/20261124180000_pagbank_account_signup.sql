-- Cadastro de conta PagBank da casa. Não aplicar no projeto remoto neste PR.
--
-- Modo A (api_enabled falso, o padrão): a casa cria a conta em
-- https://cadastro.pagbank.com.br/ e segue no Connect. O banco guarda
-- só o tipo do documento, a categoria e o aceite. Não guarda CPF, CNPJ,
-- endereço, nascimento, telefone nem e-mail.
--
-- Modo B: a Edge Function pagbank-signup chama POST /accounts. Aqui fica
-- o id ACCO_ e o status. Os documentos não são coluna.
--
-- Sonda a cada 6 horas (minuto 15). POST /accounts com {"type":"SELLER"},
-- sem os outros campos, para não criar conta. A flag só liga se a função
-- apply receber enable e o código 40001 ou 40002. 401, 403, 404 e 2xx
-- não ligam. held_off, gravado pelo admin com aal2, impede a ligação.
-- O cron não posta o segredo se a URL do Vault não for a desta função.

create or replace function private.pagbank_business_category_ok(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_value = any (array[
    'BUTCHERY', 'LEGAL_SERVICE', 'TAILOR_AND_SEAMSTRESS', 'ITINERANT_SALE',
    'ARCHITECTURAL_AND_ENGINEERING', 'ART_AND_ANTIQUE', 'RELIGION_AND_SPIRITUALITY',
    'VEHICLE_AND_PARTS', 'BABY', 'VEHICLE_SERVICES', 'BEAUTY_AND_BARBER',
    'BED_AND_BATH', 'TELECOMMUNICATION', 'KEY_CHAIN', 'PACKAGE_STORE',
    'FOOD_SERVICE', 'ADULT_CONTENT', 'REAL_ESTATE_AGENT', 'BROKER', 'DENTISTRY',
    'FREIGHT_FORWARDER', 'CANDIES_AND_CONFECTIONERIES', 'HOUSEHOLD_APPLIANCE',
    'GENERAL_CONTRACTOR', 'GOVERNMENT', 'SPORT', 'HEALTH_AND_BEAUTY_SERVICE',
    'NONDURABLE_GOODS', 'MEDICAL_SERVICE', 'PHOTOGRAPHY_AND_VIDEO', 'SUPERMARKET',
    'LODGING', 'FLORIST', 'JEWELRY_AND_WATCH', 'OTHER_SERVICES', 'DOCTOR',
    'FURNITURE_AND_DECORATION', 'BAKERY', 'PERSONAL_TRAINER', 'PET_SUPPLIES',
    'PODIATRIST_AND_CHIROPODIST', 'REPAIR_SHOPS', 'RESTAURANT',
    'CLOTHING_AND_ACCESSORIES', 'SHOE_STORE', 'EDUCATION', 'ENTERTAINMENT',
    'PROFESSIONAL_SERVICE', 'TATTOOIST', 'TRANSPORTATION_SERVICE',
    'DOOR_TO_DOOR_SALES', 'VETERINARY_SERVICE'
  ]::text[])
$$;

revoke all on function private.pagbank_business_category_ok(text)
  from public, anon, authenticated, service_role;

create table public.pagbank_signup_settings (
  id integer primary key default 1 check (id = 1),
  api_enabled boolean not null default false,
  held_off boolean not null default false,
  detected_at timestamptz,
  last_probe_at timestamptz,
  last_probe_http integer,
  last_probe_code text,
  updated_at timestamptz not null default pg_catalog.now(),
  check (last_probe_code is null or last_probe_code ~ '^[a-z0-9_]{1,48}$'),
  check (last_probe_http is null or last_probe_http between 0 and 599)
);

insert into public.pagbank_signup_settings (id) values (1);

comment on table public.pagbank_signup_settings is
  'Modo B do cadastro PagBank. Nasce desligado. O cron só liga com 40001 ou 40002. held_off é o desligamento do admin aal2.';

create table public.venue_pagbank_signups (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  mode text not null check (mode in ('manual', 'api')),
  document_kind text not null check (document_kind in ('cpf', 'cnpj')),
  business_category text not null,
  terms_accepted_at timestamptz not null,
  pagbank_account_id text,
  account_status text not null check (
    account_status in ('guided', 'pending_activation', 'exists')
  ),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (private.pagbank_business_category_ok(business_category)),
  check (
    pagbank_account_id is null
    or pagbank_account_id ~ '^ACCO_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
  ),
  check (
    (mode = 'manual' and account_status = 'guided' and pagbank_account_id is null)
    or (
      mode = 'api'
      and account_status = 'pending_activation'
      and pagbank_account_id is not null
    )
    or (mode = 'api' and account_status = 'exists' and pagbank_account_id is null)
  )
);

comment on table public.venue_pagbank_signups is
  'Jornada de cadastro PagBank sem CPF, CNPJ, endereço ou contato. O id ACCO_ só existe depois do POST /accounts.';

create table public.pagbank_signup_events (
  id bigint generated always as identity primary key,
  venue_id uuid references public.venues (id) on delete cascade,
  kind text not null check (kind ~ '^[a-z0-9_]{1,48}$'),
  code text not null check (code ~ '^[a-z0-9_]{1,48}$'),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.pagbank_signup_events is
  'Evento da sonda ou do interruptor. Sem documento, e-mail ou corpo da PagBank.';

alter table public.pagbank_signup_settings enable row level security;
alter table public.venue_pagbank_signups enable row level security;
alter table public.pagbank_signup_events enable row level security;

revoke all on table public.pagbank_signup_settings
  from public, anon, authenticated, service_role;
revoke all on table public.venue_pagbank_signups
  from public, anon, authenticated, service_role;
revoke all on table public.pagbank_signup_events
  from public, anon, authenticated, service_role;

create or replace function private.pagbank_signup_state()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'api_enabled', s.api_enabled,
    'held_off', s.held_off,
    'detected_at', s.detected_at,
    'last_probe_at', s.last_probe_at,
    'last_probe_http', s.last_probe_http,
    'last_probe_code', s.last_probe_code
  )
  from public.pagbank_signup_settings s
  where s.id = 1;
$$;

revoke all on function private.pagbank_signup_state()
  from public, anon, authenticated, service_role;

create or replace function public.pagbank_signup_for_venue(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_status text;
  v_signup public.venue_pagbank_signups%rowtype;
  v_enabled boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select v.owner_id, v.status into v_owner, v_status
  from public.venues v
  where v.id = p_venue_id;
  if v_owner is null
    or (v_owner is distinct from auth.uid() and not private.is_admin_aal2())
  then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_status is distinct from 'approved' and not private.is_admin_aal2() then
    raise exception 'casa' using errcode = 'P0001';
  end if;
  select s.api_enabled into v_enabled
  from public.pagbank_signup_settings s
  where s.id = 1;
  select * into v_signup
  from public.venue_pagbank_signups row
  where row.venue_id = p_venue_id;
  return pg_catalog.jsonb_build_object(
    'api_enabled', coalesce(v_enabled, false),
    'signup', case
      when v_signup.venue_id is null then null
      else pg_catalog.jsonb_build_object(
        'mode', v_signup.mode,
        'document_kind', v_signup.document_kind,
        'business_category', v_signup.business_category,
        'account_status', v_signup.account_status,
        'pagbank_account_id', v_signup.pagbank_account_id,
        'terms_accepted_at', v_signup.terms_accepted_at
      )
    end
  );
end;
$$;

revoke all on function public.pagbank_signup_for_venue(uuid)
  from public, anon, service_role;
grant execute on function public.pagbank_signup_for_venue(uuid) to authenticated;

create or replace function public.record_pagbank_signup_guide(
  p_venue_id uuid,
  p_document_kind text,
  p_business_category text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_status text;
  v_enabled boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select v.owner_id, v.status into v_owner, v_status
  from public.venues v
  where v.id = p_venue_id;
  if v_owner is null
    or (v_owner is distinct from auth.uid() and not private.is_admin_aal2())
  then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_status is distinct from 'approved' then
    raise exception 'casa' using errcode = 'P0001';
  end if;
  if p_document_kind is distinct from 'cpf'
    and p_document_kind is distinct from 'cnpj'
  then
    raise exception 'documento' using errcode = 'P0001';
  end if;
  if not private.pagbank_business_category_ok(p_business_category) then
    raise exception 'categoria' using errcode = 'P0001';
  end if;
  select s.api_enabled into v_enabled
  from public.pagbank_signup_settings s
  where s.id = 1
  for update;
  if coalesce(v_enabled, false) then
    raise exception 'modo_api' using errcode = 'P0001';
  end if;
  if exists (
    select 1
    from public.venue_pagbank_signups row
    where row.venue_id = p_venue_id
      and (
        row.pagbank_account_id is not null
        or row.account_status = 'exists'
      )
  ) then
    raise exception 'conta_criada' using errcode = 'P0001';
  end if;
  insert into public.venue_pagbank_signups (
    venue_id, mode, document_kind, business_category, terms_accepted_at,
    pagbank_account_id, account_status
  ) values (
    p_venue_id, 'manual', p_document_kind, p_business_category,
    pg_catalog.now(), null, 'guided'
  )
  on conflict (venue_id) do update
  set mode = 'manual',
      document_kind = excluded.document_kind,
      business_category = excluded.business_category,
      terms_accepted_at = pg_catalog.now(),
      pagbank_account_id = null,
      account_status = 'guided',
      updated_at = pg_catalog.now()
  where public.venue_pagbank_signups.pagbank_account_id is null
    and public.venue_pagbank_signups.account_status is distinct from 'exists';
  insert into public.pagbank_signup_events (venue_id, kind, code)
  values (p_venue_id, 'signup_guided', 'manual');
  return public.pagbank_signup_for_venue(p_venue_id);
end;
$$;

revoke all on function public.record_pagbank_signup_guide(uuid, text, text)
  from public, anon, service_role;
grant execute on function public.record_pagbank_signup_guide(uuid, text, text)
  to authenticated;

create or replace function public.pagbank_signup_api_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select s.api_enabled
  from public.pagbank_signup_settings s
  where s.id = 1;
$$;

revoke all on function public.pagbank_signup_api_enabled()
  from public, anon, authenticated;
grant execute on function public.pagbank_signup_api_enabled() to service_role;

create or replace function public.venue_pagbank_account_id(p_venue_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select row.pagbank_account_id
  from public.venue_pagbank_signups row
  where row.venue_id = p_venue_id;
$$;

revoke all on function public.venue_pagbank_account_id(uuid)
  from public, anon, authenticated;
grant execute on function public.venue_pagbank_account_id(uuid) to service_role;

create or replace function public.save_venue_pagbank_signup(
  p_venue_id uuid,
  p_document_kind text,
  p_business_category text,
  p_account_id text,
  p_account_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account text := nullif(pg_catalog.btrim(coalesce(p_account_id, '')), '');
begin
  if not exists (select 1 from public.venues v where v.id = p_venue_id) then
    raise exception 'casa' using errcode = 'P0001';
  end if;
  if p_document_kind is distinct from 'cpf'
    and p_document_kind is distinct from 'cnpj'
  then
    raise exception 'documento' using errcode = 'P0001';
  end if;
  if not private.pagbank_business_category_ok(p_business_category) then
    raise exception 'categoria' using errcode = 'P0001';
  end if;
  if p_account_status is distinct from 'pending_activation'
    and p_account_status is distinct from 'exists'
  then
    raise exception 'status' using errcode = 'P0001';
  end if;
  if p_account_status = 'pending_activation' and (
    v_account is null
    or v_account !~ '^ACCO_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
  ) then
    raise exception 'conta' using errcode = 'P0001';
  end if;
  if p_account_status = 'exists' and v_account is not null then
    raise exception 'conta' using errcode = 'P0001';
  end if;
  insert into public.venue_pagbank_signups (
    venue_id, mode, document_kind, business_category, terms_accepted_at,
    pagbank_account_id, account_status
  ) values (
    p_venue_id, 'api', p_document_kind, p_business_category, pg_catalog.now(),
    v_account, p_account_status
  )
  on conflict (venue_id) do update
  set mode = 'api',
      document_kind = excluded.document_kind,
      business_category = excluded.business_category,
      pagbank_account_id = coalesce(
        public.venue_pagbank_signups.pagbank_account_id,
        excluded.pagbank_account_id
      ),
      account_status = case
        when public.venue_pagbank_signups.pagbank_account_id is not null
          then 'pending_activation'
        else excluded.account_status
      end,
      updated_at = pg_catalog.now();
  insert into public.pagbank_signup_events (venue_id, kind, code)
  values (p_venue_id, 'signup_api', p_account_status);
end;
$$;

revoke all on function public.save_venue_pagbank_signup(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.save_venue_pagbank_signup(uuid, text, text, text, text)
  to service_role;

create or replace function public.apply_pagbank_signup_probe(
  p_http integer,
  p_code text,
  p_enable boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_held boolean;
  v_enabled boolean;
  v_changed boolean := false;
  v_turn_on boolean;
  v_kind text;
begin
  if p_code is null or p_code !~ '^[a-z0-9_]{1,48}$' then
    raise exception 'codigo' using errcode = 'P0001';
  end if;
  if p_http is null or p_http < 0 or p_http > 599 then
    raise exception 'http' using errcode = 'P0001';
  end if;
  select s.held_off, s.api_enabled into v_held, v_enabled
  from public.pagbank_signup_settings s
  where s.id = 1
  for update;
  v_turn_on := coalesce(p_enable, false)
    and p_code in ('40001', '40002')
    and not coalesce(v_held, false)
    and not coalesce(v_enabled, false);
  update public.pagbank_signup_settings s
  set api_enabled = case when v_turn_on then true else s.api_enabled end,
      detected_at = case
        when v_turn_on then pg_catalog.now()
        else s.detected_at
      end,
      last_probe_at = pg_catalog.now(),
      last_probe_http = p_http,
      last_probe_code = p_code,
      updated_at = pg_catalog.now()
  where s.id = 1;
  v_changed := v_turn_on;
  v_kind := case
    when p_code = 'probe_criou_conta' then 'probe_criou_conta'
    when coalesce(p_enable, false) and coalesce(v_held, false) then 'probe_held'
    when v_changed then 'probe_enabled'
    else 'probe_closed'
  end;
  insert into public.pagbank_signup_events (venue_id, kind, code)
  values (null, v_kind, p_code);
  return pg_catalog.jsonb_build_object(
    'enabled', coalesce(v_enabled, false) or v_changed,
    'changed', v_changed,
    'held_off', coalesce(v_held, false)
  );
end;
$$;

revoke all on function public.apply_pagbank_signup_probe(integer, text, boolean)
  from public, anon, authenticated;
grant execute on function public.apply_pagbank_signup_probe(integer, text, boolean)
  to service_role;

create or replace function public.admin_pagbank_signup_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return private.pagbank_signup_state();
end;
$$;

revoke all on function public.admin_pagbank_signup_settings()
  from public, anon, service_role;
grant execute on function public.admin_pagbank_signup_settings() to authenticated;

create or replace function public.admin_disable_pagbank_signup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_before jsonb;
begin
  v_actor := private.admin_require();
  v_before := private.pagbank_signup_state();
  update public.pagbank_signup_settings
  set api_enabled = false,
      held_off = true,
      updated_at = pg_catalog.now()
  where id = 1;
  perform private.admin_audit(
    v_actor,
    'disable_pagbank_signup',
    'pagbank_signup_settings',
    '1',
    v_before,
    private.pagbank_signup_state()
  );
  insert into public.pagbank_signup_events (venue_id, kind, code)
  values (null, 'admin_hold', 'held_off');
  return private.pagbank_signup_state();
end;
$$;

revoke all on function public.admin_disable_pagbank_signup()
  from public, anon, service_role;
grant execute on function public.admin_disable_pagbank_signup() to authenticated;

create or replace function public.admin_release_pagbank_signup_hold()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_before jsonb;
begin
  v_actor := private.admin_require();
  v_before := private.pagbank_signup_state();
  update public.pagbank_signup_settings
  set held_off = false,
      updated_at = pg_catalog.now()
  where id = 1;
  perform private.admin_audit(
    v_actor,
    'release_pagbank_signup_hold',
    'pagbank_signup_settings',
    '1',
    v_before,
    private.pagbank_signup_state()
  );
  insert into public.pagbank_signup_events (venue_id, kind, code)
  values (null, 'admin_release', 'hold_cleared');
  return private.pagbank_signup_state();
end;
$$;

revoke all on function public.admin_release_pagbank_signup_hold()
  from public, anon, service_role;
grant execute on function public.admin_release_pagbank_signup_hold() to authenticated;

create or replace function public.cron_vault_secret(p_name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  if p_name is distinct from 'venue_withdrawals_secret'
    and p_name is distinct from 'ledger_reconcile_secret'
    and p_name is distinct from 'pagbank_signup_probe_secret'
  then
    return null;
  end if;
  select pg_catalog.btrim(s.decrypted_secret) into v_secret
  from vault.decrypted_secrets s
  where s.name = p_name
  limit 1;
  if v_secret is null or v_secret = '' then
    return null;
  end if;
  return v_secret;
end;
$$;

revoke all on function public.cron_vault_secret(text)
  from public, anon, authenticated;
grant execute on function public.cron_vault_secret(text) to service_role;

create or replace function private.invoke_pagbank_signup_probe()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_ok boolean;
begin
  select pg_catalog.btrim(s.decrypted_secret) into v_url
  from vault.decrypted_secrets s
  where s.name = 'pagbank_signup_probe_url'
  limit 1;
  select pg_catalog.btrim(s.decrypted_secret) into v_secret
  from vault.decrypted_secrets s
  where s.name = 'pagbank_signup_probe_secret'
  limit 1;
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    insert into public.pagbank_signup_events (venue_id, kind, code)
    values (null, 'probe_closed', 'config_ausente');
    return;
  end if;
  v_ok := v_url ~ '^https://[a-z0-9-]+\.supabase\.co/functions/v1/pagbank-signup-probe$'
    or v_url ~ '^http://(127\.0\.0\.1|localhost|kong)(:[0-9]+)?/functions/v1/pagbank-signup-probe$';
  if not v_ok then
    insert into public.pagbank_signup_events (venue_id, kind, code)
    values (null, 'probe_closed', 'probe_url_recusada');
    return;
  end if;
  if not exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net') then
    insert into public.pagbank_signup_events (venue_id, kind, code)
    values (null, 'probe_closed', 'probe_sem_rede');
    return;
  end if;
  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := pg_catalog.jsonb_build_object(
      'Content-Type', 'application/json',
      'x-pagbank-signup-probe-secret', v_secret
    ),
    timeout_milliseconds := 20000
  );
end;
$$;

revoke all on function private.invoke_pagbank_signup_probe()
  from public, anon, authenticated, service_role;

comment on function private.invoke_pagbank_signup_probe() is
  'Chama a sonda a cada 6 horas. Sem os itens do Vault, não posta e não cria conta.';

do $cron$
begin
  if exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_catalog.pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    if exists (
      select 1 from cron.job where jobname = 'pagbank-signup-probe'
    ) then
      perform cron.unschedule('pagbank-signup-probe');
    end if;
    perform cron.schedule(
      'pagbank-signup-probe',
      '15 */6 * * *',
      'select private.invoke_pagbank_signup_probe()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; pagbank-signup-probe não foi agendado';
  end if;
end
$cron$;

comment on table public.venue_payouts_settings is
  'Flag histórica dos saques. Continua desligada. O valor fica na conta PagBank da casa. A Edge Function também recusa o saque.';

update public.venue_payouts_settings
set enabled = false,
    updated_at = pg_catalog.now()
where id = 1
  and enabled is true;
