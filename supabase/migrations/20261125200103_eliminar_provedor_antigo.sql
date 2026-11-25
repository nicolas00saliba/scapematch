-- Elimina o provedor antigo. O pagamento fica só na PagBank.
-- Cobranças já gravadas com provider antigo continuam válidas:
-- não há check que liste o provedor, e o default novo não reescreve linha antiga.
-- O segredo novo copia o valor que já cifra os tokens. Não recifra.
-- Não imprime o segredo.
-- Redefine admin_payments_board e admin_merge_venues da pilha de admin
-- para não lerem a coluna nem as tabelas removidas.
-- Cartão salvo ativo com customer que não é o da PagBank, ou sem token
-- PagBank, recebe deactivated_at. A linha fica.

do $$
declare
  v_secret text;
begin
  if exists (
    select 1 from vault.secrets where name = 'pagbank_token_key'
  ) then
    null;
  else
    select s.decrypted_secret
      into v_secret
    from vault.decrypted_secrets s
    where s.name = 'asaas_subaccount_key'
    limit 1;
    if v_secret is null or char_length(btrim(v_secret)) < 32 then
      raise exception 'chave dos tokens ausente' using errcode = 'P0001';
    end if;
    perform vault.create_secret(
      v_secret,
      'pagbank_token_key',
      'chave dos tokens PagBank Connect'
    );
  end if;
end $$;

create or replace function private.pagbank_token_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  select btrim(s.decrypted_secret)
    into v_key
  from vault.decrypted_secrets s
  where s.name = 'pagbank_token_key'
  limit 1;
  if v_key is null or char_length(v_key) < 32 then
    raise exception 'chave dos tokens ausente';
  end if;
  return v_key;
end;
$$;

revoke all on function private.pagbank_token_key()
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.reserve_with_subsidy(p_group_id uuid, p_user_id uuid, p_venue_id uuid, p_amount_cents integer, p_idempotency_key text, p_wallet_id text, p_commission_bps integer, p_billing_type text, p_gross_amount_cents integer DEFAULT NULL::integer, p_subsidy_cents integer DEFAULT 0, p_points_redeemed integer DEFAULT 0, p_split_percent numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
  v_inserted boolean := false;
  v_charge public.payment_charges%rowtype;
  v_fixed integer;
begin
  if p_subsidy_cents > 0 and not exists (
    select 1
    from public.scape_point_entries e
    where e.client_key = p_idempotency_key
      and e.user_id = p_user_id
      and e.kind = 'redemption'
      and e.points = p_points_redeemed
      and e.amount_cents = p_subsidy_cents
      and not exists (
        select 1 from public.scape_point_entries r
        where r.relates_to = e.id and r.kind = 'redemption_reversal'
      )
  ) then
    raise exception 'hold ausente' using errcode = '42501';
  end if;

  insert into public.payment_charges (
    group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, provider_ref, idempotency_key, wallet_id, commission_bps,
    reserved_at, attempt_id, gross_amount_cents, subsidy_cents,
    points_redeemed, split_percent
  ) values (
    p_group_id, p_user_id, p_venue_id, p_amount_cents, p_billing_type, 'creating',
    'pagbank', null, p_idempotency_key, p_wallet_id, p_commission_bps,
    pg_catalog.now(), gen_random_uuid(),
    case when p_subsidy_cents > 0 then p_gross_amount_cents else null end,
    coalesce(p_subsidy_cents, 0),
    case when p_subsidy_cents > 0 then p_points_redeemed else 0 end,
    case when p_subsidy_cents > 0 then p_split_percent else null end
  )
  on conflict (group_id, user_id) do nothing
  returning id into v_id;
  v_inserted := v_id is not null;

  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;

  if v_inserted and v_charge.points_redeemed > 0 then
    perform private.attach_point_hold(p_idempotency_key, v_charge.id);
  elsif not v_inserted and v_charge.points_redeemed = 0 then
    perform private.release_point_hold(p_idempotency_key);
  elsif not v_inserted and v_charge.points_redeemed > 0 then
    perform private.attach_point_hold(p_idempotency_key, v_charge.id);
  end if;

  if v_inserted then
    perform private.apply_share_adjustments(v_charge.id);
    select * into v_charge
    from public.payment_charges
    where id = v_charge.id;
  end if;

  if v_charge.provider_ref is not null then
    v_fixed := v_charge.house_fixed_cents;
  else
    v_fixed := private.sync_house_fixed(v_charge.id);
    select * into v_charge
    from public.payment_charges
    where id = v_charge.id;
  end if;

  return pg_catalog.jsonb_build_object(
    'id', v_charge.id,
    'status', v_charge.status,
    'provider_ref', v_charge.provider_ref,
    'billing_type', v_charge.billing_type,
    'amount_cents', v_charge.amount_cents,
    'inserted', v_inserted,
    'reserved_at', v_charge.reserved_at,
    'attempt_id', v_charge.attempt_id,
    'idempotency_key', v_charge.idempotency_key,
    'gross_amount_cents', v_charge.gross_amount_cents,
    'subsidy_cents', v_charge.subsidy_cents,
    'points_redeemed', v_charge.points_redeemed,
    'split_percent', v_charge.split_percent,
    'house_fixed_cents', v_fixed,
    'lease_expired', (not v_inserted)
      and v_charge.provider_ref is null
      and v_charge.status = 'creating'
      and (
        v_charge.reserved_at is null
        or v_charge.reserved_at < pg_catalog.now() - interval '2 minutes'
      )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.venues_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and not private.is_admin_aal2() then
      new.owner_id := auth.uid();
      new.status := 'pending';
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.referred_by := null;
      new.pagbank_account_id := null;
      new.suspended_at := null;
      new.featured_rank := null;
      new.official_email := null;
      new.official_phone := null;
      new.claimed_at := pg_catalog.now();
      if new.invite_id is not null then
        select i.badge
          into new.badge
        from public.partner_invites i
        where i.id = new.invite_id
          and i.active;
        if not found then
          raise exception 'unknown invite' using errcode = 'P0002';
        end if;
      else
        new.badge := null;
      end if;
    end if;
    if new.latitude is null or new.longitude is null then
      select c.latitude, c.longitude
        into new.latitude, new.longitude
      from public.cities c
      where c.id = new.city_id;
    end if;
    return new;
  end if;

  if auth.uid() is null then
    return new;
  end if;

  if not private.is_admin_aal2() then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'not owner' using errcode = '42501';
    end if;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
    new.badge := old.badge;
    new.invite_id := old.invite_id;
    new.pagbank_account_id := old.pagbank_account_id;
    new.suspended_at := old.suspended_at;
    new.featured_rank := old.featured_rank;
    new.official_email := old.official_email;
    new.official_phone := old.official_phone;
    new.claimed_at := old.claimed_at;
    if old.status is distinct from 'pending'
      or old.pagbank_account_id is not null
    then
      new.company_type := old.company_type;
    end if;
    if current_setting('scapematch.referral_link', true) is distinct from 'on'
      or old.referred_by is not null
    then
      new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.profiles_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null then
    new.pagbank_customer_id := old.pagbank_customer_id;
    if not (
      exists (
        select 1
        from public.admins admin_row
        where admin_row.user_id = auth.uid()
      )
      and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
    ) then
      new.suspended_at := old.suspended_at;
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.assert_payout_house(p_venue_id uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_owner uuid;
  v_status text;
  v_wallet text;
begin
  perform private.venue_payouts_require();
  if not private.venue_treasurer(p_venue_id, p_actor) then
    raise exception 'not owner' using errcode = '42501';
  end if;
  select owner_id, status, pagbank_account_id
    into v_owner, v_status, v_wallet
  from public.venues
  where id = p_venue_id;
  if v_owner is null or v_status is distinct from 'approved' or v_wallet is null then
    raise exception 'sem subconta' using errcode = '42501';
  end if;
  return v_owner;
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_venue_withdrawal(p_venue_id uuid, p_actor uuid, p_source text, p_period_key text, p_amount_cents integer, p_available_cents integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_owner uuid;
  v_id uuid;
  v_existing uuid;
  v_existing_amount integer;
  v_period text;
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
      and pagbank_account_id is not null;
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
    if v_period !~ '^auto:[0-9]{4}-W[0-9]{2}(-r[12])?$' then
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

  -- p_available_cents é o saldo disponível informado. Ele já não inclui
  -- transferência pendente: o cancelamento devolve o valor ao saldo.
  if p_amount_cents > p_available_cents then
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
$function$;

CREATE OR REPLACE FUNCTION public.begin_withdrawal_dispatch(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v_row.status in ('done', 'cancelled') then
    return false;
  end if;
  if v_row.status = 'failed' then
    if v_row.source is distinct from 'automatic'
      or v_row.pagbank_transfer_id is not null
      or v_row.retry_count >= 2
      or v_row.period_key !~ '^auto:[0-9]{4}-W[0-9]{2}(-r[12])?$'
    then
      return false;
    end if;
    update public.venue_withdrawals
    set status = 'pending',
        retry_count = retry_count + 1,
        failure_reason = null,
        dispatch_started_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
    where id = p_id;
    return true;
  end if;
  if v_row.pagbank_transfer_id is not null then
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
$function$;

CREATE OR REPLACE FUNCTION public.attach_venue_transfer(p_id uuid, p_transfer_id text, p_status text, p_receipt text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  set pagbank_transfer_id = p_transfer_id,
      status = v_status,
      receipt_url = coalesce(v_receipt, receipt_url),
      updated_at = pg_catalog.now()
  where id = p_id
    and (pagbank_transfer_id is null or pagbank_transfer_id = p_transfer_id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.fail_venue_withdrawal(p_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.venue_withdrawals
  set status = 'failed',
      failure_reason = pg_catalog.left(coalesce(p_reason, 'erro'), 80),
      dispatch_started_at = null,
      updated_at = pg_catalog.now()
  where id = p_id
    and pagbank_transfer_id is null
    and status = 'pending';
end;
$function$;

CREATE OR REPLACE FUNCTION public.apply_transfer_event(p_external_reference text, p_transfer_id text, p_status text, p_receipt text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      and pagbank_transfer_id = p_transfer_id
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
      or p_transfer_id = v_row.pagbank_transfer_id
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
      pagbank_transfer_id = coalesce(pagbank_transfer_id, nullif(p_transfer_id, '')),
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
$function$;

CREATE OR REPLACE FUNCTION public.venue_weekly_attempt_key(p_venue_id uuid, p_at timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_weekday integer;
  v_base text;
  v_today date;
  v_latest_status text;
  v_latest_day date;
  v_latest_key text;
  v_latest_transfer text;
  v_retries integer;
begin
  if p_at is null then
    return null;
  end if;
  select s.weekday into v_weekday
  from public.venue_payout_schedules s
  where s.venue_id = p_venue_id
    and s.enabled
    and s.frequency = 'weekly';
  if v_weekday is null then
    return null;
  end if;

  v_base := public.venue_payout_period_key('weekly', p_at);
  if v_base is null then
    return null;
  end if;
  v_today := (p_at at time zone 'America/Sao_Paulo')::date;

  if v_weekday = private.sao_paulo_weekday(p_at)
    and not exists (
      select 1
      from public.venue_withdrawals w
      where w.venue_id = p_venue_id
        and w.period_key = v_base
    )
  then
    return v_base;
  end if;

  select w.status,
         (w.updated_at at time zone 'America/Sao_Paulo')::date,
         w.period_key,
         w.pagbank_transfer_id
    into v_latest_status, v_latest_day, v_latest_key, v_latest_transfer
  from public.venue_withdrawals w
  where w.venue_id = p_venue_id
    and w.source = 'automatic'
    and w.period_key in (v_base, v_base || '-r1', v_base || '-r2')
  order by w.created_at desc
  limit 1;

  if v_latest_status is distinct from 'failed' then
    return null;
  end if;
  if v_latest_day is null or v_today <= v_latest_day then
    return null;
  end if;
  if exists (
    select 1
    from public.venue_withdrawals w
    where w.venue_id = p_venue_id
      and w.source = 'automatic'
      and w.status = 'pending'
      and w.period_key in (v_base, v_base || '-r1', v_base || '-r2')
  ) then
    return null;
  end if;

  select coalesce(pg_catalog.sum(
    case
      when w.period_key = v_base then w.retry_count
      else 1 + w.retry_count
    end
  ), 0)::integer
    into v_retries
  from public.venue_withdrawals w
  where w.venue_id = p_venue_id
    and w.source = 'automatic'
    and w.period_key in (v_base, v_base || '-r1', v_base || '-r2');

  if v_retries >= 2 then
    return null;
  end if;

  if v_latest_transfer is null then
    return v_latest_key;
  end if;

  if v_latest_key = v_base and not exists (
    select 1
    from public.venue_withdrawals w
    where w.venue_id = p_venue_id
      and w.period_key = v_base || '-r1'
  ) then
    return v_base || '-r1';
  end if;
  if v_latest_key = v_base || '-r1' and not exists (
    select 1
    from public.venue_withdrawals w
    where w.venue_id = p_venue_id
      and w.period_key = v_base || '-r2'
  ) then
    return v_base || '-r2';
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.ledger_reconcile_snapshot(p_since timestamp with time zone, p_until timestamp with time zone, p_payment_ids text[], p_transfer_ids text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_charges jsonb;
  v_withdrawals jsonb;
  v_charge_count integer;
  v_withdrawal_count integer;
begin
  select count(*) into v_charge_count
  from public.payment_charges c
  where c.provider = 'pagbank'
    and (
      (c.created_at >= p_since and c.created_at < p_until)
      or (c.paid_at >= p_since and c.paid_at < p_until)
      or (c.refunded_at >= p_since and c.refunded_at < p_until)
      or c.provider_ref = any (coalesce(p_payment_ids, array[]::text[]))
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into v_charges
  from (
    select
      c.id,
      coalesce(c.provider_ref, '') as provider_ref,
      c.status,
      c.amount_cents,
      coalesce((
        select pg_catalog.jsonb_agg(distinct e.kind)
        from public.ledger_entries e
        where e.payment_charge_id = c.id
      ), '[]'::jsonb) as ledger_kinds
    from public.payment_charges c
    where c.provider = 'pagbank'
      and (
        (c.created_at >= p_since and c.created_at < p_until)
        or (c.paid_at >= p_since and c.paid_at < p_until)
        or (c.refunded_at >= p_since and c.refunded_at < p_until)
        or c.provider_ref = any (coalesce(p_payment_ids, array[]::text[]))
      )
    order by c.created_at desc
    limit 500
  ) s;

  select count(*) into v_withdrawal_count
  from public.venue_withdrawals w
  where (w.created_at >= p_since and w.created_at < p_until)
    or (w.updated_at >= p_since and w.updated_at < p_until)
    or w.pagbank_transfer_id = any (coalesce(p_transfer_ids, array[]::text[]))
    or w.external_reference = any (coalesce(p_transfer_ids, array[]::text[]));

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into v_withdrawals
  from (
    select
      w.id,
      w.venue_id,
      w.external_reference,
      coalesce(w.pagbank_transfer_id, '') as pagbank_transfer_id,
      w.status,
      w.amount_cents
    from public.venue_withdrawals w
    where (w.created_at >= p_since and w.created_at < p_until)
      or (w.updated_at >= p_since and w.updated_at < p_until)
      or w.pagbank_transfer_id = any (coalesce(p_transfer_ids, array[]::text[]))
      or w.external_reference = any (coalesce(p_transfer_ids, array[]::text[]))
    order by w.created_at desc
    limit 500
  ) s;

  return pg_catalog.jsonb_build_object(
    'charges', v_charges,
    'withdrawals', v_withdrawals,
    'capped', v_charge_count > 500 or v_withdrawal_count > 500
  );
end;
$function$;

create or replace function public.admin_payments_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ready jsonb;
  v_charges jsonb;
  v_refunds jsonb;
  v_withdrawals jsonb;
  v_errors jsonb;
begin
  perform private.admin_require();
  v_ready := public.admin_payments_readiness();

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_charges
  from (
    select
      c.id,
      c.status,
      c.billing_type,
      c.amount_cents,
      c.charged_amount_cents,
      c.buyer_interest_cents,
      c.first_booking_discount_cents,
      c.subsidy_cents,
      c.points_redeemed,
      c.house_fixed_cents,
      c.custody_release_attempts,
      coalesce(c.provider_ref, '') as provider_ref,
      c.created_at,
      v.name as venue_name,
      case
        when c.custody_released_at is not null then 'liberada'
        when c.custody_release_failed_at is not null then 'falha'
        when c.status = 'paid'
          and c.provider_split_id is not null
          and c.refund_requested_at is null
          then 'HELD'
        else 'sem_custodia'
      end as custody
    from public.payment_charges c
    join public.venues v on v.id = c.venue_id
    where v.is_test = false
    order by c.created_at desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_refunds
  from (
    select
      c.id,
      c.status,
      c.billing_type,
      c.amount_cents,
      coalesce(c.provider_ref, '') as provider_ref,
      coalesce(c.refunded_at, c.created_at) as created_at,
      v.name as venue_name
    from public.payment_charges c
    join public.venues v on v.id = c.venue_id
    where c.status = 'refunded'
      and v.is_test = false
    order by coalesce(c.refunded_at, c.created_at) desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_withdrawals
  from (
    select
      w.id,
      w.status,
      w.source,
      w.amount_cents,
      coalesce(w.pagbank_transfer_id, '') as pagbank_transfer_id,
      w.created_at,
      v.name as venue_name
    from public.venue_withdrawals w
    join public.venues v on v.id = w.venue_id
    where v.is_test = false
    order by w.created_at desc
    limit 20
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_errors
  from (
    select e.id, e.source, e.code, e.provider_ref, e.created_at
    from public.payment_webhook_errors e
    order by e.created_at desc
    limit 20
  ) s;

  return pg_catalog.jsonb_build_object(
    'readiness', v_ready,
    'charges', v_charges,
    'refunds', v_refunds,
    'withdrawals', v_withdrawals,
    'webhook_errors', v_errors
  );
end;
$$;


CREATE OR REPLACE FUNCTION public.store_venue_pagbank_tokens(p_venue_id uuid, p_access_token text, p_refresh_token text, p_expires_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := private.pagbank_token_key();
  v_access bytea;
  v_refresh bytea;
begin
  if p_access_token is null or char_length(btrim(p_access_token)) = 0 then
    raise exception 'api_key ausente' using errcode = '22023';
  end if;
  v_access := extensions.pgp_sym_encrypt(btrim(p_access_token), v_key);
  if p_refresh_token is null or char_length(btrim(p_refresh_token)) = 0 then
    v_refresh := null;
  else
    v_refresh := extensions.pgp_sym_encrypt(btrim(p_refresh_token), v_key);
  end if;
  insert into public.venue_pagbank_tokens (
    venue_id, access_token, refresh_token, access_expires_at
  ) values (p_venue_id, v_access, v_refresh, p_expires_at)
  on conflict (venue_id) do update
  set access_token = excluded.access_token,
      refresh_token = coalesce(
        excluded.refresh_token,
        public.venue_pagbank_tokens.refresh_token
      ),
      access_expires_at = coalesce(
        excluded.access_expires_at,
        public.venue_pagbank_tokens.access_expires_at
      ),
      updated_at = pg_catalog.now();
end;
$function$;

CREATE OR REPLACE FUNCTION public.read_venue_pagbank_tokens(p_venue_id uuid)
 RETURNS TABLE(access_token text, refresh_token text, access_expires_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_key text := private.pagbank_token_key();
begin
  return query
  select
    extensions.pgp_sym_decrypt(k.access_token, v_key)::text,
    case
      when k.refresh_token is null then null
      else extensions.pgp_sym_decrypt(k.refresh_token, v_key)::text
    end,
    k.access_expires_at
  from public.venue_pagbank_tokens k
  where k.venue_id = p_venue_id;
end;
$function$;


delete from vault.secrets where name = 'asaas_subaccount_key';

drop function private.asaas_subaccount_key();

alter table public.saved_cards
  rename column asaas_customer_id to provider_customer_id;

alter table public.saved_cards
  rename constraint saved_cards_asaas_customer_id_check
  to saved_cards_provider_customer_id_check;

CREATE OR REPLACE FUNCTION private.insert_saved_card(p_user_id uuid, p_customer_id text, p_token text, p_last4 text, p_brand text, p_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if p_user_id is null
    or p_customer_id is null
    or char_length(p_customer_id) < 1
    or char_length(p_customer_id) > 80
    or p_token is null
    or char_length(p_token) < 8
    or char_length(p_token) > 200
    or p_token ~ '^[0-9]{13,19}$'
    or p_last4 is null
    or p_last4 !~ '^[0-9]{4}$'
    or p_brand is null
    or char_length(p_brand) < 1
    or char_length(p_brand) > 32
  then
    raise exception 'token inválido';
  end if;
  insert into public.saved_cards (
    id, user_id, provider_customer_id, credit_card_token, last4, brand
  )
  values (
    v_id,
    p_user_id,
    p_customer_id,
    extensions.pgp_sym_encrypt(p_token, private.card_token_key()),
    p_last4,
    p_brand
  );
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.load_owned_card(p_user_id uuid, p_customer_id text, p_card_id uuid)
 RETURNS TABLE(id uuid, token text, last4 text, brand text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  select
    c.id,
    extensions.pgp_sym_decrypt(c.credit_card_token, private.card_token_key()),
    c.last4,
    c.brand
  from public.saved_cards c
  where c.id = p_card_id
    and c.user_id = p_user_id
    and c.provider_customer_id = p_customer_id
    and c.deactivated_at is null;
end;
$function$;

CREATE OR REPLACE FUNCTION private.saved_cards_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE'
    and new.provider_customer_id is not distinct from old.provider_customer_id
  then
    return new;
  end if;
  if not exists (
    select 1
    from public.profiles p
    where p.id = new.user_id
      and p.pagbank_customer_id = new.provider_customer_id
  ) then
    raise exception 'customer do cartão não é o do jogador';
  end if;
  return new;
end;
$function$;

-- Mesmo caminho de deactivate_customer_saved_cards: só grava deactivated_at.
-- Token PagBank de cartão salvo começa com CARD_ ou tok_. O resto não cobra.
create or replace function private.deactivate_legacy_saved_cards()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_plain text;
  v_pagbank boolean;
  v_count integer := 0;
  v_updated integer;
begin
  for v_row in
    select
      c.id,
      c.provider_customer_id,
      c.credit_card_token,
      p.pagbank_customer_id
    from public.saved_cards c
    left join public.profiles p on p.id = c.user_id
    where c.deactivated_at is null
  loop
    v_plain := null;
    begin
      v_plain := extensions.pgp_sym_decrypt(
        v_row.credit_card_token,
        private.card_token_key()
      );
    exception
      when others then
        v_plain := null;
    end;
    v_pagbank := v_plain is not null
      and (
        pg_catalog.starts_with(v_plain, 'CARD_')
        or pg_catalog.starts_with(v_plain, 'tok_')
      );
    if v_row.provider_customer_id is distinct from v_row.pagbank_customer_id
      or not v_pagbank
    then
      update public.saved_cards
      set deactivated_at = pg_catalog.now()
      where id = v_row.id
        and deactivated_at is null;
      get diagnostics v_updated = row_count;
      v_count := v_count + v_updated;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke all on function private.deactivate_legacy_saved_cards()
  from public, anon, authenticated, service_role;

select private.deactivate_legacy_saved_cards();

CREATE OR REPLACE FUNCTION public.deactivate_customer_saved_cards(p_user_id uuid, p_customer_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
begin
  update public.saved_cards
  set deactivated_at = pg_catalog.now()
  where user_id = p_user_id
    and provider_customer_id = p_customer_id
    and deactivated_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.saved_card_needs_reregister(p_user_id uuid, p_card_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.saved_cards c
    join public.profiles p on p.id = c.user_id
    where c.id = p_card_id
      and c.user_id = p_user_id
      and c.deactivated_at is not null
      and c.provider_customer_id is distinct from p.pagbank_customer_id
  );
$function$;


drop trigger if exists sync_pagbank_venue on public.venues;
drop trigger if exists sync_pagbank_profile on public.profiles;
drop trigger if exists sync_pagbank_charge on public.payment_charges;
drop trigger if exists sync_pagbank_withdrawal on public.venue_withdrawals;

drop function private.sync_pagbank_venue();
drop function private.sync_pagbank_profile();
drop function private.sync_pagbank_charge();
drop function private.sync_pagbank_withdrawal();

update public.payment_charges
set provider_fee_cents = asaas_fee_cents
where provider_fee_cents is null
  and asaas_fee_cents is not null;

alter table public.payment_charges
  alter column provider set default 'pagbank';

drop index if exists public.venues_asaas_wallet_real_uidx;

alter table public.venues drop column asaas_wallet_id;
alter table public.profiles drop column asaas_customer_id;
alter table public.payment_charges drop column asaas_fee_cents;
alter table public.venue_withdrawals drop column asaas_transfer_id;

drop function public.store_venue_asaas_key(uuid, text);
drop function public.read_venue_asaas_key(uuid);
drop function private.store_venue_asaas_key(uuid, text);
drop function private.read_venue_asaas_key(uuid);

drop table public.asaas_customers;
drop table public.venue_asaas_keys;

-- admin_merge_venues foi criada enquanto asaas_customers e venue_asaas_keys existiam.
-- O corpo novo não consulta essas tabelas.
create or replace function public.admin_merge_venues(
  p_source_id uuid,
  p_target_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_source text;
  v_target text;
  v_table text;
  v_moved integer := 0;
begin
  if p_confirm is distinct from 'MESCLAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  if p_source_id is null or p_target_id is null or p_source_id = p_target_id then
    raise exception 'casas invalidas' using errcode = '22023';
  end if;
  select status into v_source from public.venues where id = p_source_id for update;
  if not found then
    raise exception 'casa de origem nao encontrada' using errcode = 'P0002';
  end if;
  select status into v_target from public.venues where id = p_target_id for update;
  if not found then
    raise exception 'casa de destino nao encontrada' using errcode = 'P0002';
  end if;
  if v_source = 'merged' or v_target in ('merged', 'rejected') then
    raise exception 'casa nao pode ser mesclada' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.venue_staff where venue_id = p_source_id
  ) then
    raise exception 'casa com equipe' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.venues
    where id = p_source_id
      and pagbank_account_id is not null
      and pg_catalog.btrim(pagbank_account_id) <> ''
  )
  or exists (select 1 from public.venue_pagbank_tokens where venue_id = p_source_id)
  or exists (select 1 from public.venue_pagbank_signups where venue_id = p_source_id)
  or exists (select 1 from public.pagbank_connect_states where venue_id = p_source_id)
  or exists (select 1 from public.pagbank_signup_events where venue_id = p_source_id)
  or exists (select 1 from public.venue_bank_accounts where venue_id = p_source_id)
  or exists (select 1 from public.venue_fiscal where venue_id = p_source_id)
  or exists (select 1 from public.venue_claims where venue_id = p_source_id)
  then
    raise exception 'casa com acesso' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.ledger_entries where venue_id = p_source_id)
  or exists (select 1 from public.venue_cashback_debits where venue_id = p_source_id)
  or exists (select 1 from public.venue_cashback_refunds where venue_id = p_source_id)
  or exists (select 1 from public.venue_credit_clawbacks where venue_id = p_source_id)
  or exists (select 1 from public.venue_referral_entries where venue_id = p_source_id)
  or exists (select 1 from public.free_slot_clawbacks where venue_id = p_source_id)
  or exists (select 1 from public.free_slot_topups where venue_id = p_source_id)
  or exists (select 1 from public.venue_empty_slots where venue_id = p_source_id)
  then
    raise exception 'casa com saldo' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.payment_charges where venue_id = p_source_id)
  or exists (select 1 from public.fiscal_invoices where venue_id = p_source_id)
  then
    raise exception 'casa com cobranca' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.venue_withdrawals where venue_id = p_source_id)
  or exists (select 1 from public.platform_cac_transfers where venue_id = p_source_id)
  or exists (select 1 from public.venue_payout_schedules where venue_id = p_source_id)
  or exists (select 1 from public.venue_payout_audit where venue_id = p_source_id)
  or exists (select 1 from public.venue_payout_notices where venue_id = p_source_id)
  then
    raise exception 'casa com repasse' using errcode = 'P0001';
  end if;
  foreach v_table in array array[
    'absences',
    'commission_changes',
    'groups',
    'news_items',
    'passport_gifts',
    'passport_plays',
    'passport_stamps',
    'promotions',
    'review_replies',
    'room_rating_rollups',
    'room_reviews',
    'room_time_audit',
    'room_time_entries',
    'rooms',
    'session_checkins',
    'terms_acceptances',
    'venue_commissions',
    'venue_time_ranking'
  ]
  loop
    begin
      execute format(
        'update public.%I set venue_id = $1 where venue_id = $2',
        v_table
      ) using p_target_id, p_source_id;
      get diagnostics v_moved = row_count;
    exception
      when unique_violation then
        raise exception 'mescla conflitante em %', v_table using errcode = 'P0001';
    end;
  end loop;
  update public.venues
  set status = 'merged',
      merged_into = p_target_id
  where id = p_source_id;
  perform private.admin_audit(
    v_actor, 'merge_venues', 'venues', p_source_id::text,
    pg_catalog.jsonb_build_object('status', v_source),
    pg_catalog.jsonb_build_object('status', 'merged', 'merged_into', p_target_id)
  );
  return pg_catalog.jsonb_build_object(
    'source_id', p_source_id,
    'target_id', p_target_id,
    'status', 'merged'
  );
end;
$$;


delete from public.payment_webhook_errors
where source in ('asaas-webhook', 'asaas-transfer-webhook');

alter table public.payment_webhook_errors
  drop constraint payment_webhook_errors_source_check;

alter table public.payment_webhook_errors
  add constraint payment_webhook_errors_source_check
  check (source in ('pagbank-webhook', 'pagbank-transfer-webhook'));

delete from public.payment_divergences
where kind in (
  'charge_missing_asaas',
  'transfer_missing_asaas',
  'asaas_truncated'
);

alter table public.payment_divergences
  drop constraint payment_divergences_kind_check;

alter table public.payment_divergences
  add constraint payment_divergences_kind_check
  check (kind in (
    'charge_missing_local',
    'charge_status',
    'charge_status_unknown',
    'charge_amount',
    'ledger_missing',
    'ledger_refund_missing',
    'transfer_missing_local',
    'transfer_status',
    'transfer_status_unknown',
    'transfer_amount'
  ));

CREATE OR REPLACE FUNCTION public.record_payment_divergences(p_payment_count integer, p_transfer_count integer, p_truncated boolean, p_rows jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_run uuid;
  v_count integer := 0;
  v_row jsonb;
  v_kind text;
  v_provider text;
  v_local text;
  v_expected text;
  v_actual text;
begin
  if p_payment_count < 0 or p_transfer_count < 0 then
    raise exception 'contagem' using errcode = '22023';
  end if;
  insert into public.payment_reconcile_runs (
    payment_count, transfer_count, truncated
  ) values (
    p_payment_count, p_transfer_count, coalesce(p_truncated, false)
  )
  returning id into v_run;

  if pg_catalog.jsonb_typeof(p_rows) = 'array' then
    for v_row in select value from pg_catalog.jsonb_array_elements(p_rows)
    loop
      v_kind := pg_catalog.btrim(coalesce(v_row ->> 'kind', ''));
      v_provider := pg_catalog.left(coalesce(v_row ->> 'providerRef', ''), 80);
      v_local := pg_catalog.left(coalesce(v_row ->> 'localId', ''), 80);
      v_expected := pg_catalog.left(coalesce(v_row ->> 'expected', ''), 40);
      v_actual := pg_catalog.left(coalesce(v_row ->> 'actual', ''), 40);
      if v_kind not in (
        'charge_missing_local', 'charge_status',
        'charge_status_unknown', 'charge_amount', 'ledger_missing',
        'ledger_refund_missing', 'transfer_missing_local',
        'transfer_status',
        'transfer_status_unknown', 'transfer_amount'
      ) then
        continue;
      end if;
      insert into public.payment_divergences (
        run_id, kind, provider_ref, local_id, expected, actual
      ) values (
        v_run, v_kind, v_provider, v_local, v_expected, v_actual
      );
      v_count := v_count + 1;
    end loop;
  end if;

  update public.payment_reconcile_runs
  set divergence_count = v_count
  where id = v_run;
  return v_run;
end;
$function$;


comment on table public.payment_divergences is
  'Diferença entre a PagBank e o livro. Sem nome, documento, QR ou chave.';

comment on column public.venues.company_type is
  'Tipo de empresa no cadastro da casa: MEI, LIMITED, INDIVIDUAL ou ASSOCIATION. CPF não envia o tipo. LIMITED é o padrão.';

comment on column public.venue_withdrawals.retry_count is
  'Reenvios da mesma linha, quando a transferência ainda não devolveu id. No máximo 2.';

comment on function public.list_stale_pending_withdrawals(integer) is
  'Saques ainda pendentes depois de X horas. A Edge Function consulta a transferência e não cria outra.';
