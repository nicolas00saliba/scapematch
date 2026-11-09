#!/bin/bash
# 20261108190000 recusa linhas agregadas de recompensa. Produção não tem
# essas linhas; o teste prova que a migration não segue em silêncio.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

admin_psql() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "${DATABASE_URL%/*}/postgres" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d postgres -v ON_ERROR_STOP=1 "$@"
  fi
}

psql_db() {
  local db="$1"
  shift
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "${DATABASE_URL%/*}/${db}" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

admin_psql -c "drop database if exists scapematch_aggregated with (force);" >/dev/null
admin_psql -c "create database scapematch_aggregated;" >/dev/null
psql_db scapematch_aggregated -f "$root/supabase/tests/local_harness.sql" >/dev/null

for path in supabase/migrations/*.sql; do
  base="$(basename "$path")"
  if [[ "$base" > "20261108190000_ledger_components.sql" || "$base" == "20261108190000_ledger_components.sql" ]]; then
    continue
  fi
  psql_db scapematch_aggregated -f "$root/$path" >/dev/null
done

psql_db scapematch_aggregated <<'SQL' >/dev/null
insert into auth.users (id, email, raw_user_meta_data)
values (
  'a1100000-0000-4000-8000-000000000001',
  'agregado@example.com',
  '{"display_name":"Agregado"}'
);
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'a2100000-0000-4000-8000-000000000001',
  'a1100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Agregada', 'Centro', 'Rua Soma', '8', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '45997418000153', '4130000166', 'approved'
);
insert into public.ledger_entries (
  venue_id, account, direction, kind, amount_cents
) values (
  'a2100000-0000-4000-8000-000000000001',
  'house', 'credit', 'venue_credit_applied', 700
);
SQL

set +e
psql_db scapematch_aggregated -f "$root/supabase/migrations/20261108190000_ledger_components.sql" > /tmp/aggregated-guard.log 2>&1
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  echo "a migration aceitou lancamento agregado"
  exit 1
fi
if ! grep -q "lancamentos agregados de recompensa sem origem" /tmp/aggregated-guard.log; then
  echo "a mensagem da migration nao explica o aborto"
  cat /tmp/aggregated-guard.log
  exit 1
fi

admin_psql -c "drop database if exists scapematch_aggregated with (force);" >/dev/null
echo "aggregated reward guard ok"
