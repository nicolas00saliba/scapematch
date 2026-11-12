-- Correções do saque, sem aplicar no projeto remoto.
--
-- O saldo disponível do Asaas já desconta a transferência em andamento:
-- cancelar devolve o valor, e a transferência não pode passar desse saldo.
-- Somar o pendente local de novo recusaria um saque que ainda cabe.
--
-- venue_bank_accounts não tem select para anon, authenticated nem service_role.
-- O app lê my_venue_payouts, que mascara a chave. A chave inteira só sai
-- em venue_bank_for_transfer, para a Edge Function montar o Pix ou o TED.
--
-- Um automático semanal que falhou volta no dia seguinte, na mesma semana,
-- no máximo duas vezes. A linha do período continua única.

alter table public.venue_withdrawals
  add column retry_count integer not null default 0
  check (retry_count between 0 and 2);

comment on column public.venue_withdrawals.retry_count is
  'Reenvios da mesma linha, quando o Asaas ainda não devolveu id. No máximo 2.';

comment on table public.venue_bank_accounts is
  'Destino do saque. Sem select direto na API. O app recebe a máscara de my_venue_payouts.';

revoke all on table public.venue_bank_accounts from public, anon, authenticated, service_role;

drop policy if exists venue_bank_accounts_select on public.venue_bank_accounts;

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
    if v_period !~ '^auto:[0-9]{4}-([0-9]{2}-[0-9]{2}|W[0-9]{2}(-r[12])?)$' then
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

  -- p_available_cents é o saldo disponível do Asaas. Ele já não inclui
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
  if v_row.status in ('done', 'cancelled') then
    return false;
  end if;
  if v_row.status = 'failed' then
    if v_row.source is distinct from 'automatic'
      or v_row.asaas_transfer_id is not null
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
  if v_row.asaas_transfer_id is not null then
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

create or replace function public.venue_weekly_attempt_key(
  p_venue_id uuid,
  p_at timestamptz
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
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
         w.asaas_transfer_id
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
$$;

comment on function public.venue_weekly_attempt_key(uuid, timestamptz) is
  'Chave do automático semanal. No dia seguinte a uma falha, até duas vezes na mesma semana, sem segunda linha para o mesmo período.';

revoke all on function public.venue_weekly_attempt_key(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.venue_weekly_attempt_key(uuid, timestamptz)
  to service_role;

drop function public.list_due_venue_payouts();

create function public.list_due_venue_payouts()
returns table (
  venue_id uuid,
  period_key text,
  min_amount_cents integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.venue_id,
    case
      when s.frequency = 'weekly' then public.venue_weekly_attempt_key(
        s.venue_id, pg_catalog.now()
      )
      else public.venue_payout_period_key(s.frequency, pg_catalog.now())
    end,
    s.min_amount_cents
  from public.venue_payout_schedules s
  join public.venues v on v.id = s.venue_id
  join public.venue_bank_accounts b on b.venue_id = s.venue_id
  where public.venue_payouts_enabled()
    and s.enabled
    and v.status = 'approved'
    and v.asaas_wallet_id is not null
    and (
      b.withdrawals_blocked_until is null
      or b.withdrawals_blocked_until <= pg_catalog.now()
    )
    and (
      s.frequency = 'daily'
      or (
        s.frequency = 'weekly'
        and public.venue_weekly_attempt_key(s.venue_id, pg_catalog.now()) is not null
      )
    );
$$;

comment on function public.list_due_venue_payouts() is
  'Casas com saque automático devido. O semanal que falhou volta no dia seguinte, até duas vezes. Não inclui a Reserva de pontos.';

revoke all on function public.list_due_venue_payouts()
  from public, anon, authenticated;
grant execute on function public.list_due_venue_payouts() to service_role;

create or replace function public.list_venue_subaccounts()
returns table (venue_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select id
  from public.venues
  where status = 'approved'
    and asaas_wallet_id is not null;
$$;

comment on function public.list_venue_subaccounts() is
  'Casas com subconta, para cadastrar o webhook de transferência em cada uma. A Reserva de pontos não é casa.';

revoke all on function public.list_venue_subaccounts()
  from public, anon, authenticated;
grant execute on function public.list_venue_subaccounts() to service_role;

create or replace function public.list_stale_pending_withdrawals(p_hours integer)
returns table (
  id uuid,
  venue_id uuid,
  asaas_transfer_id text,
  external_reference text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_hours is null or p_hours < 1 or p_hours > 168 then
    raise exception 'valor' using errcode = '22023';
  end if;
  return query
  select w.id, w.venue_id, w.asaas_transfer_id, w.external_reference
  from public.venue_withdrawals w
  join public.venues v on v.id = w.venue_id
  where w.status = 'pending'
    and v.status = 'approved'
    and w.updated_at <= pg_catalog.now() - pg_catalog.make_interval(hours => p_hours);
end;
$$;

comment on function public.list_stale_pending_withdrawals(integer) is
  'Saques ainda pendentes depois de X horas. A Edge Function consulta a transferência no Asaas e não cria outra.';

revoke all on function public.list_stale_pending_withdrawals(integer)
  from public, anon, authenticated;
grant execute on function public.list_stale_pending_withdrawals(integer)
  to service_role;
