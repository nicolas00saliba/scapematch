#!/bin/bash
# Corrida entre desconectar e reservar. A sessão A desconecta a casa e segura
# a transação; a B tenta gravar uma cobrança com a conta que a casa tinha.
# A B espera o lock da casa e, depois do commit da A, é recusada (PB409).
# Nenhuma cobrança fica com a conta velha.
set -euo pipefail

db="${PGDATABASE:-scapematch_duplicates}"
venue="d6200001-0000-4000-8000-000000000001"
owner="d6100001-0000-4000-8000-000000000001"
wallet="ACCO_RACE0000-0000-4000-8000-0000000000AB"

psql_db() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

psql_db <<SQL
insert into auth.users (id, email, raw_user_meta_data)
values ('$owner', 'corrida-pagbank@example.com', '{"display_name":"Corrida"}');
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  '$venue', '$owner', 'curitiba', 'Casa Corrida', 'Centro', 'Rua da Corrida',
  '5', '80010055', -25.43, -49.27, 5000, 'cnpj', '45723174000200',
  '41900001155', 'approved'
);
select public.connect_venue_pagbank(
  '$venue', '$owner', '$wallet', 'acc', 'ref', now() + interval '1 hour'
);
alter table public.payment_charges
  enable always trigger charge_wallet_matches_venue;
SQL

a_log="$(mktemp)"
b_log="$(mktemp)"

psql_db >"$a_log" 2>&1 <<SQL &
begin;
select public.disconnect_venue_pagbank('$venue', '$owner', false);
select pg_sleep(3);
commit;
SQL
a_pid=$!
sleep 1

start_ms=$(date +%s%3N)
set +e
psql_db >"$b_log" 2>&1 <<SQL
set session_replication_role = replica;
insert into public.payment_charges (
  group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, commission_bps, wallet_id
) values (
  gen_random_uuid(), gen_random_uuid(), '$venue', 5000, 'PIX', 'creating',
  'corrida-conta-velha', 2500, '$wallet'
);
SQL
b_status=$?
set -e
end_ms=$(date +%s%3N)
wait "$a_pid"

psql_db -c "alter table public.payment_charges enable trigger charge_wallet_matches_venue;"

if [[ "$b_status" -eq 0 ]]; then
  echo "a reserva com a conta velha foi aceita"; cat "$b_log"; exit 1
fi
if ! grep -q "pagbank_account_changed" "$b_log"; then
  echo "a recusa não foi a esperada"; cat "$b_log"; exit 1
fi
if (( end_ms - start_ms < 1000 )); then
  echo "a reserva não esperou o lock da casa"; exit 1
fi
left="$(psql_db -Atc "select count(*) from public.payment_charges where venue_id = '$venue'")"
account="$(psql_db -Atc "select coalesce(pagbank_account_id, 'nenhuma') from public.venues where id = '$venue'")"
if [[ "$left" != "0" || "$account" != "nenhuma" ]]; then
  echo "estado final errado: cobranças=$left conta=$account"; exit 1
fi
rm -f "$a_log" "$b_log"
echo "pagbank disconnect race ok"
