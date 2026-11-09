-- Aborta se já existem linhas agregadas de recompensa. Produção não tem
-- essas linhas; um banco de teste antigo não pode ganhar component_key ''
-- e duplicar o valor no replay.
do $$
begin
  if exists (
    select 1
    from public.ledger_entries
    where kind in (
      'venue_credit_applied',
      'venue_credit_refund',
      'venue_credit_clawback',
      'venue_credit_clawback_refund',
      'venue_credit_clawback_offset'
    )
  ) then
    raise exception using
      errcode = '55000',
      message = 'lancamentos agregados de recompensa sem origem; 20261108190000 nao reescreve essas linhas';
  end if;
end $$;

-- Um lançamento por componente. A chave é cobrança + kind + direção + origem.
-- A main já tem o índice sem origem; esta migration só roda nos pacotes novos.
-- Produção não aplicou o #84.
--
-- Cicatriz: o clawback já neutralizado não é estornado de novo. O débito fica
-- na cobrança que o cobrou e o offset fica na cobrança consumidora. A soma da
-- casa fecha; o livro daquela cobrança, sozinho, não volta a zero. Isso evita
-- devolver duas vezes o que o offset já devolveu.

alter table public.ledger_entries
  add column if not exists component_key text not null default '';

drop index if exists public.ledger_entries_charge_kind_direction_uidx;

create unique index if not exists ledger_entries_charge_kind_direction_uidx
  on public.ledger_entries (payment_charge_id, kind, direction, component_key);

create or replace function private.lock_venue_rewards(p_venue_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform id
  from public.venues
  where id = p_venue_id
  for update;
end;
$$;

revoke all on function private.lock_venue_rewards(uuid)
  from public, anon, authenticated;

create or replace function private.apply_venue_credit(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.venue_referral_entries%rowtype;
  v_open integer;
begin
  perform private.lock_venue_rewards(p_venue_id);
  if v_left <= 0 then
    return 0;
  end if;
  if exists (
    select 1 from public.payment_charges
    where id = p_charge_id
      and status in ('refunded', 'cancelled', 'failed')
  ) then
    return 0;
  end if;
  if exists (
    select 1 from public.venue_credit_applications
    where payment_charge_id = p_charge_id
  ) then
    select coalesce(sum(amount_cents), 0)::integer into v_taken
    from public.venue_credit_applications
    where payment_charge_id = p_charge_id
      and reversed_at is null;
    return v_taken;
  end if;
  for v_row in
    select *
    from public.venue_referral_entries
    where venue_id = p_venue_id
      and kind = 'accrual'
      and settlement = 'released'
      and review_status is distinct from 'em_revisao'
      and review_status is distinct from 'rejected'
      and not exists (
        select 1 from public.venue_referral_entries r
        where r.relates_to = venue_referral_entries.id and r.kind = 'reversal'
      )
    order by available_at, created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    update public.venue_referral_entries
    set applied_cents = amount_cents,
        settlement = 'applied'
    where id = v_row.id;
    insert into public.venue_credit_applications (
      entry_id, payment_charge_id, amount_cents
    ) values (
      v_row.id, p_charge_id, v_open
    );
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

revoke all on function private.apply_venue_credit(uuid, uuid, integer)
  from public, anon, authenticated;

create or replace function private.apply_venue_clawback(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.venue_credit_clawbacks%rowtype;
  v_open integer;
begin
  perform private.lock_venue_rewards(p_venue_id);
  if v_left <= 0 then
    return 0;
  end if;
  if exists (
    select 1 from public.payment_charges
    where id = p_charge_id
      and status in ('refunded', 'cancelled', 'failed')
  ) then
    return 0;
  end if;
  for v_row in
    select *
    from public.venue_credit_clawbacks
    where venue_id = p_venue_id
      and voided_at is null
      and neutralized_at is null
      and applied_cents < amount_cents
    order by created_at
    for update
  loop
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    update public.venue_credit_clawbacks
    set applied_cents = amount_cents,
        applied_charge_id = p_charge_id
    where id = v_row.id
      and applied_cents = v_row.applied_cents
      and voided_at is null
      and neutralized_at is null;
    if not found then
      continue;
    end if;
    v_left := v_left - v_open;
    v_taken := v_taken + v_open;
    exit when v_left <= 0;
  end loop;
  return v_taken;
end;
$$;

revoke all on function private.apply_venue_clawback(uuid, uuid, integer)
  from public, anon, authenticated;

create or replace function private.restore_applied_venue_credits(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.lock_venue_rewards(ch.venue_id)
  from public.payment_charges ch
  where ch.id = p_charge_id;

  with locked as (
    select c.id, c.applied_cents
    from public.venue_credit_clawbacks c
    join public.venue_credit_applications a on a.entry_id = c.entry_id
    where a.payment_charge_id = p_charge_id
      and a.reversed_at is null
      and c.voided_at is null
      and c.neutralized_at is null
    for update of c
  ),
  voided as (
    update public.venue_credit_clawbacks c
    set voided_at = pg_catalog.now()
    from locked l
    where c.id = l.id
      and l.applied_cents = 0
    returning c.id
  ),
  posted as (
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    )
    select
      ch.venue_id,
      ch.group_id,
      ch.user_id,
      'house',
      'credit',
      'venue_credit_clawback_offset',
      l.applied_cents,
      p_charge_id,
      l.id::text
    from locked l
    join public.payment_charges ch on ch.id = p_charge_id
    where l.applied_cents > 0
    on conflict (payment_charge_id, kind, direction, component_key) do nothing
    returning component_key
  )
  update public.venue_credit_clawbacks c
  set neutralized_at = pg_catalog.now()
  from locked l
  where c.id = l.id
    and l.applied_cents > 0;

  update public.venue_referral_entries e
  set settlement = 'released',
      applied_cents = 0
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and a.entry_id = e.id
    and e.settlement = 'applied'
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  update public.venue_credit_applications
  set reversed_at = pg_catalog.now()
  where payment_charge_id = p_charge_id
    and reversed_at is null;

  update public.venue_credit_clawbacks
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null
    and neutralized_at is null;
end;
$$;

revoke all on function private.restore_applied_venue_credits(uuid)
  from public, anon, authenticated;

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
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_fee_gross := (
    (v_gross::bigint * v_charge.commission_bps + 5000) / 10000
  )::integer;
  v_fee := v_fee_gross
    - v_charge.subsidy_cents
    - v_charge.first_booking_discount_cents
    - v_charge.venue_credit_applied_cents
    + v_charge.venue_credit_clawback_cents;
  v_net := v_gross - v_fee_gross;
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
    )
    on conflict (payment_charge_id, kind, direction, component_key) do nothing;
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
  if v_fee > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'platform', 'credit', 'commission', v_fee, v_charge.id, ''
    )
    on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  end if;
end;
$$;

revoke all on function private.ledger_credit_charge(uuid)
  from public, anon, authenticated;

create or replace function private.ledger_reverse_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    credit.venue_id,
    credit.group_id,
    credit.user_id,
    credit.account,
    'debit',
    case credit.kind
      when 'commission' then 'commission_refund'
      when 'venue_credit_applied' then 'venue_credit_refund'
      else 'house_refund'
    end,
    credit.amount_cents,
    credit.payment_charge_id,
    credit.component_key
  from public.ledger_entries as credit
  where credit.payment_charge_id = p_charge_id
    and credit.direction = 'credit'
    and credit.kind not in (
      'venue_credit_clawback_offset',
      'venue_credit_clawback_refund',
      'empty_slot_offset_undo'
    )
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    debit.venue_id,
    debit.group_id,
    debit.user_id,
    debit.account,
    'credit',
    'venue_credit_clawback_refund',
    debit.amount_cents,
    debit.payment_charge_id,
    debit.component_key
  from public.ledger_entries as debit
  join public.venue_credit_clawbacks c
    on c.id::text = debit.component_key
  where debit.payment_charge_id = p_charge_id
    and debit.direction = 'debit'
    and debit.kind = 'venue_credit_clawback'
    and c.neutralized_at is null
    and c.voided_at is null
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;

  perform private.restore_applied_venue_credits(p_charge_id);
end;
$$;

revoke all on function private.ledger_reverse_charge(uuid)
  from public, anon, authenticated;
