#!/bin/bash
# Duas sessões disputam o mesmo débito de horário vazio.
# A que chega primeiro segura a linha. A outra espera e não marca o débito.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"
lock_file="/tmp/scapematch-debit-locked"
debit_id="cf100000-0000-4000-8000-000000000001"
target_id="cf200000-0000-4000-8000-000000000002"

psql_db() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

if [[ -n "${DATABASE_URL:-}" ]]; then
  rm -f "$lock_file"
else
  sudo rm -f "$lock_file"
fi

psql_db <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values (
  'cf300000-0000-4000-8000-000000000001',
  'concorrencia@example.com',
  '{"display_name":"Concorrencia"}'
);
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'cf400000-0000-4000-8000-000000000001',
  'cf300000-0000-4000-8000-000000000001',
  'curitiba',
  'Casa Concorrencia',
  'Centro',
  'Rua do Lock',
  '1',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '11444777000161',
  '4130000099',
  'approved'
);
insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'cf500000-0000-4000-8000-000000000001',
  'cf400000-0000-4000-8000-000000000001',
  'Sala Lock',
  '',
  4,
  2,
  60,
  'medium',
  10000
);
insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    'cf600000-0000-4000-8000-000000000001',
    'curitiba',
    'cf400000-0000-4000-8000-000000000001',
    'cf500000-0000-4000-8000-000000000001',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-20 18:00:00+00',
    4, 2, 10000,
    'cf300000-0000-4000-8000-000000000001'
  ),
  (
    'cf600000-0000-4000-8000-000000000002',
    'curitiba',
    'cf400000-0000-4000-8000-000000000001',
    'cf500000-0000-4000-8000-000000000001',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-21 18:00:00+00',
    4, 2, 10000,
    'cf300000-0000-4000-8000-000000000001'
  );
insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps
) values
  (
    'cf200000-0000-4000-8000-000000000001',
    'cf600000-0000-4000-8000-000000000001',
    'cf300000-0000-4000-8000-000000000001',
    'cf400000-0000-4000-8000-000000000001',
    10000, 'PIX', 'paid',
    'idem-lock-origem', 'wal_house', 2500
  ),
  (
    'cf200000-0000-4000-8000-000000000002',
    'cf600000-0000-4000-8000-000000000002',
    'cf300000-0000-4000-8000-000000000001',
    'cf400000-0000-4000-8000-000000000001',
    10000, 'PIX', 'creating',
    'idem-lock-alvo', 'wal_house', 2500
  );
insert into public.venue_cashback_debits (
  id, venue_id, source_charge_id, amount_cents
) values (
  'cf100000-0000-4000-8000-000000000001',
  'cf400000-0000-4000-8000-000000000001',
  'cf200000-0000-4000-8000-000000000001',
  100
);
SQL

psql_db <<SQL &
begin;
select id from public.venue_cashback_debits where id = '${debit_id}' for update;
\\! touch ${lock_file}
select pg_catalog.pg_sleep(4);
rollback;
SQL
locker_pid=$!

ready=0
for _ in $(seq 1 50); do
  if [[ -f "$lock_file" ]]; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" -ne 1 ]]; then
  echo "a sessao que segura o debito nao chegou a trava"
  kill "$locker_pid" 2>/dev/null || true
  exit 1
fi

set +e
psql_db -c "set lock_timeout = '400ms'; select private.apply_share_adjustments('${target_id}'::uuid);"
blocked=$?
set -e
if [[ "$blocked" -eq 0 ]]; then
  echo "a segunda sessao aplicou o debito enquanto a linha estava travada"
  kill "$locker_pid" 2>/dev/null || true
  wait "$locker_pid" 2>/dev/null || true
  exit 1
fi

wait "$locker_pid" || true
psql_db -c "select private.apply_share_adjustments('${target_id}'::uuid);"
psql_db <<SQL
do \$\$
begin
  if (
    select applied_cents from public.venue_cashback_debits where id = '${debit_id}'
  ) <> 100 or (
    select empty_slot_offset_cents from public.payment_charges where id = '${target_id}'
  ) <> 100 then
    raise exception 'depois do lock o debito nao ficou numa cobranca so';
  end if;
  perform private.apply_share_adjustments('${target_id}'::uuid);
  if (
    select applied_cents from public.venue_cashback_debits where id = '${debit_id}'
  ) <> 100 then
    raise exception 'a retentativa cobrou o debito duas vezes';
  end if;
end \$\$;
SQL

if [[ -n "${DATABASE_URL:-}" ]]; then
  rm -f "$lock_file"
else
  sudo rm -f "$lock_file"
fi
echo "rewards concurrency ok"
