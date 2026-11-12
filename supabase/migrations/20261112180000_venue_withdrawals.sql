-- Saque da casa para a conta bancária dela. A flag nasce desligada.
-- Não aplicar no projeto remoto neste PR.
--
-- O split e a comissão não mudam. O dinheiro já está na subconta Asaas
-- da casa (walletId). O saque é uma transferência dessa subconta, com a
-- chave dela, para Pix ou TED de mesma titularidade.
--
-- A subconta Reserva de pontos não é uma casa: não tem linha aqui,
-- não tem conta bancária e nenhuma função desta migration a movimenta.
-- A Edge Function ainda recusa a wallet e a chave dessa reserva.

create table public.venue_payouts_settings (
  id integer primary key default 1 check (id = 1),
  enabled boolean not null default false,
  updated_at timestamptz,
  updated_by uuid
);

insert into public.venue_payouts_settings (id, enabled)
values (1, false);

comment on table public.venue_payouts_settings is
  'Flag dos saques da casa. enabled nasce falso. Sem isso, nada saca nem grava conta.';

create table public.venue_bank_accounts (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  destination text not null check (destination in ('pix', 'bank')),
  pix_key text,
  pix_key_type text check (
    pix_key_type is null
    or pix_key_type in ('CPF', 'CNPJ', 'EMAIL', 'PHONE', 'EVP')
  ),
  bank_code text,
  agency text,
  account_number text,
  account_digit text,
  owner_name text not null check (char_length(owner_name) between 2 and 120),
  owner_document text not null,
  operation_type text not null check (operation_type in ('PIX', 'TED')),
  withdrawals_blocked_until timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null,
  check (
    (destination = 'pix' and operation_type = 'PIX' and pix_key is not null and pix_key_type is not null)
    or (
      destination = 'bank'
      and bank_code is not null
      and agency is not null
      and account_number is not null
      and account_digit is not null
    )
  )
);

comment on table public.venue_bank_accounts is
  'Destino do saque. O documento do titular tem de ser o da casa. Trocar a conta bloqueia saques por 24 horas.';

create table public.venue_payout_schedules (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  enabled boolean not null default false,
  frequency text not null check (frequency in ('daily', 'weekly')),
  weekday smallint check (weekday between 0 and 6),
  min_amount_cents integer not null check (min_amount_cents >= 0),
  updated_at timestamptz not null default pg_catalog.now(),
  updated_by uuid not null,
  check (
    (frequency = 'daily' and weekday is null)
    or (frequency = 'weekly' and weekday is not null)
  )
);

comment on table public.venue_payout_schedules is
  'Saque automático. weekday 0 é domingo, no fuso America/Sao_Paulo. O cron não duplica o período.';

create table public.venue_withdrawals (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  status text not null check (status in ('pending', 'done', 'failed', 'cancelled')),
  source text not null check (source in ('manual', 'automatic')),
  period_key text not null check (char_length(period_key) between 8 and 80),
  external_reference text not null unique,
  asaas_transfer_id text unique,
  receipt_url text check (receipt_url is null or receipt_url ~ '^https://'),
  failure_reason text check (failure_reason is null or char_length(failure_reason) <= 80),
  requested_by uuid,
  dispatch_started_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (venue_id, period_key)
);

comment on table public.venue_withdrawals is
  'Um saque por período automático (period_key). O manual usa uma chave própria. O comprovante é a URL https do Asaas.';

create index venue_withdrawals_by_venue
  on public.venue_withdrawals (venue_id, created_at desc);

create table public.venue_payout_audit (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  actor_id uuid,
  action text not null check (action in (
    'request_withdrawal',
    'automatic_withdrawal',
    'save_bank_account',
    'save_payout_schedule'
  )),
  withdrawal_id uuid,
  summary text not null check (char_length(summary) between 1 and 120),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.venue_payout_audit is
  'Quem pediu o saque e quem trocou a conta ou a agenda. Sem chave Pix, sem documento e sem apiKey.';

create table public.venue_payout_notices (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  owner_id uuid,
  kind text not null check (kind in (
    'withdrawal_done',
    'withdrawal_failed',
    'bank_changed'
  )),
  body text not null check (char_length(body) between 1 and 400),
  created_at timestamptz not null default pg_catalog.now(),
  sent_at timestamptz
);

comment on table public.venue_payout_notices is
  'Aviso ao dono. O e-mail sai na Edge Function. Sem endereço e sem chave nesta tabela.';

alter table public.venue_payouts_settings enable row level security;
alter table public.venue_bank_accounts enable row level security;
alter table public.venue_payout_schedules enable row level security;
alter table public.venue_withdrawals enable row level security;
alter table public.venue_payout_audit enable row level security;
alter table public.venue_payout_notices enable row level security;

revoke all on table public.venue_payouts_settings from public, anon, authenticated, service_role;
revoke all on table public.venue_bank_accounts from public, anon, authenticated, service_role;
revoke all on table public.venue_payout_schedules from public, anon, authenticated, service_role;
revoke all on table public.venue_withdrawals from public, anon, authenticated, service_role;
revoke all on table public.venue_payout_audit from public, anon, authenticated, service_role;
revoke all on table public.venue_payout_notices from public, anon, authenticated, service_role;

create or replace function private.only_digits(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.regexp_replace(coalesce(p_text, ''), '[^0-9]', '', 'g');
$$;

revoke all on function private.only_digits(text) from public, anon, authenticated, service_role;

create or replace function private.venue_treasurer(p_venue_id uuid, p_actor uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_actor is not null and (
    exists (
      select 1
      from public.venues
      where id = p_venue_id
        and owner_id = p_actor
    )
    or exists (
      select 1
      from public.venue_staff
      where venue_id = p_venue_id
        and user_id = p_actor
        and role = 'partner'
        and status = 'accepted'
    )
  );
$$;

comment on function private.venue_treasurer(uuid, uuid) is
  'Dono ou sócio aceito (admin da casa). Equipe (staff) não saca.';

revoke all on function private.venue_treasurer(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.venue_treasurer(uuid, uuid) to authenticated;

create or replace function private.venue_payout_role(p_venue_id uuid, p_actor uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_actor is not null and exists (
      select 1 from public.venues
      where id = p_venue_id and owner_id = p_actor
    ) then 'owner'
    when p_actor is not null and exists (
      select 1 from public.venue_staff
      where venue_id = p_venue_id
        and user_id = p_actor
        and role = 'partner'
        and status = 'accepted'
    ) then 'partner'
    when p_actor is not null and exists (
      select 1 from public.venue_staff
      where venue_id = p_venue_id
        and user_id = p_actor
        and role = 'staff'
        and status = 'accepted'
    ) then 'staff'
    else 'none'
  end;
$$;

revoke all on function private.venue_payout_role(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.venue_payouts_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select enabled from public.venue_payouts_settings where id = 1),
    false
  );
$$;

revoke all on function public.venue_payouts_enabled() from public, anon, service_role;
grant execute on function public.venue_payouts_enabled() to authenticated;

create or replace function private.venue_payouts_require()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.venue_payouts_enabled() then
    raise exception 'saques desligados' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.venue_payouts_require()
  from public, anon, authenticated, service_role;

create or replace function private.mask_tail(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_text is null or p_text = '' then null
    when char_length(p_text) <= 4 then pg_catalog.repeat('*', char_length(p_text))
    else pg_catalog.repeat('*', char_length(p_text) - 4) || pg_catalog.right(p_text, 4)
  end;
$$;

revoke all on function private.mask_tail(text)
  from public, anon, authenticated, service_role;

create or replace function public.venue_payout_period_key(
  p_frequency text,
  p_at timestamptz
)
returns text
language sql
stable
set search_path = ''
as $$
  select case p_frequency
    when 'daily' then 'auto:' || pg_catalog.to_char(
      p_at at time zone 'America/Sao_Paulo', 'YYYY-MM-DD'
    )
    when 'weekly' then 'auto:' || pg_catalog.to_char(
      p_at at time zone 'America/Sao_Paulo', 'IYYY-"W"IW'
    )
    else null
  end;
$$;

revoke all on function public.venue_payout_period_key(text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.venue_payout_period_key(text, timestamptz) to service_role;

create or replace function private.sao_paulo_weekday(p_at timestamptz)
returns integer
language sql
stable
set search_path = ''
as $$
  select pg_catalog.date_part(
    'dow', p_at at time zone 'America/Sao_Paulo'
  )::integer;
$$;

revoke all on function private.sao_paulo_weekday(timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.venue_payout_snapshot(
  p_venue_id uuid,
  p_actor uuid,
  p_as_admin boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := private.venue_payout_role(p_venue_id, p_actor);
  v_enabled boolean := public.venue_payouts_enabled();
  v_bank public.venue_bank_accounts%rowtype;
  v_schedule public.venue_payout_schedules%rowtype;
  v_rows jsonb;
  v_pending integer;
begin
  if v_role = 'none' and not coalesce(p_as_admin, false) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  if v_role = 'none' and coalesce(p_as_admin, false) then
    v_role := 'admin';
  end if;
  if not v_enabled then
    return pg_catalog.jsonb_build_object(
      'enabled', false,
      'can_withdraw', false,
      'role', v_role
    );
  end if;
  if v_role = 'staff' then
    return pg_catalog.jsonb_build_object(
      'enabled', true,
      'can_withdraw', false,
      'role', 'staff'
    );
  end if;

  select * into v_bank
  from public.venue_bank_accounts
  where venue_id = p_venue_id;

  select * into v_schedule
  from public.venue_payout_schedules
  where venue_id = p_venue_id;

  select coalesce(pg_catalog.sum(amount_cents), 0)::integer
    into v_pending
  from public.venue_withdrawals
  where venue_id = p_venue_id
    and status = 'pending';

  select coalesce(pg_catalog.jsonb_agg(item.payload order by item.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      created_at,
      pg_catalog.jsonb_build_object(
        'id', id,
        'amount_cents', amount_cents,
        'status', status,
        'source', source,
        'receipt_url', receipt_url,
        'failure_reason', failure_reason,
        'created_at', created_at
      ) as payload
    from public.venue_withdrawals
    where venue_id = p_venue_id
    order by created_at desc
    limit 50
  ) item;

  return pg_catalog.jsonb_build_object(
    'enabled', true,
    'can_withdraw', v_role in ('owner', 'partner'),
    'role', v_role,
    'pending_cents', v_pending,
    'blocked_until', v_bank.withdrawals_blocked_until,
    'bank', case
      when v_bank.venue_id is null then null
      else pg_catalog.jsonb_build_object(
        'destination', v_bank.destination,
        'pix_key_type', v_bank.pix_key_type,
        'pix_key_masked', private.mask_tail(v_bank.pix_key),
        'bank_code', v_bank.bank_code,
        'agency', v_bank.agency,
        'account_masked', private.mask_tail(v_bank.account_number),
        'operation_type', v_bank.operation_type,
        'owner_name', v_bank.owner_name
      )
    end,
    'schedule', case
      when v_schedule.venue_id is null then pg_catalog.jsonb_build_object(
        'enabled', false,
        'frequency', 'daily',
        'weekday', null,
        'min_amount_cents', 0
      )
      else pg_catalog.jsonb_build_object(
        'enabled', v_schedule.enabled,
        'frequency', v_schedule.frequency,
        'weekday', v_schedule.weekday,
        'min_amount_cents', v_schedule.min_amount_cents
      )
    end,
    'withdrawals', v_rows
  );
end;
$$;

comment on function public.venue_payout_snapshot(uuid, uuid, boolean) is
  'Leitura do saque para a Edge Function. p_as_admin só é verdadeiro quando a função conferiu admin e aal2. Sem apiKey.';

revoke all on function public.venue_payout_snapshot(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.venue_payout_snapshot(uuid, uuid, boolean) to service_role;

create or replace function public.my_venue_payouts(p_venue_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.venue_payout_snapshot(
    p_venue_id,
    auth.uid(),
    private.is_admin_aal2()
  );
$$;

revoke all on function public.my_venue_payouts(uuid) from public, anon, service_role;
grant execute on function public.my_venue_payouts(uuid) to authenticated;

create or replace function private.assert_payout_house(p_venue_id uuid, p_actor uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_status text;
  v_wallet text;
begin
  perform private.venue_payouts_require();
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  select owner_id, status, asaas_wallet_id
    into v_owner, v_status, v_wallet
  from public.venues
  where id = p_venue_id;
  if v_owner is null or v_status is distinct from 'approved' or v_wallet is null then
    raise exception 'sem subconta' using errcode = '42501';
  end if;
  return v_owner;
end;
$$;

revoke all on function private.assert_payout_house(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.save_venue_bank_account(
  p_venue_id uuid,
  p_actor uuid,
  p_destination text,
  p_pix_key text,
  p_pix_key_type text,
  p_bank_code text,
  p_agency text,
  p_account_number text,
  p_account_digit text,
  p_owner_name text,
  p_owner_document text,
  p_operation_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_doc text;
  v_old public.venue_bank_accounts%rowtype;
  v_key text;
  v_key_type text;
  v_bank text;
  v_agency text;
  v_account text;
  v_digit text;
  v_name text;
  v_operation text;
  v_document text;
  v_changed boolean;
  v_blocked timestamptz;
  v_notice uuid;
begin
  v_owner := private.assert_payout_house(p_venue_id, p_actor);
  select private.only_digits(document_number)
    into v_doc
  from public.venues
  where id = p_venue_id;
  v_document := private.only_digits(p_owner_document);
  v_name := pg_catalog.btrim(coalesce(p_owner_name, ''));
  if v_document is distinct from v_doc or char_length(v_document) not in (11, 14) then
    raise exception 'titularidade' using errcode = '42501';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'valor' using errcode = '22023';
  end if;

  if p_destination = 'pix' then
    v_operation := 'PIX';
    v_key_type := pg_catalog.upper(pg_catalog.btrim(coalesce(p_pix_key_type, '')));
    if v_key_type in ('CPF', 'CNPJ') then
      v_key := private.only_digits(p_pix_key);
      if v_key is distinct from v_doc then
        raise exception 'titularidade' using errcode = '42501';
      end if;
    elsif v_key_type = 'EMAIL' then
      v_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_pix_key, '')));
      if v_key !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
        raise exception 'valor' using errcode = '22023';
      end if;
    elsif v_key_type = 'PHONE' then
      v_key := private.only_digits(p_pix_key);
      if v_key !~ '^[0-9]{10,13}$' then
        raise exception 'valor' using errcode = '22023';
      end if;
    elsif v_key_type = 'EVP' then
      v_key := pg_catalog.lower(pg_catalog.btrim(coalesce(p_pix_key, '')));
      if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        raise exception 'valor' using errcode = '22023';
      end if;
    else
      raise exception 'valor' using errcode = '22023';
    end if;
    v_bank := null;
    v_agency := null;
    v_account := null;
    v_digit := null;
  elsif p_destination = 'bank' then
    v_operation := case when p_operation_type = 'TED' then 'TED' else 'PIX' end;
    v_bank := private.only_digits(p_bank_code);
    v_agency := private.only_digits(p_agency);
    v_account := private.only_digits(p_account_number);
    v_digit := private.only_digits(p_account_digit);
    if v_bank !~ '^[0-9]{3}$'
      or v_agency !~ '^[0-9]{1,6}$'
      or v_account !~ '^[0-9]{1,16}$'
      or v_digit !~ '^[0-9]{1,2}$'
    then
      raise exception 'valor' using errcode = '22023';
    end if;
    v_key := null;
    v_key_type := null;
  else
    raise exception 'valor' using errcode = '22023';
  end if;

  select * into v_old
  from public.venue_bank_accounts
  where venue_id = p_venue_id
  for update;

  v_changed := v_old.venue_id is null
    or v_old.destination is distinct from p_destination
    or v_old.pix_key is distinct from v_key
    or v_old.pix_key_type is distinct from v_key_type
    or v_old.bank_code is distinct from v_bank
    or v_old.agency is distinct from v_agency
    or v_old.account_number is distinct from v_account
    or v_old.account_digit is distinct from v_digit
    or v_old.operation_type is distinct from v_operation
    or v_old.owner_document is distinct from v_document
    or v_old.owner_name is distinct from v_name;

  if v_changed then
    v_blocked := pg_catalog.now() + interval '24 hours';
  else
    v_blocked := v_old.withdrawals_blocked_until;
  end if;

  insert into public.venue_bank_accounts (
    venue_id, destination, pix_key, pix_key_type, bank_code, agency,
    account_number, account_digit, owner_name, owner_document, operation_type,
    withdrawals_blocked_until, updated_at, updated_by
  ) values (
    p_venue_id, p_destination, v_key, v_key_type, v_bank, v_agency,
    v_account, v_digit, v_name, v_document, v_operation,
    v_blocked, pg_catalog.now(), p_actor
  )
  on conflict (venue_id) do update set
    destination = excluded.destination,
    pix_key = excluded.pix_key,
    pix_key_type = excluded.pix_key_type,
    bank_code = excluded.bank_code,
    agency = excluded.agency,
    account_number = excluded.account_number,
    account_digit = excluded.account_digit,
    owner_name = excluded.owner_name,
    owner_document = excluded.owner_document,
    operation_type = excluded.operation_type,
    withdrawals_blocked_until = excluded.withdrawals_blocked_until,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  insert into public.venue_payout_audit (
    venue_id, actor_id, action, summary
  ) values (
    p_venue_id,
    p_actor,
    'save_bank_account',
    case when p_destination = 'pix' then 'destino pix' else 'destino banco' end
  );

  if not v_changed then
    return null;
  end if;

  insert into public.venue_payout_notices (venue_id, owner_id, kind, body)
  values (
    p_venue_id,
    v_owner,
    'bank_changed',
    'A conta de saque da casa foi alterada. Novos saques ficam bloqueados por 24 horas.'
  )
  returning id into v_notice;
  return v_notice;
end;
$$;

revoke all on function public.save_venue_bank_account(
  uuid, uuid, text, text, text, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.save_venue_bank_account(
  uuid, uuid, text, text, text, text, text, text, text, text, text, text
) to service_role;

create or replace function public.save_venue_payout_schedule(
  p_venue_id uuid,
  p_actor uuid,
  p_enabled boolean,
  p_frequency text,
  p_weekday integer,
  p_min_amount_cents integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_frequency text := pg_catalog.btrim(coalesce(p_frequency, ''));
  v_weekday smallint;
begin
  perform private.assert_payout_house(p_venue_id, p_actor);
  if p_min_amount_cents is null or p_min_amount_cents < 0 then
    raise exception 'valor' using errcode = '22023';
  end if;
  if v_frequency = 'daily' then
    v_weekday := null;
  elsif v_frequency = 'weekly' then
    if p_weekday is null or p_weekday < 0 or p_weekday > 6 then
      raise exception 'valor' using errcode = '22023';
    end if;
    v_weekday := p_weekday::smallint;
  else
    raise exception 'valor' using errcode = '22023';
  end if;

  insert into public.venue_payout_schedules (
    venue_id, enabled, frequency, weekday, min_amount_cents, updated_at, updated_by
  ) values (
    p_venue_id,
    coalesce(p_enabled, false),
    v_frequency,
    v_weekday,
    p_min_amount_cents,
    pg_catalog.now(),
    p_actor
  )
  on conflict (venue_id) do update set
    enabled = excluded.enabled,
    frequency = excluded.frequency,
    weekday = excluded.weekday,
    min_amount_cents = excluded.min_amount_cents,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  insert into public.venue_payout_audit (venue_id, actor_id, action, summary)
  values (
    p_venue_id,
    p_actor,
    'save_payout_schedule',
    case
      when coalesce(p_enabled, false) then 'agenda ligada'
      else 'agenda desligada'
    end
  );
end;
$$;

revoke all on function public.save_venue_payout_schedule(uuid, uuid, boolean, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.save_venue_payout_schedule(uuid, uuid, boolean, text, integer, integer)
  to service_role;

create or replace function public.claim_venue_withdrawal(
  p_venue_id uuid,
  p_actor uuid,
  p_source text,
  p_period_key text,
  p_amount_cents integer,
  p_available_cents integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_id uuid;
  v_existing uuid;
  v_existing_amount integer;
  v_period text;
  v_pending integer;
  v_blocked timestamptz;
  v_min integer;
  v_schedule_on boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_venue_id::text, 0)
  );

  if p_source = 'automatic' then
    perform private.venue_payouts_require();
    select owner_id into v_owner
    from public.venues
    where id = p_venue_id
      and status = 'approved'
      and asaas_wallet_id is not null;
    if v_owner is null then
      raise exception 'sem subconta' using errcode = '42501';
    end if;
  else
    if p_source is distinct from 'manual' then
      raise exception 'valor' using errcode = '22023';
    end if;
    v_owner := private.assert_payout_house(p_venue_id, p_actor);
  end if;

  if p_amount_cents is null or p_amount_cents <= 0
    or p_available_cents is null or p_available_cents < 0
  then
    raise exception 'valor' using errcode = '22023';
  end if;

  select withdrawals_blocked_until
    into v_blocked
  from public.venue_bank_accounts
  where venue_id = p_venue_id
  for update;
  if not found then
    raise exception 'sem conta' using errcode = '42501';
  end if;
  if v_blocked is not null and v_blocked > pg_catalog.now() then
    raise exception 'bloqueado' using errcode = '42501';
  end if;

  select coalesce(pg_catalog.sum(amount_cents), 0)::integer
    into v_pending
  from public.venue_withdrawals
  where venue_id = p_venue_id
    and status = 'pending';

  if p_source = 'automatic' then
    select enabled, min_amount_cents
      into v_schedule_on, v_min
    from public.venue_payout_schedules
    where venue_id = p_venue_id;
    if v_schedule_on is not true then
      raise exception 'agenda' using errcode = '22023';
    end if;
    if p_amount_cents < coalesce(v_min, 0) then
      raise exception 'minimo' using errcode = '22023';
    end if;
    v_period := pg_catalog.btrim(coalesce(p_period_key, ''));
    if v_period !~ '^auto:[0-9]{4}-[0-9W-]{2,12}$' then
      raise exception 'valor' using errcode = '22023';
    end if;
    select id, amount_cents
      into v_existing, v_existing_amount
    from public.venue_withdrawals
    where venue_id = p_venue_id
      and period_key = v_period
    for update;
    if v_existing is not null then
      return pg_catalog.jsonb_build_object(
        'id', v_existing,
        'amount_cents', v_existing_amount,
        'fresh', false
      );
    end if;
  else
    v_id := pg_catalog.gen_random_uuid();
    v_period := 'manual:' || v_id::text;
  end if;

  if p_amount_cents + v_pending > p_available_cents then
    raise exception 'saldo' using errcode = '22023';
  end if;

  if p_source = 'manual' then
    insert into public.venue_withdrawals (
      id, venue_id, amount_cents, status, source, period_key,
      external_reference, requested_by
    ) values (
      v_id, p_venue_id, p_amount_cents, 'pending', 'manual', v_period,
      v_id::text, p_actor
    );
    insert into public.venue_payout_audit (
      venue_id, actor_id, action, withdrawal_id, summary
    ) values (
      p_venue_id, p_actor, 'request_withdrawal', v_id, 'saque manual'
    );
    return pg_catalog.jsonb_build_object(
      'id', v_id,
      'amount_cents', p_amount_cents,
      'fresh', true
    );
  end if;

  v_id := pg_catalog.gen_random_uuid();
  begin
    insert into public.venue_withdrawals (
      id, venue_id, amount_cents, status, source, period_key,
      external_reference, requested_by
    ) values (
      v_id, p_venue_id, p_amount_cents, 'pending', 'automatic', v_period,
      v_id::text, null
    );
    insert into public.venue_payout_audit (
      venue_id, actor_id, action, withdrawal_id, summary
    ) values (
      p_venue_id, null, 'automatic_withdrawal', v_id, 'saque automatico'
    );
    return pg_catalog.jsonb_build_object(
      'id', v_id,
      'amount_cents', p_amount_cents,
      'fresh', true
    );
  exception
    when unique_violation then
      select id, amount_cents
        into v_existing, v_existing_amount
      from public.venue_withdrawals
      where venue_id = p_venue_id
        and period_key = v_period;
      return pg_catalog.jsonb_build_object(
        'id', v_existing,
        'amount_cents', v_existing_amount,
        'fresh', false
      );
  end;
end;
$$;

revoke all on function public.claim_venue_withdrawal(uuid, uuid, text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.claim_venue_withdrawal(uuid, uuid, text, text, integer, integer)
  to service_role;

create or replace function public.begin_withdrawal_dispatch(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.venue_withdrawals%rowtype;
begin
  select * into v_row
  from public.venue_withdrawals
  where id = p_id
  for update;
  if not found then
    return false;
  end if;
  if v_row.asaas_transfer_id is not null then
    return false;
  end if;
  if v_row.status in ('done', 'cancelled') then
    return false;
  end if;
  if v_row.status = 'pending'
    and v_row.dispatch_started_at is not null
    and v_row.dispatch_started_at > pg_catalog.now() - interval '2 minutes'
  then
    return false;
  end if;
  update public.venue_withdrawals
  set dispatch_started_at = pg_catalog.now(),
      status = 'pending',
      updated_at = pg_catalog.now()
  where id = p_id;
  return true;
end;
$$;

revoke all on function public.begin_withdrawal_dispatch(uuid)
  from public, anon, authenticated;
grant execute on function public.begin_withdrawal_dispatch(uuid) to service_role;

create or replace function public.attach_venue_transfer(
  p_id uuid,
  p_transfer_id text,
  p_status text,
  p_receipt text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text := case p_status
    when 'done' then 'done'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'pending'
  end;
  v_receipt text;
begin
  if p_transfer_id is null or p_transfer_id !~ '^[A-Za-z0-9_-]{4,64}$' then
    raise exception 'valor' using errcode = '22023';
  end if;
  v_receipt := case
    when p_receipt is null or p_receipt = '' then null
    when p_receipt ~ '^https://' then pg_catalog.left(p_receipt, 400)
    else null
  end;
  update public.venue_withdrawals
  set asaas_transfer_id = p_transfer_id,
      status = v_status,
      receipt_url = coalesce(v_receipt, receipt_url),
      updated_at = pg_catalog.now()
  where id = p_id
    and (asaas_transfer_id is null or asaas_transfer_id = p_transfer_id);
end;
$$;

revoke all on function public.attach_venue_transfer(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.attach_venue_transfer(uuid, text, text, text) to service_role;

create or replace function public.fail_venue_withdrawal(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.venue_withdrawals
  set status = 'failed',
      failure_reason = pg_catalog.left(coalesce(p_reason, 'erro'), 80),
      dispatch_started_at = null,
      updated_at = pg_catalog.now()
  where id = p_id
    and asaas_transfer_id is null
    and status = 'pending';
end;
$$;

revoke all on function public.fail_venue_withdrawal(uuid, text)
  from public, anon, authenticated;
grant execute on function public.fail_venue_withdrawal(uuid, text) to service_role;

create or replace function public.apply_transfer_event(
  p_external_reference text,
  p_transfer_id text,
  p_status text,
  p_receipt text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.venue_withdrawals%rowtype;
  v_next text;
  v_receipt text;
  v_owner uuid;
  v_notice uuid;
  v_body text;
begin
  if p_status not in ('pending', 'done', 'failed', 'cancelled') then
    return pg_catalog.jsonb_build_object('changed', false);
  end if;

  select * into v_row
  from public.venue_withdrawals
  where (
      coalesce(p_external_reference, '') <> ''
      and external_reference = p_external_reference
    )
    or (
      coalesce(p_transfer_id, '') <> ''
      and asaas_transfer_id = p_transfer_id
    )
  order by created_at desc
  limit 1
  for update;

  if not found then
    return pg_catalog.jsonb_build_object('changed', false);
  end if;

  v_next := p_status;
  if v_row.status = 'done' or v_row.status = 'cancelled' then
    v_next := v_row.status;
  elsif v_row.status = 'failed' and p_status = 'pending' then
    v_next := 'failed';
  end if;

  v_receipt := case
    when p_receipt is null or p_receipt = '' then v_row.receipt_url
    when p_receipt ~ '^https://' then pg_catalog.left(p_receipt, 400)
    else v_row.receipt_url
  end;

  if v_next is not distinct from v_row.status
    and v_receipt is not distinct from v_row.receipt_url
    and (
      p_transfer_id is null
      or p_transfer_id = ''
      or p_transfer_id = v_row.asaas_transfer_id
    )
  then
    return pg_catalog.jsonb_build_object('changed', false);
  end if;

  update public.venue_withdrawals
  set status = v_next,
      receipt_url = v_receipt,
      failure_reason = case
        when v_next = 'failed' then pg_catalog.left(coalesce(p_reason, 'falhou'), 80)
        else failure_reason
      end,
      asaas_transfer_id = coalesce(asaas_transfer_id, nullif(p_transfer_id, '')),
      updated_at = pg_catalog.now()
  where id = v_row.id;

  if v_next in ('done', 'failed') and v_next is distinct from v_row.status then
    select owner_id into v_owner
    from public.venues
    where id = v_row.venue_id;
    v_body := case v_next
      when 'done' then 'O saque da casa foi concluído. O comprovante fica no histórico do Parceiro.'
      else 'O saque da casa não foi concluído. O valor continua na subconta.'
    end;
    insert into public.venue_payout_notices (venue_id, owner_id, kind, body)
    values (
      v_row.venue_id,
      v_owner,
      case when v_next = 'done' then 'withdrawal_done' else 'withdrawal_failed' end,
      v_body
    )
    returning id into v_notice;
  end if;

  return pg_catalog.jsonb_build_object(
    'changed', true,
    'status', v_next,
    'venue_id', v_row.venue_id,
    'owner_id', v_owner,
    'amount_cents', v_row.amount_cents,
    'notice_id', v_notice
  );
end;
$$;

revoke all on function public.apply_transfer_event(text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.apply_transfer_event(text, text, text, text, text)
  to service_role;

create or replace function public.list_due_venue_payouts()
returns table (
  venue_id uuid,
  period_key text,
  min_amount_cents integer,
  pending_cents integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.venue_id,
    public.venue_payout_period_key(s.frequency, pg_catalog.now()),
    s.min_amount_cents,
    coalesce((
      select pg_catalog.sum(w.amount_cents)::integer
      from public.venue_withdrawals w
      where w.venue_id = s.venue_id
        and w.status = 'pending'
    ), 0)
  from public.venue_payout_schedules s
  join public.venues v on v.id = s.venue_id
  join public.venue_bank_accounts b on b.venue_id = s.venue_id
  where public.venue_payouts_enabled()
    and s.enabled
    and v.status = 'approved'
    and v.asaas_wallet_id is not null
    and (b.withdrawals_blocked_until is null or b.withdrawals_blocked_until <= pg_catalog.now())
    and (
      s.frequency = 'daily'
      or (
        s.frequency = 'weekly'
        and s.weekday = private.sao_paulo_weekday(pg_catalog.now())
      )
    );
$$;

comment on function public.list_due_venue_payouts() is
  'Casas com saque automático devido hoje. Não inclui a Reserva de pontos.';

revoke all on function public.list_due_venue_payouts()
  from public, anon, authenticated;
grant execute on function public.list_due_venue_payouts() to service_role;

create or replace function public.venue_payout_wallet(p_venue_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select asaas_wallet_id
  from public.venues
  where id = p_venue_id
    and status = 'approved';
$$;

revoke all on function public.venue_payout_wallet(uuid)
  from public, anon, authenticated;
grant execute on function public.venue_payout_wallet(uuid) to service_role;

create or replace function public.venue_bank_for_transfer(p_venue_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'destination', destination,
    'pix_key', pix_key,
    'pix_key_type', pix_key_type,
    'bank_code', bank_code,
    'agency', agency,
    'account_number', account_number,
    'account_digit', account_digit,
    'owner_name', owner_name,
    'owner_document', owner_document,
    'operation_type', operation_type
  )
  from public.venue_bank_accounts
  where venue_id = p_venue_id;
$$;

comment on function public.venue_bank_for_transfer(uuid) is
  'Destino completo só para a Edge Function montar a transferência. O app recebe a versão mascarada.';

revoke all on function public.venue_bank_for_transfer(uuid)
  from public, anon, authenticated;
grant execute on function public.venue_bank_for_transfer(uuid) to service_role;

create or replace function public.payout_notice(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'id', id,
    'venue_id', venue_id,
    'owner_id', owner_id,
    'kind', kind,
    'body', body,
    'sent_at', sent_at
  )
  from public.venue_payout_notices
  where id = p_id;
$$;

revoke all on function public.payout_notice(uuid) from public, anon, authenticated;
grant execute on function public.payout_notice(uuid) to service_role;

create or replace function public.unsent_payout_notices()
returns table (id uuid, venue_id uuid, owner_id uuid, kind text, body text)
language sql
stable
security definer
set search_path = ''
as $$
  select id, venue_id, owner_id, kind, body
  from public.venue_payout_notices
  where sent_at is null
  order by created_at
  limit 50;
$$;

revoke all on function public.unsent_payout_notices()
  from public, anon, authenticated;
grant execute on function public.unsent_payout_notices() to service_role;

create or replace function public.mark_payout_notice_sent(p_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.venue_payout_notices
  set sent_at = pg_catalog.now()
  where id = p_id
    and sent_at is null;
$$;

revoke all on function public.mark_payout_notice_sent(uuid)
  from public, anon, authenticated;
grant execute on function public.mark_payout_notice_sent(uuid) to service_role;

create or replace function public.admin_list_venue_withdrawals()
returns table (
  id uuid,
  venue_id uuid,
  venue_name text,
  amount_cents integer,
  status text,
  source text,
  receipt_url text,
  failure_reason text,
  requested_by uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return query
  select
    w.id,
    w.venue_id,
    v.name,
    w.amount_cents,
    w.status,
    w.source,
    w.receipt_url,
    w.failure_reason,
    w.requested_by,
    w.created_at
  from public.venue_withdrawals w
  join public.venues v on v.id = w.venue_id
  order by w.created_at desc
  limit 200;
end;
$$;

revoke all on function public.admin_list_venue_withdrawals()
  from public, anon, service_role;
grant execute on function public.admin_list_venue_withdrawals() to authenticated;

create or replace function public.admin_set_venue_payouts_enabled(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_before boolean;
begin
  v_actor := private.admin_require();
  select enabled into v_before
  from public.venue_payouts_settings
  where id = 1
  for update;
  update public.venue_payouts_settings
  set enabled = coalesce(p_enabled, false),
      updated_at = pg_catalog.now(),
      updated_by = v_actor
  where id = 1;
  perform private.admin_audit(
    v_actor,
    'set_venue_payouts_enabled',
    'venue_payouts_settings',
    '1',
    pg_catalog.jsonb_build_object('enabled', v_before),
    pg_catalog.jsonb_build_object('enabled', coalesce(p_enabled, false))
  );
  return coalesce(p_enabled, false);
end;
$$;

revoke all on function public.admin_set_venue_payouts_enabled(boolean)
  from public, anon, service_role;
grant execute on function public.admin_set_venue_payouts_enabled(boolean) to authenticated;

grant select on table public.venue_bank_accounts to authenticated;
grant select on table public.venue_payout_schedules to authenticated;
grant select on table public.venue_withdrawals to authenticated;
grant select on table public.venue_payout_audit to authenticated;
grant select on table public.venue_payout_notices to authenticated;
grant select on table public.venue_payouts_settings to authenticated;

create policy venue_payouts_settings_select
  on public.venue_payouts_settings
  for select to authenticated
  using (true);

create policy venue_bank_accounts_select
  on public.venue_bank_accounts
  for select to authenticated
  using (
    private.is_admin_aal2()
    or private.venue_treasurer(venue_id, (select auth.uid()))
  );

create policy venue_payout_schedules_select
  on public.venue_payout_schedules
  for select to authenticated
  using (
    private.is_admin_aal2()
    or private.venue_treasurer(venue_id, (select auth.uid()))
  );

create policy venue_withdrawals_select
  on public.venue_withdrawals
  for select to authenticated
  using (
    private.is_admin_aal2()
    or private.venue_treasurer(venue_id, (select auth.uid()))
  );

create policy venue_payout_audit_select
  on public.venue_payout_audit
  for select to authenticated
  using (
    private.is_admin_aal2()
    or private.venue_treasurer(venue_id, (select auth.uid()))
  );

create policy venue_payout_notices_select
  on public.venue_payout_notices
  for select to authenticated
  using (
    private.is_admin_aal2()
    or exists (
      select 1
      from public.venues
      where id = venue_id
        and owner_id = (select auth.uid())
    )
  );

-- Agenda o saque automático uma vez por dia, 11:20 UTC (08:20 em São Paulo).
-- Sem pg_cron e pg_net, a migração não agenda e não falha.
-- No projeto, crie no vault, fora do git:
--   venue_withdrawals_url = https://<ref>.supabase.co/functions/v1/schedule-venue-withdrawals
--   venue_withdrawals_secret = o mesmo valor da env VENUE_WITHDRAWALS_SECRET
-- O cron manda o segredo em x-venue-withdrawals-secret. Não usa service_role.

do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net')
  then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    execute $fn$
      create or replace function private.invoke_venue_withdrawals()
      returns void
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_url text;
        v_secret text;
      begin
        select btrim(s.decrypted_secret) into v_url
        from vault.decrypted_secrets s
        where s.name = 'venue_withdrawals_url'
        limit 1;
        select btrim(s.decrypted_secret) into v_secret
        from vault.decrypted_secrets s
        where s.name = 'venue_withdrawals_secret'
        limit 1;
        if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
          return;
        end if;
        perform net.http_post(
          url := v_url,
          body := '{}'::jsonb,
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-venue-withdrawals-secret', v_secret
          ),
          timeout_milliseconds := 90000
        );
      end;
      $body$;
    $fn$;
    revoke all on function private.invoke_venue_withdrawals()
      from public, anon, authenticated, service_role;
    if exists (
      select 1 from cron.job where jobname = 'venue-withdrawals'
    ) then
      perform cron.unschedule('venue-withdrawals');
    end if;
    perform cron.schedule(
      'venue-withdrawals',
      '20 11 * * *',
      'select private.invoke_venue_withdrawals()'
    );
  else
    raise notice 'pg_cron ou pg_net ausente; venue-withdrawals não foi agendado';
  end if;
end
$cron$;
