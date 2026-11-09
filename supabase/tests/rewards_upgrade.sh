#!/bin/bash
# Prova que um banco que já aplicou o #84 em 70bbdd1 fica igual a um banco novo
# depois das migrations atuais do #85. Não fala com o Asaas.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
old_ref="70bbdd183dc2ded5e0f75faee8d0de5a0c62f0a5"

if ! git cat-file -e "${old_ref}^{commit}" 2>/dev/null; then
  git fetch --no-tags origin "$old_ref"
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

make_db() {
  local db="$1"
  admin_psql -c "drop database if exists ${db} with (force);" >/dev/null
  admin_psql -c "create database ${db};" >/dev/null
  psql_db "$db" -f "$root/tests/local_harness.sql" >/dev/null
}

make_db scapematch_upgrade
mapfile -t old_migrations < <(git ls-tree -r --name-only "$old_ref" supabase/migrations | sort)
if [[ ${#old_migrations[@]} -eq 0 ]]; then
  echo "o commit ${old_ref} nao tem migrations" >&2
  exit 1
fi
for path in "${old_migrations[@]}"; do
  git show "${old_ref}:${path}" | psql_db scapematch_upgrade -f - >/dev/null
done
psql_db scapematch_upgrade -f "$root/migrations/20261109120000_rewards_rules.sql" >/dev/null
psql_db scapematch_upgrade -f "$root/migrations/20261109130000_reward_reversal.sql" >/dev/null

psql_db scapematch_upgrade -v ON_ERROR_STOP=1 -c "
do \$\$
begin
  if to_regprocedure('private.apply_venue_clawback(uuid,uuid,integer)') is null
    or to_regprocedure('private.restore_applied_venue_credits(uuid)') is null
    or to_regprocedure('private.reopen_empty_slot_on_refund(uuid)') is null
  then
    raise exception 'upgrade do #84 antigo nao criou clawback, restore ou reopen';
  end if;
  if pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)
    not like '%post_player_cashback%'
    or pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)
    not like '%referrer_tier_bonus%'
  then
    raise exception 'upgrade nao ligou cashback variavel nem nivel';
  end if;
end \$\$;
"
psql_db scapematch_upgrade -f "$root/tests/reward_reversal.sql" >/dev/null
psql_db scapematch_upgrade -f "$root/tests/rewards_regression.sql" >/dev/null

admin_psql -c "drop database if exists scapematch_upgrade with (force);" >/dev/null
echo "rewards upgrade ok"
