#!/bin/bash
# Aplica a main e só as migrations novas deste branch, depois executa o estorno.
# Não usa o socket local quando DATABASE_URL existe. Não cobra no Asaas.
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

admin_psql -c "drop database if exists scapematch_from_main with (force);" >/dev/null
admin_psql -c "create database scapematch_from_main;" >/dev/null
psql_db scapematch_from_main -f "$root/supabase/tests/local_harness.sql" >/dev/null

while IFS= read -r path; do
  git show "origin/main:${path}" | psql_db scapematch_from_main -f - >/dev/null
done < <(git ls-tree -r --name-only origin/main supabase/migrations | sort)

while IFS= read -r path; do
  psql_db scapematch_from_main -f "$root/$path" >/dev/null
done < <(comm -13 \
  <(git ls-tree -r --name-only origin/main supabase/migrations | sort) \
  <(printf '%s\n' supabase/migrations/*.sql | sed "s|^$root/||" | sort))

psql_db scapematch_from_main -f "$root/supabase/tests/reward_reversal.sql" >/dev/null
admin_psql -c "drop database if exists scapematch_from_main with (force);" >/dev/null
echo "upgrade from main ok"
