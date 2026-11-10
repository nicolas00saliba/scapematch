#!/bin/bash
# Schema publicado no merge do #84 (45039751) → dados financeiros gravados
# → migrations do #85 e as que este branch acrescenta depois.
# A main não serve de base: depois do #85, private.post_player_cashback já
# existe e o teste histórico do #84 falha. Arquivo da base não roda de novo.
# 70bbdd1 nunca foi aplicado fora de teste e não é caminho suportado.
# Não fala com o Asaas e não publica função.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

# Merge do #84, "Scape Points a partir da comissão da reserva".
base_sha=45039751ccc91e3827c238aad7c022e8c5679fb3
# Primeira migration do #85. O que vem antes é o schema do #84.
upgrade_from=supabase/migrations/20261109120000_rewards_rules.sql

if ! git cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
  git fetch --no-tags origin "$base_sha"
fi
base="$(git rev-parse "${base_sha}^{commit}")"

if ! git cat-file -e "${base}:supabase/migrations/20261108200000_split_fixed_value.sql" 2>/dev/null; then
  echo "a base ${base_sha} não é o schema do #84" >&2
  exit 1
fi
if git cat-file -e "${base}:${upgrade_from}" 2>/dev/null; then
  echo "a base ${base_sha} já contém a migration do #85" >&2
  exit 1
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
  git show "${base}:${path}" | psql_db scapematch_rewards_upgrade -f - >/dev/null
done < <(git ls-tree -r --name-only "$base" supabase/migrations | sort)

# Migrations anteriores ao #85 que a base ainda não tem.
while IFS= read -r path; do
  if git cat-file -e "${base}:${path}" 2>/dev/null; then
    continue
  fi
  if [[ "$path" < "$upgrade_from" ]]; then
    psql_db scapematch_rewards_upgrade -f "$root/$path" >/dev/null
  fi
done < <(printf '%s\n' supabase/migrations/*.sql | sort)

psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/paid_cashback_84.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/reward_reversal.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/ledger_permutations.sql" >/dev/null
psql_db scapematch_rewards_upgrade -f "$root/supabase/tests/commit_84_offset.sql" >/dev/null

# #85 e o que este branch acrescenta depois, na ordem do nome do arquivo.
while IFS= read -r path; do
  if git cat-file -e "${base}:${path}" 2>/dev/null; then
    continue
  fi
  if [[ "$path" < "$upgrade_from" ]]; then
    continue
  fi
  psql_db scapematch_rewards_upgrade -f "$root/$path" >/dev/null
done < <(printf '%s\n' supabase/migrations/*.sql | sort)

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
