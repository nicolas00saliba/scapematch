#!/bin/bash
# Aplica as migrations num Postgres local e roda o teste de duplicata.
# Não fala com o projeto remoto.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"

run() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

if [[ -z "${DATABASE_URL:-}" ]]; then
  sudo -u postgres psql -d postgres -v ON_ERROR_STOP=1 \
    -c "drop database if exists ${db} with (force);"
  sudo -u postgres createdb "$db"
fi

run -f "$root/tests/local_harness.sql"
for migration in "$root"/migrations/*.sql; do
  echo "== $migration"
  run -f "$migration"
done
run -f "$root/tests/venue_duplicates.sql"
echo "duplicatas ok"
run -f "$root/tests/groups_rls.sql"
echo "groups rls ok"
run -f "$root/tests/private_functions.sql"
echo "private functions ok"
run -f "$root/tests/saved_cards.sql"
echo "saved cards ok"
run -f "$root/tests/card_tokenize_limit.sql"
echo "card tokenize limit ok"
run -f "$root/tests/card_token_crypto.sql"
echo "card token crypto ok"
run -f "$root/tests/wallet_commission.sql"
echo "wallet commission ok"
run -f "$root/tests/player_cpf.sql"
echo "player cpf ok"
run -f "$root/tests/private_usage.sql"
echo "private usage ok"
run -f "$root/tests/payment_transition.sql"
echo "payment transition ok"
run -f "$root/tests/payment_followups.sql"
echo "payment followups ok"
run -f "$root/tests/scape_points.sql"
echo "scape points ok"
run -f "$root/tests/reward_reversal.sql"
echo "reward reversal ok"
run -f "$root/tests/unpaid_release.sql"
echo "unpaid release ok"
bash "$root/tests/aggregated_reward_guard.sh"
run -f "$root/tests/ledger_permutations.sql"
echo "ledger permutations ok"
bash "$root/tests/upgrade_from_main.sh"
bash "$root/tests/rewards_concurrency.sh"
bash "$root/tests/payment_sessions.sh"
bash "$root/tests/rewards_regression.sh"
bash "$root/tests/rewards_upgrade.sh"
bash "$root/tests/clawback_race.sh"
run -f "$root/tests/empty_slot_permutations.sql"
echo "empty slot permutations ok"
