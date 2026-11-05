-- Estorno duplicado: cancel-house-group e o webhook PAYMENT_REFUNDED
-- chamam reverseLedger ao mesmo tempo. O índice único de crédito
-- (payment_charge_id, kind) WHERE direction = 'credit' não cobre o débito.
--
-- Kinds permitidos: house_net e commission só entram como credit;
-- house_refund e commission_refund só entram como debit. Uma linha por
-- (payment_charge_id, kind, direction) vale para todos. Índice parcial só
-- nos estornos não serve de alvo do ON CONFLICT do PostgREST, que não
-- manda o predicado. payment_charge_id nulo não colide com outro nulo.
--
-- Não aplicada no projeto remoto.

with ranked as (
  select
    id,
    row_number() over (
      partition by payment_charge_id, kind, direction
      order by created_at asc, id asc
    ) as rn
  from public.ledger_entries
  where payment_charge_id is not null
)
delete from public.ledger_entries as entries
using ranked
where entries.id = ranked.id
  and ranked.rn > 1;

create unique index if not exists ledger_entries_charge_kind_direction_uidx
  on public.ledger_entries (payment_charge_id, kind, direction);
