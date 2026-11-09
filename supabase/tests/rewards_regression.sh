#!/bin/bash
# Revisão periódica dos dois pacotes de recompensa.
# Só Postgres local. Não cobra no Asaas e desfaz os dados no final.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"

if [[ -n "${DATABASE_URL:-}" ]]; then
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$root/tests/rewards_regression.sql"
else
  sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/tests/rewards_regression.sql"
fi

echo "rewards regression ok"
