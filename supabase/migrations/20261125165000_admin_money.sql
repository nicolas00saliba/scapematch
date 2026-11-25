-- Admin: cobranças, fila de estorno, custódia e CAC.
-- Não cria integração. Liberar e reprocessar só zeram a tentativa;
-- quem fala com a PagBank continua sendo settle-charges.
-- Reembolso parcial não existe na fila (sem coluna de valor).
-- Reembolso do Admin só é recusado a menos de 2h do início.
-- Custódia só reabre depois que o horário da sessão passou.

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
      coalesce(w.pagbank_transfer_id, w.asaas_transfer_id, '') as pagbank_transfer_id,
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

create or replace function public.admin_platform_cac_report(
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_assumed integer;
  v_paid integer;
  v_pending integer;
  v_failed integer;
  v_alerts jsonb;
  v_entries jsonb;
begin
  perform private.admin_require();
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'periodo' using errcode = '22023';
  end if;
  v_start := p_from::timestamp at time zone 'America/Sao_Paulo';
  v_end := (p_to + 1)::timestamp at time zone 'America/Sao_Paulo';

  select
    coalesce(sum(t.assumed_cents), 0),
    coalesce(sum(t.amount_cents) filter (where t.status = 'paid'), 0),
    coalesce(sum(t.amount_cents) filter (where t.status = 'pending'), 0),
    coalesce(sum(t.amount_cents) filter (where t.status = 'failed'), 0)
  into v_assumed, v_paid, v_pending, v_failed
  from public.platform_cac_transfers t
  join public.venues v on v.id = t.venue_id
  where t.created_at >= v_start
    and t.created_at < v_end
    and v.is_test = false;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
  into v_alerts
  from (
    select
      t.id,
      t.payment_charge_id,
      t.venue_id,
      v.name as venue_name,
      t.amount_cents,
      t.assumed_cents,
      t.status,
      coalesce(t.last_error, '') as last_error,
      t.attempts,
      t.created_at
    from public.platform_cac_transfers t
    join public.venues v on v.id = t.venue_id
    where t.created_at >= v_start
      and t.created_at < v_end
      and v.is_test = false
      and (
        t.status = 'failed'
        or coalesce(t.last_error, '') <> ''
      )
    order by t.created_at desc
    limit 50
  ) s;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
  into v_entries
  from (
    select
      t.id,
      t.payment_charge_id,
      v.name as venue_name,
      t.amount_cents,
      t.assumed_cents,
      t.status,
      t.attempts,
      coalesce(t.last_error, '') as last_error,
      t.created_at
    from public.platform_cac_transfers t
    join public.venues v on v.id = t.venue_id
    where t.created_at >= v_start
      and t.created_at < v_end
      and v.is_test = false
    order by t.created_at desc
    limit 80
  ) s;

  return pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'assumed_cents', v_assumed,
    'paid_cents', v_paid,
    'pending_cents', v_pending,
    'failed_cents', v_failed,
    'alerts', v_alerts,
    'entries', v_entries,
    'transfers_flag', pg_catalog.jsonb_build_object(
      'name', 'PAGBANK_CAC_TRANSFERS',
      'readable', false,
      'enabled', null
    )
  );
end;
$$;

create or replace function public.admin_cac_transfers_flag()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return pg_catalog.jsonb_build_object(
    'name', 'PAGBANK_CAC_TRANSFERS',
    'readable', false,
    'enabled', null
  );
end;
$$;

create or replace function public.admin_search_charges(
  p_query text default null,
  p_venue_id uuid default null,
  p_status text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  if p_status is not null and p_status not in (
    'pending', 'authorized', 'paid', 'refunded', 'cancelled', 'failed'
  ) then
    raise exception 'status' using errcode = '22023';
  end if;

  select count(*)::integer into v_total
  from public.payment_charges c
  join public.venues v on v.id = c.venue_id
  join public.profiles pr on pr.id = c.user_id
  where (p_venue_id is null or c.venue_id = p_venue_id)
    and (p_status is null or c.status = p_status)
    and (
      p_include_test
      or (v.is_test = false and pr.is_test = false)
    )
    and (
      p_query is null
      or btrim(p_query) = ''
      or v.name ilike v_like
      or pr.display_name ilike v_like
      or coalesce(c.provider_ref, '') ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      c.id,
      c.group_id,
      c.status,
      c.billing_type,
      c.amount_cents,
      c.charged_amount_cents,
      c.buyer_interest_cents,
      c.first_booking_discount_cents,
      c.subsidy_cents,
      c.points_redeemed,
      c.house_fixed_cents,
      c.split_divergence_at,
      coalesce(c.split_divergence_event, '') as split_divergence_event,
      c.custody_release_attempts,
      c.created_at,
      v.name as venue_name,
      pr.display_name as player_name,
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
    join public.profiles pr on pr.id = c.user_id
    where (p_venue_id is null or c.venue_id = p_venue_id)
      and (p_status is null or c.status = p_status)
      and (
        p_include_test
        or (v.is_test = false and pr.is_test = false)
      )
      and (
        p_query is null
        or btrim(p_query) = ''
        or v.name ilike v_like
        or pr.display_name ilike v_like
        or coalesce(c.provider_ref, '') ilike v_like
      )
    order by c.created_at desc
    limit v_limit offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_search_refund_queue(
  p_query text default null,
  p_status text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  if p_status is not null and p_status not in ('queued', 'processing', 'done') then
    raise exception 'status' using errcode = '22023';
  end if;

  select count(*)::integer into v_total
  from public.member_refund_queue q
  join public.payment_charges c on c.id = q.charge_id
  join public.venues v on v.id = c.venue_id
  join public.profiles pr on pr.id = q.user_id
  where (p_status is null or q.status = p_status)
    and (
      p_include_test
      or (v.is_test = false and pr.is_test = false)
    )
    and (
      p_query is null
      or btrim(p_query) = ''
      or v.name ilike v_like
      or pr.display_name ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      q.id,
      q.charge_id,
      q.group_id,
      q.action,
      q.status,
      q.attempts,
      q.created_at,
      q.done_at,
      c.amount_cents,
      c.charged_amount_cents,
      v.name as venue_name,
      pr.display_name as player_name
    from public.member_refund_queue q
    join public.payment_charges c on c.id = q.charge_id
    join public.venues v on v.id = c.venue_id
    join public.profiles pr on pr.id = q.user_id
    where (p_status is null or q.status = p_status)
      and (
        p_include_test
        or (v.is_test = false and pr.is_test = false)
      )
      and (
        p_query is null
        or btrim(p_query) = ''
        or v.name ilike v_like
        or pr.display_name ilike v_like
      )
    order by q.created_at desc
    limit v_limit offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_search_withdrawals(
  p_query text default null,
  p_status text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();

  select count(*)::integer into v_total
  from public.venue_withdrawals w
  join public.venues v on v.id = w.venue_id
  where (p_status is null or w.status = p_status)
    and (p_include_test or v.is_test = false)
    and (
      p_query is null
      or btrim(p_query) = ''
      or v.name ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      w.id,
      w.status,
      w.source,
      w.amount_cents,
      w.created_at,
      v.name as venue_name
    from public.venue_withdrawals w
    join public.venues v on v.id = w.venue_id
    where (p_status is null or w.status = p_status)
      and (p_include_test or v.is_test = false)
      and (
        p_query is null
        or btrim(p_query) = ''
        or v.name ilike v_like
      )
    order by w.created_at desc
    limit v_limit offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object(
    'total', v_total,
    'limit', v_limit,
    'offset', v_offset,
    'rows', v_rows
  );
end;
$$;

create or replace function public.admin_charge(p_charge_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  perform private.admin_require();
  select pg_catalog.jsonb_build_object(
    'id', c.id,
    'group_id', c.group_id,
    'status', c.status,
    'billing_type', c.billing_type,
    'amount_cents', c.amount_cents,
    'charged_amount_cents', c.charged_amount_cents,
    'buyer_interest_cents', c.buyer_interest_cents,
    'first_booking_discount_cents', c.first_booking_discount_cents,
    'subsidy_cents', c.subsidy_cents,
    'points_redeemed', c.points_redeemed,
    'house_fixed_cents', c.house_fixed_cents,
    'split_divergence_at', c.split_divergence_at,
    'split_divergence_event', coalesce(c.split_divergence_event, ''),
    'custody_release_attempts', c.custody_release_attempts,
    'custody_released_at', c.custody_released_at,
    'custody_release_failed_at', c.custody_release_failed_at,
    'refund_requested_at', c.refund_requested_at,
    'venue_name', v.name,
    'player_name', pr.display_name,
    'room_name', r.name,
    'starts_at', g.starts_at,
    'group_closed', g.closed_at is not null or g.confirmed_at is not null,
    'custody', case
      when c.custody_released_at is not null then 'liberada'
      when c.custody_release_failed_at is not null then 'falha'
      when c.status = 'paid'
        and c.provider_split_id is not null
        and c.refund_requested_at is null
        then 'HELD'
      else 'sem_custodia'
    end,
    'refund_queue_status', q.status,
    'refund_queue_action', q.action,
    'full_refund_cents', case
      when c.charged_amount_cents > 0 then c.charged_amount_cents
      else c.amount_cents
    end
  ) into v_row
  from public.payment_charges c
  join public.venues v on v.id = c.venue_id
  join public.profiles pr on pr.id = c.user_id
  join public.groups g on g.id = c.group_id
  join public.rooms r on r.id = g.room_id
  left join public.member_refund_queue q on q.charge_id = c.id
  where c.id = p_charge_id;
  if v_row is null then
    raise exception 'cobranca nao encontrada' using errcode = 'P0002';
  end if;
  return v_row;
end;
$$;

create or replace function public.admin_refund_charge(
  p_charge_id uuid,
  p_confirm text,
  p_amount_cents integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_charge public.payment_charges%rowtype;
  v_member_id uuid;
  v_starts timestamptz;
  v_full integer;
  v_queued boolean;
begin
  if p_confirm is distinct from 'REEMBOLSAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if not found then
    raise exception 'cobranca nao encontrada' using errcode = 'P0002';
  end if;
  v_full := case
    when v_charge.charged_amount_cents > 0 then v_charge.charged_amount_cents
    else v_charge.amount_cents
  end;
  if p_amount_cents is not null and p_amount_cents is distinct from v_full then
    raise exception 'reembolso parcial sem fila' using errcode = '22023';
  end if;
  -- Segundo clique: a fila já existe. Não grava outra auditoria.
  if exists (
    select 1
    from public.member_refund_queue
    where charge_id = p_charge_id
  ) then
    return pg_catalog.jsonb_build_object(
      'charge_id', p_charge_id,
      'group_id', v_charge.group_id,
      'queued', true,
      'amount_cents', v_full
    );
  end if;
  select starts_at into v_starts
  from public.groups
  where id = v_charge.group_id;
  if v_starts is null then
    raise exception 'grupo nao encontrado' using errcode = 'P0002';
  end if;
  if v_starts - pg_catalog.now() < interval '2 hours' then
    raise exception 'reembolso a menos de 2h do inicio' using errcode = 'P0001';
  end if;
  select id into v_member_id
  from public.group_members
  where group_id = v_charge.group_id
    and user_id = v_charge.user_id
  order by case when attendance = 'joined' then 0 else 1 end
  limit 1;
  if v_member_id is null then
    raise exception 'membro nao encontrado' using errcode = 'P0002';
  end if;
  v_queued := private.enqueue_member_refund(
    v_charge.group_id, v_charge.user_id, v_member_id
  );
  if not v_queued then
    raise exception 'cobranca sem estorno' using errcode = 'P0001';
  end if;
  perform private.admin_audit(
    v_actor,
    'refund_charge',
    'payment_charges',
    p_charge_id::text,
    '{}'::jsonb,
    pg_catalog.jsonb_build_object('amount_cents', v_full, 'queued', true)
  );
  return pg_catalog.jsonb_build_object(
    'charge_id', p_charge_id,
    'group_id', v_charge.group_id,
    'queued', true,
    'amount_cents', v_full
  );
end;
$$;

create or replace function public.admin_reopen_custody(
  p_charge_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_charge public.payment_charges%rowtype;
  v_starts timestamptz;
  v_ready boolean;
begin
  if p_confirm is distinct from 'LIBERAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if not found then
    raise exception 'cobranca nao encontrada' using errcode = 'P0002';
  end if;
  if v_charge.custody_released_at is not null then
    raise exception 'custodia ja liberada' using errcode = 'P0001';
  end if;
  if v_charge.refund_requested_at is not null then
    raise exception 'estorno pedido' using errcode = 'P0001';
  end if;
  if v_charge.status is distinct from 'paid'
    or v_charge.provider_split_id is null
  then
    raise exception 'sem custodia' using errcode = 'P0001';
  end if;
  select starts_at into v_starts
  from public.groups
  where id = v_charge.group_id;
  if v_starts is null or v_starts > pg_catalog.now() then
    raise exception 'custodia antes do horario da sessao' using errcode = 'P0001';
  end if;
  update public.payment_charges
  set custody_release_attempts = 0,
      custody_release_failed_at = null
  where id = p_charge_id;
  select g.closed_at is not null or g.confirmed_at is not null
    into v_ready
  from public.groups g
  where g.id = v_charge.group_id;
  perform private.admin_audit(
    v_actor,
    'reopen_custody',
    'payment_charges',
    p_charge_id::text,
    pg_catalog.jsonb_build_object('attempts', v_charge.custody_release_attempts),
    pg_catalog.jsonb_build_object(
      'attempts', 0,
      'group_ready', coalesce(v_ready, false)
    )
  );
  return pg_catalog.jsonb_build_object(
    'charge_id', p_charge_id,
    'group_id', v_charge.group_id,
    'attempts', 0,
    'group_ready', coalesce(v_ready, false)
  );
end;
$$;

create or replace function public.admin_reopen_cac(
  p_charge_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_id uuid;
  v_group uuid;
begin
  if p_confirm is distinct from 'REPROCESSAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  select t.id, c.group_id into v_id, v_group
  from public.platform_cac_transfers t
  join public.payment_charges c on c.id = t.payment_charge_id
  where t.payment_charge_id = p_charge_id
    and t.status = 'failed'
  for update of t;
  if v_id is null then
    raise exception 'cac sem falha' using errcode = 'P0002';
  end if;
  update public.platform_cac_transfers
  set attempts = 0,
      status = 'pending',
      last_error = null,
      failed_at = null
  where id = v_id;
  perform private.admin_audit(
    v_actor,
    'reopen_cac',
    'platform_cac_transfers',
    v_id::text,
    pg_catalog.jsonb_build_object('status', 'failed'),
    pg_catalog.jsonb_build_object(
      'status', 'pending',
      'charge_id', p_charge_id,
      'attempts', 0
    )
  );
  return pg_catalog.jsonb_build_object(
    'id', v_id,
    'charge_id', p_charge_id,
    'group_id', v_group,
    'status', 'pending',
    'attempts', 0
  );
end;
$$;

do $$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public.admin_cac_transfers_flag()',
    'public.admin_search_charges(text, uuid, text, boolean, integer, integer)',
    'public.admin_search_refund_queue(text, text, boolean, integer, integer)',
    'public.admin_search_withdrawals(text, text, boolean, integer, integer)',
    'public.admin_charge(uuid)',
    'public.admin_refund_charge(uuid, text, integer)',
    'public.admin_reopen_custody(uuid, text)',
    'public.admin_reopen_cac(uuid, text)'
  ]
  loop
    execute format(
      'revoke all on function %s from public, anon, service_role',
      v_sig
    );
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;
