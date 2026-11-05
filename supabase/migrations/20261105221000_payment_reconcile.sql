-- Trabalho da reconciliação. A Edge Function consulta o Asaas. O
-- agendamento fica na migração seguinte, para o CI sem pg_cron passar.

alter table private.orphan_payments
  add column if not exists resolved_at timestamptz;

create or replace function private.list_payment_reconciliation()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'creating', coalesce((
      select jsonb_agg(jsonb_build_object(
        'charge_id', c.id,
        'attempt_id', c.attempt_id,
        'billing_type', c.billing_type,
        'group_id', c.group_id,
        'user_id', c.user_id,
        'external_reference', case
          when c.billing_type = 'PIX'
            then 'pix:' || c.group_id::text || ':' || c.user_id::text
          else c.idempotency_key
        end
      ))
      from public.payment_charges c
      where c.status = 'creating'
        and c.provider_ref is null
        and (
          c.reserved_at is null
          or c.reserved_at < pg_catalog.now() - interval '2 minutes'
        )
    ), '[]'::jsonb),
    'orphans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'provider_ref', o.provider_ref,
        'charge_id', o.charge_id,
        'attempt_id', o.attempt_id,
        'billing_type', o.billing_type,
        'reason', o.reason,
        'external_reference', case
          when c.id is null then null
          when coalesce(o.billing_type, c.billing_type) = 'PIX'
            then 'pix:' || c.group_id::text || ':' || c.user_id::text
          else c.idempotency_key
        end
      ))
      from private.orphan_payments o
      left join public.payment_charges c on c.id = o.charge_id
      where o.resolved_at is null
    ), '[]'::jsonb)
  );
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

revoke all on function private.list_payment_reconciliation()
  from public, anon, authenticated;
revoke all on function private.mark_orphan_resolved(uuid)
  from public, anon, authenticated;
revoke all on function private.delete_compensated_charge(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function private.list_payment_reconciliation() to service_role;
grant execute on function private.mark_orphan_resolved(uuid) to service_role;
grant execute on function private.delete_compensated_charge(uuid, uuid, text)
  to service_role;

create or replace function public.list_payment_reconciliation()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.list_payment_reconciliation();
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

revoke all on function public.list_payment_reconciliation()
  from public, anon, authenticated;
revoke all on function public.mark_orphan_resolved(uuid)
  from public, anon, authenticated;
revoke all on function public.delete_compensated_charge(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.list_payment_reconciliation() to service_role;
grant execute on function public.mark_orphan_resolved(uuid) to service_role;
grant execute on function public.delete_compensated_charge(uuid, uuid, text)
  to service_role;
