-- PagBank em produção. Colunas novas convivem com as antigas.
-- Um drop das colunas e da tabela de chaves fica para uma migração seguinte.
-- Esta migração ainda cita os nomes antigos porque o gatilho precisa copiar os dois lados
-- e as funções SQL históricas leem a coluna antiga.

alter table public.venues
  add column if not exists pagbank_account_id text unique;

alter table public.profiles
  add column if not exists pagbank_customer_id text unique;

alter table public.payment_charges
  add column if not exists provider_fee_cents integer,
  add column if not exists provider_split_id text;

alter table public.payment_charges
  drop constraint if exists payment_charges_provider_fee_nonnegative;
alter table public.payment_charges
  add constraint payment_charges_provider_fee_nonnegative
  check (provider_fee_cents is null or provider_fee_cents >= 0);

alter table public.venue_withdrawals
  add column if not exists pagbank_transfer_id text unique;

create or replace function private.sync_pagbank_venue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and not private.is_admin() then
    if tg_op = 'INSERT' then
      new.pagbank_account_id := null;
    else
      new.pagbank_account_id := old.pagbank_account_id;
    end if;
    return new;
  end if;
  -- Só a conta PagBank, gravada depois do Connect, segue para a coluna
  -- antiga. O id antigo não vira conta PagBank.
  if tg_op = 'INSERT' then
    if new.pagbank_account_id is not null then
      new.asaas_wallet_id := new.pagbank_account_id;
    end if;
    return new;
  end if;
  if new.pagbank_account_id is not null
    and new.pagbank_account_id is distinct from old.pagbank_account_id
  then
    new.asaas_wallet_id := new.pagbank_account_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_pagbank_venue on public.venues;
create trigger sync_pagbank_venue
  before insert or update on public.venues
  for each row execute function private.sync_pagbank_venue();

create or replace function private.sync_pagbank_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and not private.is_admin() then
    if tg_op = 'INSERT' then
      new.pagbank_customer_id := null;
    else
      new.pagbank_customer_id := old.pagbank_customer_id;
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.pagbank_customer_id is not null then
      new.asaas_customer_id := new.pagbank_customer_id;
    end if;
    return new;
  end if;
  if new.pagbank_customer_id is not null
    and new.pagbank_customer_id is distinct from old.pagbank_customer_id
  then
    new.asaas_customer_id := new.pagbank_customer_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_pagbank_profile on public.profiles;
create trigger sync_pagbank_profile
  before insert or update on public.profiles
  for each row execute function private.sync_pagbank_profile();

create or replace function private.sync_pagbank_charge()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.provider is null
      or lower(new.provider) in (
        'asaas', 'woovi', 'openpix', 'mercadopago', 'mercado_pago'
      )
    then
      new.provider := 'pagbank';
    end if;
  elsif new.provider is distinct from old.provider then
    if new.provider is null
      or lower(new.provider) in (
        'asaas', 'woovi', 'openpix', 'mercadopago', 'mercado_pago'
      )
    then
      new.provider := 'pagbank';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    if new.provider_fee_cents is distinct from old.provider_fee_cents then
      new.asaas_fee_cents := new.provider_fee_cents;
    elsif new.asaas_fee_cents is distinct from old.asaas_fee_cents then
      new.provider_fee_cents := new.asaas_fee_cents;
    end if;
  else
    if new.provider_fee_cents is not null then
      new.asaas_fee_cents := new.provider_fee_cents;
    else
      new.provider_fee_cents := new.asaas_fee_cents;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_pagbank_charge on public.payment_charges;
create trigger sync_pagbank_charge
  before insert or update on public.payment_charges
  for each row execute function private.sync_pagbank_charge();

create or replace function private.sync_pagbank_withdrawal()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.pagbank_transfer_id is not null then
      new.asaas_transfer_id := new.pagbank_transfer_id;
    end if;
    return new;
  end if;
  if new.pagbank_transfer_id is not null
    and new.pagbank_transfer_id is distinct from old.pagbank_transfer_id
  then
    new.asaas_transfer_id := new.pagbank_transfer_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_pagbank_withdrawal on public.venue_withdrawals;
create trigger sync_pagbank_withdrawal
  before insert or update on public.venue_withdrawals
  for each row execute function private.sync_pagbank_withdrawal();

-- Não copia wallet, cliente nem transferência antigos para as colunas
-- PagBank. Casa que já existia fica sem pagbank_account_id e precisa
-- passar pelo Connect. A chave antiga também não é lida como token.

update public.payment_charges
set provider_fee_cents = asaas_fee_cents
where provider_fee_cents is null and asaas_fee_cents is not null;

create or replace view public.venue_provider_keys as
select venue_id, api_key from public.venue_asaas_keys;
revoke all on table public.venue_provider_keys from public, anon, authenticated;

create or replace function public.read_venue_provider_key(p_venue_id uuid)
returns text
language sql
security definer
set search_path = ''
as $$
  select public.read_venue_asaas_key(p_venue_id);
$$;

create or replace function public.store_venue_provider_key(
  p_venue_id uuid,
  p_api_key text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select public.store_venue_asaas_key(p_venue_id, p_api_key);
$$;

revoke all on function public.read_venue_provider_key(uuid) from public, anon, authenticated;
revoke all on function public.store_venue_provider_key(uuid, text) from public, anon, authenticated;
grant execute on function public.read_venue_provider_key(uuid) to service_role;
grant execute on function public.store_venue_provider_key(uuid, text) to service_role;


create or replace function private.sync_house_fixed(p_charge_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fixed integer;
  v_net integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return 0;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_fixed := v_gross
    - private.reward_cents(v_gross, v_charge.commission_bps)
    + v_charge.venue_credit_applied_cents
    + v_charge.free_slot_applied_cents
    - v_charge.empty_slot_offset_cents
    - v_charge.venue_credit_clawback_cents
    - v_charge.free_slot_clawback_cents
    - v_charge.free_slot_topup_cents
    + v_charge.cashback_refund_cents;
  if v_fixed < 0 then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  -- A taxa da PagBank sai da comissão da conta principal, não da parte da casa.
  v_net := v_charge.amount_cents;
  if v_fixed > v_net then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  update public.payment_charges
  set house_fixed_cents = v_fixed
  where id = p_charge_id;
  return v_fixed;
end;
$$;

create or replace function private.apply_share_adjustments(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee integer;
  v_house integer;
  v_discount integer;
  v_charged integer;
  v_asaas integer;
  v_net integer;
  v_room integer;
  v_credit integer;
  v_debit integer;
  v_claw integer;
  v_refund integer;
  v_free integer := 0;
  v_free_claw integer := 0;
  v_for_house integer;
  v_split numeric;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return;
  end if;
  perform private.lock_venue_rewards(v_charge.venue_id);
  with pairs as (
    select d.id as debit_id, f.id as refund_id
    from public.venue_cashback_debits d
    join public.venue_cashback_refunds f on f.debit_id = d.id
    where d.venue_id = v_charge.venue_id
      and d.voided_at is null
      and d.applied_cents = 0
      and d.applied_charge_id is null
      and f.voided_at is null
      and f.applied_cents = 0
  ),
  void_refund as (
    update public.venue_cashback_refunds f
    set voided_at = pg_catalog.now()
    from pairs
    where f.id = pairs.refund_id
    returning pairs.debit_id
  )
  update public.venue_cashback_debits d
  set voided_at = pg_catalog.now()
  where d.id in (select debit_id from void_refund);
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  if v_charge.first_booking_discount_cents > 0
    or v_charge.venue_credit_applied_cents > 0
    or v_charge.empty_slot_offset_cents > 0
    or v_charge.free_slot_topup_cents > 0
    or v_charge.free_slot_applied_cents > 0
    or v_charge.free_slot_clawback_cents > 0
  then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_discount := private.first_booking_discount_for(
    v_charge.user_id, v_charge.venue_id, v_gross,
    v_charge.commission_bps, v_charge.subsidy_cents, v_charge.id
  );
  v_fee := private.reward_cents(v_gross, v_charge.commission_bps);
  v_house := v_gross - v_fee;
  v_charged := v_gross - v_charge.subsidy_cents - v_discount;
  if v_charged <= 0 or v_house > v_charged then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
  end if;
  -- A taxa da PagBank não reduz o teto da casa. v_asaas fica só para o declare antigo.
  v_asaas := 0;
  v_net := v_charged;
  if v_discount > 0 and v_house > v_net then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
    v_asaas := 0;
    v_net := v_charged;
  end if;
  if v_charged <= 0 or v_house > v_charged then
    if private.note_free_slot_shortfall(v_charge.id) then
      if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
        update public.payment_charges
        set gross_amount_cents = v_gross
        where id = v_charge.id;
      end if;
      return;
    end if;
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if v_house > v_net then
    if private.note_free_slot_shortfall(v_charge.id) then
      return;
    end if;
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  v_room := greatest(v_net - v_house, 0);
  v_credit := private.apply_venue_credit(
    v_charge.id, v_charge.venue_id, v_room, false
  );
  v_debit := private.apply_empty_slot_debit(
    v_charge.id, v_charge.venue_id, greatest(v_house, 0), false
  );
  v_for_house := greatest(v_house - v_debit, 0) + v_credit;
  if v_for_house > v_net then
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_claw := private.apply_venue_clawback(
    v_charge.id, v_charge.venue_id, greatest(v_house - v_debit, 0)
  );
  v_refund := private.apply_cashback_refund(
    v_charge.id, v_charge.venue_id, greatest(v_room - v_credit, 0)
  );
  v_free := private.apply_free_slot_credit(
    v_charge.id, v_charge.venue_id,
    greatest(v_room - v_credit - v_refund, 0), false
  );
  v_free_claw := private.apply_free_slot_clawback(
    v_charge.id, v_charge.venue_id,
    greatest(v_house - v_debit - v_claw, 0), false
  );
  v_for_house := greatest(v_house - v_debit - v_claw - v_free_claw, 0)
    + v_credit + v_refund + v_free;
  if v_discount = 0 and v_credit = 0 and v_debit = 0 and v_claw = 0
    and v_refund = 0 and v_free = 0 and v_free_claw = 0
  then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if v_for_house > v_net then
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if private.apply_venue_credit(v_charge.id, v_charge.venue_id, v_room, true)
    is distinct from v_credit
    or private.apply_empty_slot_debit(
      v_charge.id, v_charge.venue_id, greatest(v_house, 0), true
    ) is distinct from v_debit
    or private.apply_free_slot_credit(
      v_charge.id, v_charge.venue_id,
      greatest(v_room - v_credit - v_refund, 0), true
    ) is distinct from v_free
    or private.apply_free_slot_clawback(
      v_charge.id, v_charge.venue_id,
      greatest(v_house - v_debit - v_claw, 0), true
    ) is distinct from v_free_claw
  then
    raise exception 'ajuste mudou antes de gravar' using errcode = '40001';
  end if;
  v_split := ceil((v_for_house::numeric * 1000000) / v_charged) / 10000;
  update public.payment_charges
  set amount_cents = v_charged,
      gross_amount_cents = v_gross,
      first_booking_discount_cents = v_discount,
      venue_credit_applied_cents = v_credit,
      empty_slot_offset_cents = v_debit,
      venue_credit_clawback_cents = v_claw,
      cashback_refund_cents = v_refund,
      free_slot_applied_cents = v_free,
      free_slot_clawback_cents = v_free_claw,
      split_percent = v_split
  where id = v_charge.id;
end;
$$;

create or replace function private.ledger_credit_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee_gross integer;
  v_fee integer;
  v_net integer;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  if v_charge.provider = 'points' then
    return;
  end if;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_fee_gross := ((v_gross::bigint * v_charge.commission_bps + 5000) / 10000)::integer;
  v_fee := v_fee_gross
    - v_charge.subsidy_cents
    - v_charge.first_booking_discount_cents
    - v_charge.venue_credit_applied_cents
    - v_charge.free_slot_applied_cents
    + v_charge.empty_slot_offset_cents
    + v_charge.venue_credit_clawback_cents
    + v_charge.free_slot_clawback_cents
    + v_charge.free_slot_topup_cents
    - v_charge.cashback_refund_cents;
  v_net := v_gross - v_fee_gross;
  if v_charge.free_slot_topup_cents > 0 then
    v_net := greatest(v_charge.amount_cents, 0);
  end if;
  if v_net < 0 or v_fee < 0 then
    raise exception 'comissao negativa' using errcode = '23514';
  end if;
  if v_net > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'house_net', v_net, v_charge.id, ''
    ) on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  end if;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'venue_credit_applied',
    a.amount_cents, v_charge.id, a.entry_id::text
  from public.venue_credit_applications a
  where a.payment_charge_id = v_charge.id
    and a.reversed_at is null
    and a.amount_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'venue_credit_clawback',
    c.applied_cents, v_charge.id, c.id::text
  from public.venue_credit_clawbacks c
  where c.applied_charge_id = v_charge.id
    and c.voided_at is null
    and c.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'free_slot_topup',
    a.amount_cents, v_charge.id, a.id::text
  from public.free_slot_applications a
  where a.payment_charge_id = v_charge.id
    and a.reversed_at is null
    and a.amount_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'free_slot_clawback',
    c.applied_cents, v_charge.id, c.id::text
  from public.free_slot_clawbacks c
  where c.applied_charge_id = v_charge.id
    and c.voided_at is null
    and c.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'empty_slot_offset_refund',
    f.applied_cents, v_charge.id, f.id::text
  from public.venue_cashback_refunds f
  where f.applied_charge_id = v_charge.id
    and f.voided_at is null
    and f.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'empty_slot_offset',
    d.applied_cents, v_charge.id, d.id::text
  from public.venue_cashback_debits d
  where d.applied_charge_id = v_charge.id
    and d.voided_at is null
    and d.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  if v_fee > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'platform', 'credit', 'commission', v_fee, v_charge.id, ''
    ) on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  end if;
end;
$$;

create or replace function public.ledger_reconcile_snapshot(
  p_since timestamptz,
  p_until timestamptz,
  p_payment_ids text[],
  p_transfer_ids text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    or coalesce(w.pagbank_transfer_id, w.asaas_transfer_id) = any (coalesce(p_transfer_ids, array[]::text[]))
    or w.external_reference = any (coalesce(p_transfer_ids, array[]::text[]));

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    into v_withdrawals
  from (
    select
      w.id,
      w.venue_id,
      w.external_reference,
      coalesce(w.pagbank_transfer_id, w.asaas_transfer_id, '') as pagbank_transfer_id,
      w.status,
      w.amount_cents
    from public.venue_withdrawals w
    where (w.created_at >= p_since and w.created_at < p_until)
      or (w.updated_at >= p_since and w.updated_at < p_until)
      or coalesce(w.pagbank_transfer_id, w.asaas_transfer_id) = any (coalesce(p_transfer_ids, array[]::text[]))
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
$$;

create or replace function public.admin_earnings(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_venue_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_gross bigint := 0;
  v_redeemed bigint := 0;
  v_cashback bigint := 0;
  v_cashback_platform bigint := 0;
  v_fee bigint := 0;
  v_fee_rows integer := 0;
  v_liability jsonb;
begin
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;
  select coalesce(sum(
    case
      when account = 'platform' and kind = 'commission' and direction = 'credit'
        then amount_cents
      when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
        then -amount_cents
      else 0
    end
  ), 0)::bigint
  into v_gross
  from public.ledger_entries
  where (p_from is null or created_at >= p_from)
    and (p_to is null or created_at < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  select coalesce(sum(subsidy_cents), 0)::bigint
  into v_redeemed
  from public.payment_charges
  where status = 'paid'
    and (p_from is null or coalesce(paid_at, created_at) >= p_from)
    and (p_to is null or coalesce(paid_at, created_at) < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  select coalesce(sum(e.amount_cents), 0)::bigint
  into v_cashback
  from public.scape_point_entries e
  left join public.payment_charges c on c.id = e.source_charge_id
  where e.kind = 'accrual'
    and e.program = 'cashback'
    and e.review_status is distinct from 'rejected'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id);

  select coalesce(sum(d.platform_cents), 0)::bigint
  into v_cashback_platform
  from public.cashback_draws d
  left join public.payment_charges c on c.id = d.payment_charge_id
  where (p_from is null or d.created_at >= p_from)
    and (p_to is null or d.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id);

  select
    count(*) filter (where provider_fee_cents is not null)::integer,
    coalesce(sum(provider_fee_cents) filter (where provider_fee_cents is not null), 0)::bigint
  into v_fee_rows, v_fee
  from public.payment_charges
  where (p_from is null or coalesce(paid_at, created_at) >= p_from)
    and (p_to is null or coalesce(paid_at, created_at) < p_to)
    and (p_venue_id is null or venue_id = p_venue_id);

  v_liability := public.admin_scape_liability();

  return pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'venue_id', p_venue_id,
    'gross_commission_cents', v_gross,
    'rewards_redeemed_cents', v_redeemed,
    'cashback_issued_cents', v_cashback,
    'cashback_platform_cents', v_cashback_platform,
    'open_points', coalesce((v_liability ->> 'available_points')::integer, 0),
    'open_points_cents', coalesce((v_liability ->> 'available_points')::integer, 0)
      * coalesce((v_liability ->> 'point_value_cents')::integer, 1),
    'pending_points', coalesce((v_liability ->> 'pending_points')::integer, 0),
    'provider_fee_cents', case when v_fee_rows = 0 then null else v_fee end,
    'pagbank_fee_rows', v_fee_rows,
    'by_venue', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.name)
      from (
        select
          v.id as venue_id,
          v.name,
          coalesce(c.gross_cents, 0) as gross_commission_cents,
          coalesce(r.redeemed_cents, 0) as rewards_redeemed_cents,
          coalesce(k.cashback_cents, 0) as cashback_issued_cents,
          coalesce(d.debt_cents, 0) as open_debt_cents
        from public.venues v
        left join (
          select venue_id, sum(
            case
              when account = 'platform' and kind = 'commission' and direction = 'credit'
                then amount_cents
              when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
                then -amount_cents
              else 0
            end
          )::bigint as gross_cents
          from public.ledger_entries
          where (p_from is null or created_at >= p_from)
            and (p_to is null or created_at < p_to)
          group by venue_id
        ) c on c.venue_id = v.id
        left join (
          select venue_id, sum(subsidy_cents)::bigint as redeemed_cents
          from public.payment_charges
          where status = 'paid'
            and (p_from is null or coalesce(paid_at, created_at) >= p_from)
            and (p_to is null or coalesce(paid_at, created_at) < p_to)
          group by venue_id
        ) r on r.venue_id = v.id
        left join (
          select ch.venue_id, sum(e.amount_cents)::bigint as cashback_cents
          from public.scape_point_entries e
          join public.payment_charges ch on ch.id = e.source_charge_id
          where e.kind = 'accrual'
            and e.program = 'cashback'
            and e.review_status is distinct from 'rejected'
            and not exists (
              select 1 from public.scape_point_entries rev
              where rev.relates_to = e.id and rev.kind = 'reversal'
            )
            and (p_from is null or e.created_at >= p_from)
            and (p_to is null or e.created_at < p_to)
          group by ch.venue_id
        ) k on k.venue_id = v.id
        left join (
          select venue_id, sum(open_cents)::bigint as debt_cents
          from (
            select venue_id, (amount_cents - applied_cents) as open_cents
            from public.venue_credit_clawbacks
            where voided_at is null
              and neutralized_at is null
              and applied_cents < amount_cents
            union all
            select venue_id, (amount_cents - applied_cents)
            from public.venue_cashback_debits
            where voided_at is null
              and applied_cents < amount_cents
          ) open_debt
          group by venue_id
        ) d on d.venue_id = v.id
        where (p_venue_id is null or v.id = p_venue_id)
          and (
            c.venue_id is not null
            or r.venue_id is not null
            or k.venue_id is not null
            or d.venue_id is not null
          )
      ) s
    ), '[]'::jsonb),
    'open_components', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.venue_name, s.kind)
      from (
        select
          v.id as venue_id,
          v.name as venue_name,
          'clawback'::text as kind,
          'debt'::text as direction,
          (c.amount_cents - c.applied_cents) as open_cents,
          true as all_or_nothing
        from public.venue_credit_clawbacks c
        join public.venues v on v.id = c.venue_id
        where c.voided_at is null
          and c.neutralized_at is null
          and c.applied_cents < c.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
        union all
        select
          v.id,
          v.name,
          'cashback_debit',
          'debt',
          d.amount_cents - d.applied_cents,
          true
        from public.venue_cashback_debits d
        join public.venues v on v.id = d.venue_id
        where d.voided_at is null
          and d.applied_cents < d.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
        union all
        select
          v.id,
          v.name,
          'venue_credit',
          'credit',
          e.amount_cents - e.applied_cents,
          true
        from public.venue_referral_entries e
        join public.venues v on v.id = e.venue_id
        where e.kind = 'accrual'
          and e.settlement = 'released'
          and e.review_status is distinct from 'em_revisao'
          and e.review_status is distinct from 'rejected'
          and e.applied_cents < e.amount_cents
          and not exists (
            select 1 from public.venue_referral_entries r
            where r.relates_to = e.id and r.kind = 'reversal'
          )
          and (p_venue_id is null or v.id = p_venue_id)
      ) s
    ), '[]'::jsonb)
  );
end;
$$;


-- Token do Connect, cifrado com a chave que já está no Vault.
-- A tabela antiga não é lida: o ciphertext de lá não é token PagBank.
create table public.venue_pagbank_tokens (
  venue_id uuid primary key references public.venues(id) on delete cascade,
  access_token bytea not null,
  refresh_token bytea,
  access_expires_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now()
);

revoke all on table public.venue_pagbank_tokens
  from public, anon, authenticated;

create or replace function public.store_venue_pagbank_tokens(
  p_venue_id uuid,
  p_access_token text,
  p_refresh_token text,
  p_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := private.asaas_subaccount_key();
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
$$;

revoke all on function public.store_venue_pagbank_tokens(uuid, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.store_venue_pagbank_tokens(uuid, text, text, timestamptz)
  to service_role;

create or replace function public.read_venue_pagbank_tokens(p_venue_id uuid)
returns table (
  access_token text,
  refresh_token text,
  access_expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text := private.asaas_subaccount_key();
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
$$;

revoke all on function public.read_venue_pagbank_tokens(uuid)
  from public, anon, authenticated;
grant execute on function public.read_venue_pagbank_tokens(uuid) to service_role;

create or replace view public.venue_provider_keys as
select venue_id, access_token as api_key
from public.venue_pagbank_tokens;

revoke all on table public.venue_provider_keys from public, anon, authenticated;

create or replace function public.read_venue_provider_key(p_venue_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select access_token
  from public.read_venue_pagbank_tokens(p_venue_id);
$$;

create or replace function public.store_venue_provider_key(
  p_venue_id uuid,
  p_api_key text
)
returns void
language sql
security definer
set search_path = ''
as $$
  select public.store_venue_pagbank_tokens(p_venue_id, p_api_key, null, null);
$$;

revoke all on function public.read_venue_provider_key(uuid)
  from public, anon, authenticated;
revoke all on function public.store_venue_provider_key(uuid, text)
  from public, anon, authenticated;
grant execute on function public.read_venue_provider_key(uuid) to service_role;
grant execute on function public.store_venue_provider_key(uuid, text) to service_role;

-- State do Connect: aleatório, de uso único, expira em 10 minutos
-- e só o usuário que pediu o link consegue trocar o code.
create table public.pagbank_connect_states (
  state text primary key,
  venue_id uuid not null references public.venues(id) on delete cascade,
  user_id uuid not null,
  redirect_uri text not null,
  expires_at timestamptz not null,
  used_at timestamptz
);

revoke all on table public.pagbank_connect_states
  from public, anon, authenticated;

create or replace function public.begin_pagbank_connect(
  p_venue_id uuid,
  p_user_id uuid,
  p_redirect_uri text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state text;
begin
  if p_venue_id is null or p_user_id is null then
    raise exception 'state' using errcode = '22023';
  end if;
  if p_redirect_uri is null or left(btrim(p_redirect_uri), 8) <> 'https://' then
    raise exception 'state' using errcode = '22023';
  end if;
  delete from public.pagbank_connect_states
  where venue_id = p_venue_id
    and user_id = p_user_id
    and used_at is null;
  v_state := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.pagbank_connect_states (
    state, venue_id, user_id, redirect_uri, expires_at
  ) values (
    v_state,
    p_venue_id,
    p_user_id,
    btrim(p_redirect_uri),
    pg_catalog.now() + interval '10 minutes'
  );
  return v_state;
end;
$$;

revoke all on function public.begin_pagbank_connect(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.begin_pagbank_connect(uuid, uuid, text)
  to service_role;

create or replace function public.consume_pagbank_connect(
  p_state text,
  p_user_id uuid
)
returns table (venue_id uuid, redirect_uri text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.pagbank_connect_states%rowtype;
begin
  if p_state is null or btrim(p_state) = '' or p_user_id is null then
    raise exception 'state' using errcode = 'P0001';
  end if;
  select * into v_row
  from public.pagbank_connect_states
  where state = btrim(p_state)
  for update;
  if not found
    or v_row.used_at is not null
    or v_row.expires_at <= pg_catalog.now()
    or v_row.user_id is distinct from p_user_id
  then
    raise exception 'state' using errcode = 'P0001';
  end if;
  update public.pagbank_connect_states
  set used_at = pg_catalog.now()
  where state = v_row.state;
  return query select v_row.venue_id, v_row.redirect_uri;
end;
$$;

revoke all on function public.consume_pagbank_connect(text, uuid)
  from public, anon, authenticated;
grant execute on function public.consume_pagbank_connect(text, uuid)
  to service_role;

create or replace function public.transfer_ref_venue(p_reference text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select venue_id
  from public.venue_withdrawals
  where external_reference = btrim(coalesce(p_reference, ''))
    and btrim(coalesce(p_reference, '')) <> ''
  limit 1;
$$;

revoke all on function public.transfer_ref_venue(text)
  from public, anon, authenticated;
grant execute on function public.transfer_ref_venue(text) to service_role;

create or replace function private.groups_require_payout_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wallet text;
  v_status text;
begin
  if auth.uid() is null then
    return new;
  end if;
  select v.status, v.pagbank_account_id
    into v_status, v_wallet
  from public.venues v
  where v.id = new.venue_id;
  if v_status = 'approved'
    and v_wallet is not null
    and btrim(v_wallet) <> ''
  then
    return new;
  end if;
  raise exception 'conta de recebimento pendente' using errcode = 'P0001';
end;
$$;

create or replace function public.venue_finance_ready(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues venue
    where venue.id = p_venue_id
      and venue.status = 'approved'
      and venue.suspended_at is null
      and venue.pagbank_account_id is not null
      and pg_catalog.btrim(venue.pagbank_account_id) <> ''
      and exists (
        select 1
        from public.venue_bank_accounts bank
        where bank.venue_id = venue.id
      )
  );
$$;

create or replace function public.venue_payout_wallet(p_venue_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select pagbank_account_id
  from public.venues
  where id = p_venue_id
    and status = 'approved';
$$;

create or replace function public.list_due_venue_payouts()
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
    public.venue_weekly_attempt_key(s.venue_id, pg_catalog.now()),
    s.min_amount_cents
  from public.venue_payout_schedules s
  join public.venues v on v.id = s.venue_id
  join public.venue_bank_accounts b on b.venue_id = s.venue_id
  where public.venue_payouts_enabled()
    and s.enabled
    and s.frequency = 'weekly'
    and v.status = 'approved'
    and v.pagbank_account_id is not null
    and (
      b.withdrawals_blocked_until is null
      or b.withdrawals_blocked_until <= pg_catalog.now()
    )
    and public.venue_weekly_attempt_key(s.venue_id, pg_catalog.now()) is not null;
$$;

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
    and pagbank_account_id is not null;
$$;

drop function public.list_stale_pending_withdrawals(integer);

create function public.list_stale_pending_withdrawals(p_hours integer)
returns table (
  id uuid,
  venue_id uuid,
  pagbank_transfer_id text,
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
  select w.id, w.venue_id, w.pagbank_transfer_id, w.external_reference
  from public.venue_withdrawals w
  join public.venues v on v.id = w.venue_id
  where w.status = 'pending'
    and v.status = 'approved'
    and w.updated_at <= pg_catalog.now() - pg_catalog.make_interval(hours => p_hours);
end;
$$;

revoke all on function public.list_stale_pending_withdrawals(integer)
  from public, anon, authenticated;
grant execute on function public.list_stale_pending_withdrawals(integer)
  to service_role;

drop view public.venues_vitrine;

alter table public.venues drop column receives_payments;

alter table public.venues
  add column receives_payments boolean
  generated always as (
    pagbank_account_id is not null and btrim(pagbank_account_id) <> ''
  ) stored;

grant select (receives_payments) on table public.venues to anon, authenticated;

revoke select (pagbank_account_id) on table public.venues
  from anon, authenticated;

alter table public.payment_webhook_errors
  drop constraint payment_webhook_errors_source_check;

alter table public.payment_webhook_errors
  add constraint payment_webhook_errors_source_check
  check (source in (
    'pagbank-webhook',
    'pagbank-transfer-webhook',
    'asaas-webhook',
    'asaas-transfer-webhook'
  ));

create or replace function public.note_webhook_error(
  p_source text,
  p_code text,
  p_provider_ref text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source text := pg_catalog.btrim(coalesce(p_source, ''));
  v_code text := pg_catalog.btrim(coalesce(p_code, ''));
  v_ref text := pg_catalog.btrim(coalesce(p_provider_ref, ''));
begin
  if v_source not in ('pagbank-webhook', 'pagbank-transfer-webhook') then
    return;
  end if;
  if v_code !~ '^[a-z0-9_]{1,48}$' then
    v_code := 'unknown';
  end if;
  if v_ref !~ '^[A-Za-z0-9_-]{1,64}$' then
    v_ref := '';
  end if;
  insert into public.payment_webhook_errors (source, code, provider_ref)
  values (v_source, v_code, v_ref);
end;
$$;

create or replace function private.note_split_divergence(
  p_provider_ref text,
  p_event text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_event not in (
    'PAYMENT_SPLIT_DIVERGENCE_BLOCK',
    'PAYMENT_SPLIT_DIVERGENCE_BLOCK_FINISHED'
  ) then
    return false;
  end if;
  update public.payment_charges
  set split_divergence_at = pg_catalog.now(),
      split_divergence_event = p_event
  where provider_ref = p_provider_ref
    and provider = 'pagbank';
  return found;
end;
$$;

grant select (pagbank_customer_id) on table public.profiles to authenticated;
grant update (pagbank_customer_id) on table public.profiles to authenticated;

create view public.venues_vitrine
with (security_invoker = true) as
select
  id,
  city_id,
  name,
  neighborhood,
  street_address,
  address_number,
  postal_code,
  latitude,
  longitude,
  category,
  badge,
  status,
  created_at,
  receives_payments,
  featured_rank,
  public.venue_finance_ready(id) as finance_ready
from public.venues;

revoke all on table public.venues_vitrine from public, anon, authenticated;
grant select on table public.venues_vitrine to anon, authenticated, service_role;


create or replace function public.admin_list_venues(
  p_status text default null,
  p_query text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_like text := private.admin_like(p_query);
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
begin
  if v_status is not null
    and v_status not in ('pending', 'approved', 'rejected', 'merged', 'suspended')
  then
    raise exception 'status invalido' using errcode = '22023';
  end if;
  return pg_catalog.jsonb_build_object(
    'platform_bps', (select commission_bps from public.platform_settings where id = 1),
    'houses', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.name)
      from (
        select
          v.id,
          v.name,
          v.city_id,
          v.status,
          v.suspended_at is not null as suspended,
          v.pagbank_account_id is not null as has_wallet,
          coalesce(c.commission_bps, s.commission_bps) as commission_bps,
          c.venue_id is not null as commission_override,
          v.created_at
        from public.venues v
        cross join public.platform_settings s
        left join public.venue_commissions c on c.venue_id = v.id
        where s.id = 1
          and (
            v_status is null
            or (v_status = 'suspended' and v.suspended_at is not null)
            or (v_status <> 'suspended' and v.status = v_status)
          )
          and (
            btrim(coalesce(p_query, '')) = ''
            or v.name ilike v_like
          )
        order by v.name
        limit 200
      ) s
    ), '[]'::jsonb)
  );
end;
$$;


create or replace function public.admin_venue(p_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_house public.venues%rowtype;
  v_platform integer;
  v_rate integer;
  v_override boolean;
begin
  select * into v_house from public.venues where id = p_venue_id;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  select commission_bps into v_platform
  from public.platform_settings where id = 1;
  select c.commission_bps into v_rate
  from public.venue_commissions c where c.venue_id = p_venue_id;
  v_override := v_rate is not null;
  v_rate := coalesce(v_rate, v_platform);
  return pg_catalog.jsonb_build_object(
    'id', v_house.id,
    'name', v_house.name,
    'city_id', v_house.city_id,
    'neighborhood', v_house.neighborhood,
    'street_address', v_house.street_address,
    'address_number', v_house.address_number,
    'postal_code', v_house.postal_code,
    'phone', v_house.phone,
    'category', v_house.category,
    'badge', v_house.badge,
    'status', v_house.status,
    'suspended', v_house.suspended_at is not null,
    'suspended_at', v_house.suspended_at,
    'has_wallet', v_house.pagbank_account_id is not null,
    'document_kind', v_house.document_kind,
    'document_last4', right(v_house.document_number, 4),
    'owner_id', v_house.owner_id,
    'owner_name', (select display_name from public.profiles where id = v_house.owner_id),
    'owner_email', (select email from auth.users where id = v_house.owner_id),
    'invite_code', (
      select i.code from public.partner_invites i where i.id = v_house.invite_id
    ),
    'platform_bps', v_platform,
    'commission_bps', v_rate,
    'commission_override', v_override,
    'featured_rank', v_house.featured_rank,
    'snapshots', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(c) order by c.created_at desc)
      from (
        select id, commission_bps, status, created_at
        from public.payment_charges
        where venue_id = p_venue_id
        order by created_at desc
        limit 8
      ) c
    ), '[]'::jsonb),
    'rooms', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(r) order by r.name)
      from (
        select id, name, featured_rank
        from public.rooms
        where venue_id = p_venue_id
        order by name
      ) r
    ), '[]'::jsonb)
  );
end;
$$;


create or replace function public.admin_review_venue(
  p_venue_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before text;
  v_wallet text;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  select status into v_before from public.venues where id = p_venue_id for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v_before <> 'pending' then
    raise exception 'casa nao esta pendente' using errcode = 'P0001';
  end if;
  update public.venues
  set status = p_decision,
      reviewed_by = v_uid,
      reviewed_at = pg_catalog.now()
  where id = p_venue_id;
  select pagbank_account_id into v_wallet from public.venues where id = p_venue_id;
  perform private.admin_audit(
    v_uid,
    'review_venue',
    'venues',
    p_venue_id::text,
    pg_catalog.jsonb_build_object('status', v_before),
    pg_catalog.jsonb_build_object('status', p_decision)
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'status', p_decision,
    'needs_subaccount', p_decision = 'approved'
      and (v_wallet is null or btrim(v_wallet) = '')
  );
end;
$$;


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
      coalesce(c.provider_ref, '') as provider_ref,
      c.created_at,
      v.name as venue_name
    from public.payment_charges c
    join public.venues v on v.id = c.venue_id
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

