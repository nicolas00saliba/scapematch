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

make_db scapematch_fresh
for path in "$root"/migrations/*.sql; do
  psql_db scapematch_fresh -f "$path" >/dev/null
done

psql_db scapematch_upgrade -c "
do \$\$
declare
  v_fn text;
begin
  select pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure) into v_fn;
  if v_fn not like '%post_player_cashback%' or v_fn not like '%referrer_tier_bonus%' then
    raise exception 'upgrade nao ligou cashback variavel nem nivel';
  end if;
  if pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)
    is distinct from pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)
  then
    null;
  end if;
end \$\$;
" >/dev/null

psql_db scapematch_upgrade -tA -c "select pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)" > /tmp/upgrade_post.sql
psql_db scapematch_fresh -tA -c "select pg_get_functiondef('private.post_referral_rewards(uuid)'::regprocedure)" > /tmp/fresh_post.sql
if ! cmp -s /tmp/upgrade_post.sql /tmp/fresh_post.sql; then
  echo "post_referral_rewards divergiu entre upgrade e banco novo" >&2
  exit 1
fi
for fn in \
  "private.reverse_referral_rewards(uuid)" \
  "private.ledger_reverse_charge(uuid)" \
  "private.referral_reward_gate(uuid,text,uuid,uuid,uuid,uuid)"
do
  psql_db scapematch_upgrade -tA -c "select pg_get_functiondef('${fn}'::regprocedure)" > /tmp/upgrade_fn.sql
  psql_db scapematch_fresh -tA -c "select pg_get_functiondef('${fn}'::regprocedure)" > /tmp/fresh_fn.sql
  if ! cmp -s /tmp/upgrade_fn.sql /tmp/fresh_fn.sql; then
    echo "$fn divergiu entre upgrade e banco novo" >&2
    exit 1
  fi
done

admin_psql -c "drop database if exists scapematch_upgrade with (force);" >/dev/null
admin_psql -c "drop database if exists scapematch_fresh with (force);" >/dev/null
echo "rewards upgrade ok"
