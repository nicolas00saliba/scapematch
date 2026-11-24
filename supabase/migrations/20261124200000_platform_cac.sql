-- CAC da plataforma. O split FIXED só reparte o que o cliente pagou.
-- Quando desconto, pontos e indicações passam da comissão, a casa continua
-- com o valor cheio e a diferença sai da conta PagBank da EscapeMatch,
-- depois da custódia, por transferência P2P. A flag de execução fica
-- desligada: esta migration não liga nada em produção.
-- O complemento deixa de ser crédito em free_slot_topups, para a casa
-- não receber duas vezes.

create table public.platform_cac_transfers (
  id uuid primary key default gen_random_uuid(),
  payment_charge_id uuid not null unique
    references public.payment_charges (id) on delete cascade,
  venue_id uuid not null references public.venues (id),
  amount_cents integer not null check (amount_cents >= 0),
  assumed_cents integer not null check (assumed_cents >= amount_cents),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'failed')),
  provider_ref text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at timestamptz not null default pg_catalog.now(),
  paid_at timestamptz,
  failed_at timestamptz
);

create index platform_cac_transfers_open_idx
  on public.platform_cac_transfers (created_at)
  where status in ('pending', 'failed');

alter table public.platform_cac_transfers enable row level security;

revoke all on table public.platform_cac_transfers
  from public, anon, authenticated;
grant select, update on table public.platform_cac_transfers to service_role;

comment on table public.platform_cac_transfers is
  'Prejuízo consciente da EscapeMatch por reserva. amount_cents é o que a transferência P2P manda para a casa. assumed_cents é o CAC do período, incluindo indicação que não vira dinheiro.';

create or replace function private.book_platform_cac(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_commission integer;
  v_referral integer;
  v_covered integer;
  v_assumed integer;
  v_amount integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;

  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_commission := private.reward_cents(v_gross, v_charge.commission_bps);

  select coalesce(sum(s.amount_cents), 0) into v_referral
  from (
    select e.amount_cents
    from public.scape_point_entries e
    where e.source_charge_id = p_charge_id
      and e.kind = 'accrual'
      and e.program in ('c2c', 'c2b')
    union all
    select r.amount_cents
    from public.venue_referral_entries r
    where r.source_charge_id = p_charge_id
      and r.kind = 'accrual'
      and r.program in ('b2c', 'b2b')
  ) s;

  select coalesce(sum(t.amount_cents), 0) into v_covered
  from public.free_slot_topups t
  where t.payment_charge_id = p_charge_id
    and t.redemption_id is not null
    and t.voided_at is null;

  v_amount := greatest(
    coalesce(v_charge.free_slot_topup_cents, 0) - v_covered,
    0
  );
  v_assumed := greatest(
    coalesce(v_charge.first_booking_discount_cents, 0)
      + coalesce(v_charge.subsidy_cents, 0)
      + v_referral
      - v_commission,
    0
  );
  v_assumed := greatest(v_assumed, v_amount);
  if v_assumed <= 0 then
    return;
  end if;

  insert into public.platform_cac_transfers (
    payment_charge_id, venue_id, amount_cents, assumed_cents, status, paid_at
  ) values (
    v_charge.id,
    v_charge.venue_id,
    v_amount,
    v_assumed,
    case when v_amount = 0 then 'paid' else 'pending' end,
    case when v_amount = 0 then pg_catalog.now() else null end
  )
  on conflict (payment_charge_id) do nothing;
end;
$$;

create or replace function private.void_platform_cac(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.platform_cac_transfers
  set last_error = case
        when status = 'paid' and amount_cents > 0 then 'estorno_apos_pagamento'
        else 'estorno'
      end,
      status = case
        when status = 'paid' and amount_cents > 0 then 'paid'
        else 'failed'
      end,
      attempts = case
        when status = 'paid' and amount_cents > 0 then attempts
        else 8
      end,
      failed_at = case
        when status = 'paid' and amount_cents > 0 then failed_at
        else coalesce(failed_at, pg_catalog.now())
      end
  where payment_charge_id = p_charge_id
    and coalesce(last_error, '') not in ('estorno', 'estorno_apos_pagamento');
end;
$$;

-- O crédito futuro na casa saiu. O complemento agora é a transferência.
create or replace function private.realize_discount_topup(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  return;
end;
$$;

revoke all on function private.book_platform_cac(uuid)
  from public, anon, authenticated;
revoke all on function private.void_platform_cac(uuid)
  from public, anon, authenticated;
revoke all on function private.realize_discount_topup(uuid)
  from public, anon, authenticated;

create or replace function private.apply_payment_transition(
  p_charge_id uuid,
  p_next_status text,
  p_credit boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_previous text;
  v_applied boolean := false;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    raise exception 'charge_not_found' using errcode = 'P0002';
  end if;

  v_previous := v_charge.status;

  if v_previous = 'refunded' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
    perform private.void_charge_free_slot_topups(v_charge.id);
    perform private.void_platform_cac(v_charge.id);
    perform private.sync_charge_member(v_charge);
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'status', v_charge.status,
      'paid_at', v_charge.paid_at,
      'refunded_at', v_charge.refunded_at
    );
  end if;

  if not private.payment_status_allowed(v_previous, p_next_status) then
    perform private.sync_charge_member(v_charge);
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'status', v_charge.status,
      'paid_at', v_charge.paid_at,
      'refunded_at', v_charge.refunded_at
    );
  end if;

  if v_previous is distinct from p_next_status
    or (p_next_status = 'paid' and v_charge.paid_at is null)
    or (p_next_status = 'refunded' and v_charge.refunded_at is null)
  then
    update public.payment_charges
    set
      status = p_next_status,
      paid_at = case
        when p_next_status = 'paid' then coalesce(paid_at, pg_catalog.now())
        else paid_at
      end,
      refunded_at = case
        when p_next_status = 'refunded'
          then coalesce(refunded_at, pg_catalog.now())
        else refunded_at
      end
    where id = v_charge.id
    returning * into v_charge;
    v_applied := v_previous is distinct from v_charge.status;
  end if;

  if v_charge.status = 'paid' and p_credit then
    perform private.ledger_credit_charge(v_charge.id);
    perform private.post_referral_rewards(v_charge.id);
  end if;
  if v_charge.status = 'paid' then
    perform private.book_platform_cac(v_charge.id);
  end if;
  if v_charge.status = 'refunded' then
    perform private.ledger_reverse_charge(v_charge.id);
    perform private.reverse_referral_rewards(v_charge.id);
    perform private.void_charge_free_slot_topups(v_charge.id);
    perform private.void_platform_cac(v_charge.id);
  end if;
  if v_charge.status in ('cancelled', 'failed') then
    perform private.release_unpaid_components(v_charge.id);
    perform private.void_platform_cac(v_charge.id);
  end if;

  perform private.sync_charge_member(v_charge);
  return pg_catalog.jsonb_build_object(
    'applied', v_applied,
    'status', v_charge.status,
    'paid_at', v_charge.paid_at,
    'refunded_at', v_charge.refunded_at
  );
end;
$$;

create or replace function public.claim_platform_cac(p_limit integer)
returns table (
  id uuid,
  payment_charge_id uuid,
  venue_id uuid,
  amount_cents integer,
  attempts integer,
  account_id text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'limite' using errcode = '22023';
  end if;

  return query
  with picked as (
    select t.id
    from public.platform_cac_transfers t
    join public.payment_charges c on c.id = t.payment_charge_id
    where t.status in ('pending', 'failed')
      and t.attempts < 8
      and t.amount_cents > 0
      and coalesce(t.last_error, '') <> 'estorno'
      and c.status = 'paid'
      and c.custody_released_at is not null
      and c.refund_requested_at is null
    order by t.created_at
    limit p_limit
    for update of t skip locked
  )
  update public.platform_cac_transfers t
  set attempts = t.attempts + 1,
      status = 'pending',
      last_error = null
  from picked
  where t.id = picked.id
  returning
    t.id,
    t.payment_charge_id,
    t.venue_id,
    t.amount_cents,
    t.attempts,
    (
      select v.pagbank_account_id
      from public.venues v
      where v.id = t.venue_id
    );
end;
$$;

create or replace function public.complete_platform_cac(
  p_id uuid,
  p_status text,
  p_provider_ref text,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_status not in ('paid', 'failed') then
    raise exception 'status' using errcode = '22023';
  end if;
  update public.platform_cac_transfers
  set status = p_status,
      provider_ref = coalesce(nullif(p_provider_ref, ''), provider_ref),
      last_error = nullif(left(coalesce(p_error, ''), 80), ''),
      paid_at = case
        when p_status = 'paid' then coalesce(paid_at, pg_catalog.now())
        else paid_at
      end,
      failed_at = case
        when p_status = 'failed' then coalesce(failed_at, pg_catalog.now())
        else null
      end
  where id = p_id
    and status in ('pending', 'failed');
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
begin
  perform private.admin_require();
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'periodo' using errcode = '22023';
  end if;
  v_start := p_from::timestamp at time zone 'America/Sao_Paulo';
  v_end := (p_to + 1)::timestamp at time zone 'America/Sao_Paulo';

  select
    coalesce(sum(assumed_cents), 0),
    coalesce(sum(amount_cents) filter (where status = 'paid'), 0),
    coalesce(sum(amount_cents) filter (where status = 'pending'), 0),
    coalesce(sum(amount_cents) filter (where status = 'failed'), 0)
  into v_assumed, v_paid, v_pending, v_failed
  from public.platform_cac_transfers
  where created_at >= v_start
    and created_at < v_end;

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
      and (
        t.status = 'failed'
        or coalesce(t.last_error, '') <> ''
      )
    order by t.created_at desc
    limit 50
  ) s;

  return pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'assumed_cents', v_assumed,
    'paid_cents', v_paid,
    'pending_cents', v_pending,
    'failed_cents', v_failed,
    'alerts', v_alerts
  );
end;
$$;

revoke all on function public.claim_platform_cac(integer)
  from public, anon, authenticated;
revoke all on function public.complete_platform_cac(uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.admin_platform_cac_report(date, date)
  from public, anon;

grant execute on function public.claim_platform_cac(integer) to service_role;
grant execute on function public.complete_platform_cac(uuid, text, text, text)
  to service_role;
grant execute on function public.admin_platform_cac_report(date, date)
  to authenticated;
