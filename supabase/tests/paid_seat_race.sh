#!/bin/bash
# Duas sessões pagam a última vaga. A que segura a linha do grupo
# faz a outra esperar. Quem chega depois não entra e vai para a fila.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"
lock_file="/tmp/scapematch-paid-seat-locked"
group_id="a6500001-0000-4000-8000-000000000001"
charge_id="a6700001-0000-4000-8000-000000000002"

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
values
  ('a6100001-0000-4000-8000-000000000001', 'trava-um@example.com', '{"display_name":"Trava Um"}'),
  ('a6100001-0000-4000-8000-000000000002', 'trava-dois@example.com', '{"display_name":"Trava Dois"}'),
  ('a6100001-0000-4000-8000-000000000003', 'trava-tres@example.com', '{"display_name":"Trava Tres"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'a6200001-0000-4000-8000-000000000001',
  'a6100001-0000-4000-8000-000000000001',
  'curitiba',
  'Casa Trava',
  'Centro',
  'Rua da Trava',
  '9',
  '80010020',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '88777666000144',
  '41988880002',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'a6300001-0000-4000-8000-000000000001',
  'a6200001-0000-4000-8000-000000000001',
  'Sala Trava',
  '',
  4,
  2,
  60,
  'medium',
  9000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'a6400001-0000-4000-8000-000000000001',
  'a6300001-0000-4000-8000-000000000001',
  '2027-10-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by, closes_at
) values (
  'a6500001-0000-4000-8000-000000000001',
  'curitiba',
  'a6200001-0000-4000-8000-000000000001',
  'a6300001-0000-4000-8000-000000000001',
  'a6400001-0000-4000-8000-000000000001',
  '2027-10-01 18:00:00+00',
  2,
  2,
  9000,
  'a6100001-0000-4000-8000-000000000001',
  '2027-09-30 18:00:00+00'
);

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  (
    'a6600001-0000-4000-8000-000000000001',
    'a6500001-0000-4000-8000-000000000001',
    'a6100001-0000-4000-8000-000000000001',
    'Trava Um',
    true,
    'paid'
  ),
  (
    'a6600001-0000-4000-8000-000000000002',
    'a6500001-0000-4000-8000-000000000001',
    'a6100001-0000-4000-8000-000000000002',
    'Trava Dois',
    false,
    'pending'
  ),
  (
    'a6600001-0000-4000-8000-000000000003',
    'a6500001-0000-4000-8000-000000000001',
    'a6100001-0000-4000-8000-000000000003',
    'Trava Tres',
    false,
    'pending'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider, provider_ref, idempotency_key, wallet_id, commission_bps,
  paid_at, attempt_id
) values (
  'a6700001-0000-4000-8000-000000000002',
  'a6500001-0000-4000-8000-000000000001',
  'a6100001-0000-4000-8000-000000000002',
  'a6200001-0000-4000-8000-000000000001',
  9000, 'PIX', 'paid', 'pagbank', 'CHAR_TRAVA',
  'idem-trava', 'wal_trava', 2500, now(),
  'a6710001-0000-4000-8000-000000000002'
),
(
  'a6700001-0000-4000-8000-000000000003',
  'a6500001-0000-4000-8000-000000000001',
  'a6100001-0000-4000-8000-000000000003',
  'a6200001-0000-4000-8000-000000000001',
  9000, 'CREDIT_CARD', 'authorized', 'pagbank', 'CHAR_TRAVA_3',
  'idem-trava-3', 'wal_trava', 2500, now(),
  'a6710001-0000-4000-8000-000000000003'
);
SQL

psql_db <<SQL &
begin;
select id from public.groups where id = '${group_id}' for update;
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
  echo "a sessao que segura o grupo nao chegou a trava"
  kill "$locker_pid" 2>/dev/null || true
  exit 1
fi

set +e
psql_db -c "set lock_timeout = '400ms'; select private.sync_charge_member(c.*) from public.payment_charges c where c.id = '${charge_id}';"
blocked=$?
set -e
if [[ "$blocked" -eq 0 ]]; then
  echo "o pagamento entrou enquanto o grupo estava travado"
  kill "$locker_pid" 2>/dev/null || true
  wait "$locker_pid" 2>/dev/null || true
  exit 1
fi

wait "$locker_pid" || true
psql_db -c "select private.sync_charge_member(c.*) from public.payment_charges c where c.id = '${charge_id}';"
psql_db -c "select private.sync_charge_member(c.*) from public.payment_charges c where c.id = 'a6700001-0000-4000-8000-000000000003';"
psql_db <<SQL
do \$\$
begin
  if (
    select attendance from public.group_members
    where id = 'a6600001-0000-4000-8000-000000000002'
  ) <> 'confirmed' or private.group_filled_spots(
    '${group_id}'
  ) <> 2 or exists (
    select 1 from public.member_refund_queue
    where charge_id = '${charge_id}'
  ) then
    raise exception 'depois da trava a vaga livre nao ficou com quem pagou';
  end if;
  if (
    select attendance from public.group_members
    where id = 'a6600001-0000-4000-8000-000000000003'
  ) <> 'cancelled' or not exists (
    select 1 from public.member_refund_queue
    where charge_id = 'a6700001-0000-4000-8000-000000000003'
      and status = 'queued'
      and action = 'void'
  ) then
    raise exception 'o segundo pagamento da ultima vaga nao foi para a fila';
  end if;
end \$\$;
SQL

if [[ -n "${DATABASE_URL:-}" ]]; then
  rm -f "$lock_file"
else
  sudo rm -f "$lock_file"
fi
echo "paid seat race ok"
