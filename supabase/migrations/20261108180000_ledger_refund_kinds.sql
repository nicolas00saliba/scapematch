-- Estorno do livro para quem já aplicou a main.
-- Não altera 20261105210000, que já está registrada em produção.
-- O crédito aplicado e o clawback ganham lançamentos próprios.

alter table public.ledger_entries
  drop constraint if exists ledger_entries_kind_check;

alter table public.ledger_entries
  add constraint ledger_entries_kind_check
  check (
    kind in (
      'house_net',
      'commission',
      'house_refund',
      'commission_refund',
      'venue_credit_applied',
      'venue_credit_refund',
      'venue_credit_clawback',
      'venue_credit_clawback_refund',
      'venue_credit_clawback_offset'
    )
  );

create or replace function private.ledger_reverse_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
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
    credit.payment_charge_id
  from public.ledger_entries as credit
  where credit.payment_charge_id = p_charge_id
    and credit.direction = 'credit'
    and credit.kind not in (
      'venue_credit_clawback_offset',
      'venue_credit_clawback_refund',
      'empty_slot_offset_undo'
    )
  on conflict (payment_charge_id, kind, direction) do nothing;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    debit.venue_id,
    debit.group_id,
    debit.user_id,
    debit.account,
    'credit',
    'venue_credit_clawback_refund',
    debit.amount_cents,
    debit.payment_charge_id
  from public.ledger_entries as debit
  where debit.payment_charge_id = p_charge_id
    and debit.direction = 'debit'
    and debit.kind = 'venue_credit_clawback'
  on conflict (payment_charge_id, kind, direction) do nothing;

  perform private.restore_applied_venue_credits(p_charge_id);
end;
$$;

revoke all on function private.ledger_reverse_charge(uuid)
  from public, anon, authenticated;
