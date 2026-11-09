#!/bin/bash
# main (já com o #84) → dados financeiros gravados → migrations do #85.
# Arquivo que a main já registrou não roda de novo: o CREATE TABLE quebra.
# 70bbdd1 nunca foi aplicado fora de teste e não é caminho suportado.
# Não fala com o Asaas e não publica função.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

if ! git cat-file -e origin/main^{commit} 2>/dev/null; then
  git fetch --no-tags origin main
fi

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

admin_psql -c "drop database if exists scapematch_rewards_upgrade with (force);" >/dev/null
admin_psql -c "create database scapematch_rewards_upgrade;" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/local_harness.sql" >/dev/null

while IFS= read -r path; do
  git show "origin/main:${path}" | psql_db scapematch_rewards_upgrade -f - >/dev/null
done < <(git ls-tree -r --name-only origin/main supabase/migrations | sort)

for path in supabase/migrations/20261108*.sql; do
  if git cat-file -e "origin/main:${path}" 2>/dev/null; then
    continue
  fi
  psql_db scapematch_rewards_upgrade -f "$root/$path" >/dev/null
done

psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/paid_cashback_84.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/reward_reversal.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/ledger_permutations.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/commit_84_offset.sql" >/dev/null

for path in supabase/migrations/20261109*.sql; do
  if git cat-file -e "origin/main:${path}" 2>/dev/null; then
    continue
  fi
  psql_db scapematch_rewards_upgrade -f "$root/$path" >/dev/null
done

psql_db scapematch_rewards_upgrade -v ON_ERROR_STOP=1 -c "
  do \$\$
  begin
    if (
      select amount_cents from public.ledger_entries
      where kind = 'venue_credit_clawback_offset'
        and payment_charge_id = 'cb500000-0000-4000-8000-000000000001'
    ) is distinct from 700 then
      raise exception 'o offset gravado no #84 sumiu na migration do #85';
    end if;
  end \$\$;
" >/dev/null

psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/rewards_regression.sql" >/dev/null
admin_psql -c "drop database if exists scapematch_rewards_upgrade with (force);" >/dev/null
echo "rewards upgrade ok"
