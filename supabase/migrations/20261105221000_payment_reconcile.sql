-- Trabalho da reconciliação. A Edge Function consulta o Asaas só depois
-- deste claim. O agendamento fica na migração seguinte.
--
-- Cobrança creating: novo attempt_id e lease de 2 minutos. O create-charge
-- só retoma com claim_expired (lease vencido) e só solta com o attempt
-- vigente, então não pega a linha que o reconciliador acabou de cercar.
-- Órfão: claimed_at, sem trocar a cobrança. A identidade dele é o
-- provider_ref, não o externalReference da cobrança atual.

alter table private.orphan_payments
  add column if not exists resolved_at timestamptz;

alter table private.orphan_payments
  add column if not exists claimed_at timestamptz;

create or replace function private.claim_payment_reconciliation()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_creating jsonb;
  v_orphans jsonb;
begin
  with picked as (
    select c.id
    from public.payment_charges c
    where c.status = 'creating'
      and c.provider_ref is null
      and (
        c.reserved_at is null
        or c.reserved_at < pg_catalog.now() - interval '2 minutes'
      )
    order by c.reserved_at nulls first, c.id
    limit 10
    for update skip locked
  ),
  updated as (
    update public.payment_charges charge
    set
      attempt_id = gen_random_uuid(),
      reserved_at = pg_catalog.now()
    from picked
    where charge.id = picked.id
    returning
      charge.id,
      charge.attempt_id,
      charge.billing_type,
      charge.group_id,
      charge.user_id,
      charge.idempotency_key
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'charge_id', updated.id,
    'attempt_id', updated.attempt_id,
    'billing_type', updated.billing_type,
    'group_id', updated.group_id,
    'user_id', updated.user_id,
    'external_reference', case
      when updated.billing_type = 'PIX'
        then 'pix:' || updated.group_id::text || ':' || updated.user_id::text
      else updated.idempotency_key
    end
  )), '[]'::jsonb)
  into v_creating
  from updated;

  with picked as (
    select o.id
    from private.orphan_payments o
    where o.resolved_at is null
      and (
        o.claimed_at is null
        or o.claimed_at < pg_catalog.now() - interval '2 minutes'
      )
    order by o.created_at, o.id
    limit 10
    for update skip locked
  ),
  updated as (
    update private.orphan_payments orphan
    set claimed_at = pg_catalog.now()
    from picked
    where orphan.id = picked.id
    returning
      orphan.id,
      orphan.provider_ref,
      orphan.charge_id,
      orphan.attempt_id,
      orphan.billing_type,
      orphan.claimed_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', updated.id,
    'provider_ref', updated.provider_ref,
    'charge_id', updated.charge_id,
    'attempt_id', updated.attempt_id,
    'billing_type', updated.billing_type,
    'claimed_at', updated.claimed_at
  )), '[]'::jsonb)
  into v_orphans
  from updated;

  return jsonb_build_object('creating', v_creating, 'orphans', v_orphans);
end;
$$;

-- Só move a cobrança que ainda é este pagamento. attempt_id e
-- provider_ref têm de bater. Outra tentativa devolve skipped e não altera.
create or replace function private.settle_orphan_charge(
  p_charge_id uuid,
  p_attempt_id uuid,
  p_provider_ref text,
  p_next_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_result jsonb;
begin
  if p_next_status not in ('cancelled', 'refunded') then
    raise exception 'status invalido' using errcode = '22023';
  end if;
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return pg_catalog.jsonb_build_object('applied', false, 'skipped', true);
  end if;
  if v_charge.status = 'paid' then
    if p_next_status = 'refunded'
      and v_charge.provider_ref is not distinct from p_provider_ref
      and v_charge.attempt_id is not distinct from p_attempt_id then
      v_result := private.apply_payment_transition(
        p_charge_id,
        'refunded',
        false
      );
      if coalesce(v_result ->> 'status', '') is distinct from 'refunded' then
        return pg_catalog.jsonb_build_object(
          'applied', false,
          'skipped', false,
          'status', v_result ->> 'status'
        );
      end if;
      return v_result || pg_catalog.jsonb_build_object('skipped', false);
    end if;
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'skipped', false,
      'status', v_charge.status
    );
  end if;
  if v_charge.provider_ref is distinct from p_provider_ref
    or v_charge.status not in ('creating', 'authorized') then
    return pg_catalog.jsonb_build_object('applied', false, 'skipped', true);
  end if;
  if v_charge.attempt_id is distinct from p_attempt_id then
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'skipped', false,
      'status', v_charge.status
    );
  end if;
  v_result := private.apply_payment_transition(
    p_charge_id,
    p_next_status,
    false
  );
  if coalesce(v_result ->> 'status', '') is distinct from p_next_status then
    return pg_catalog.jsonb_build_object(
      'applied', false,
      'skipped', false,
      'status', v_result ->> 'status'
    );
  end if;
  return v_result || pg_catalog.jsonb_build_object('skipped', false);
end;
$$;

-- Renova o lease só se este worker ainda for o dono do attempt.
-- Sem linha, a ação no Asaas não acontece.
create or replace function private.confirm_reconcile_claim(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  update public.payment_charges
  set reserved_at = pg_catalog.now()
  where id = p_charge_id
    and attempt_id = p_attempt_id
    and status = 'creating'
    and provider_ref is null
  returning id into v_id;
  return v_id is not null;
end;
$$;

-- O claimed_at devolvido no claim é o token. Outro worker que já
-- renovou não deixa este confirmar.
create or replace function private.confirm_orphan_claim(
  p_id uuid,
  p_claimed_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- now() não muda na transação; o token precisa avançar a cada confirm.
  update private.orphan_payments
  set claimed_at = pg_catalog.clock_timestamp()
  where id = p_id
    and claimed_at = p_claimed_at
    and resolved_at is null
  returning id into v_id;
  return v_id is not null;
end;
$$;

create or replace function private.mark_orphan_resolved(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.orphan_payments
  set resolved_at = pg_catalog.now()
  where id = p_id
    and resolved_at is null;
  return found;
end;
$$;

-- Só apaga a cobrança depois do estorno confirmado, sem crédito no livro.
create or replace function private.delete_compensated_charge(
  p_charge_id uuid,
  p_attempt_id uuid,
  p_provider_ref text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.ledger_entries entry
    where entry.payment_charge_id = p_charge_id
      and entry.direction = 'credit'
  ) then
    return false;
  end if;
  delete from public.payment_charges charge
  where charge.id = p_charge_id
    and charge.attempt_id is not distinct from p_attempt_id
    and charge.provider_ref = p_provider_ref
    and charge.status = 'cancelled'
    and charge.billing_type = 'CREDIT_CARD';
  return found;
end;
$$;

revoke all on function private.claim_payment_reconciliation()
  from public, anon, authenticated;
revoke all on function private.confirm_reconcile_claim(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.confirm_orphan_claim(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function private.settle_orphan_charge(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.mark_orphan_resolved(uuid)
  from public, anon, authenticated;
revoke all on function private.delete_compensated_charge(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function private.claim_payment_reconciliation() to service_role;
grant execute on function private.confirm_reconcile_claim(uuid, uuid)
  to service_role;
grant execute on function private.confirm_orphan_claim(uuid, timestamptz)
  to service_role;
grant execute on function private.settle_orphan_charge(uuid, uuid, text, text)
  to service_role;
grant execute on function private.mark_orphan_resolved(uuid) to service_role;
grant execute on function private.delete_compensated_charge(uuid, uuid, text)
  to service_role;

create or replace function public.claim_payment_reconciliation()
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.claim_payment_reconciliation();
$$;

create or replace function public.confirm_reconcile_claim(
  p_charge_id uuid,
  p_attempt_id uuid
)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.confirm_reconcile_claim(p_charge_id, p_attempt_id);
$$;

create or replace function public.confirm_orphan_claim(
  p_id uuid,
  p_claimed_at timestamptz
)
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.confirm_orphan_claim(p_id, p_claimed_at);
$$;

create or replace function public.settle_orphan_charge(
  p_charge_id uuid,
  p_attempt_id uuid,
  p_provider_ref text,
  p_next_status text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select private.settle_orphan_charge(
    p_charge_id, p_attempt_id, p_provider_ref, p_next_status
  );
$$;

create or replace function public.mark_orphan_resolved(p_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.mark_orphan_resolved(p_id);
$$;

create or replace function public.delete_compensated_charge(
  p_charge_id uuid,
  p_attempt_id uuid,
  p_provider_ref text
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.delete_compensated_charge(
    p_charge_id, p_attempt_id, p_provider_ref
  );
$$;

revoke all on function public.claim_payment_reconciliation()
  from public, anon, authenticated;
revoke all on function public.confirm_reconcile_claim(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.confirm_orphan_claim(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.settle_orphan_charge(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.mark_orphan_resolved(uuid)
  from public, anon, authenticated;
revoke all on function public.delete_compensated_charge(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_payment_reconciliation() to service_role;
grant execute on function public.confirm_reconcile_claim(uuid, uuid)
  to service_role;
grant execute on function public.confirm_orphan_claim(uuid, timestamptz)
  to service_role;
grant execute on function public.settle_orphan_charge(uuid, uuid, text, text)
  to service_role;
grant execute on function public.mark_orphan_resolved(uuid) to service_role;
grant execute on function public.delete_compensated_charge(uuid, uuid, text)
  to service_role;
