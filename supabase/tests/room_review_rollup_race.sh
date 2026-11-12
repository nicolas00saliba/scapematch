#!/bin/bash
# Duas avaliações da mesma sala ao mesmo tempo.
# A trava segura a segunda até a primeira gravar o agregado.
# Sem ela, a que commita por último apaga a nota da outra.
set -euo pipefail

db="${PGDATABASE:-scapematch_duplicates}"
ready="/tmp/scapematch-review-rollup-ready"
venue="c0f20000-0000-4000-8000-000000000001"
room="c0f30000-0000-4000-8000-000000000001"
group_id="c0f40000-0000-4000-8000-000000000001"
owner="c0f10000-0000-4000-8000-000000000003"
player_a="c0f10000-0000-4000-8000-000000000001"
player_b="c0f10000-0000-4000-8000-000000000002"

psql_db() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

cleanup() {
  psql_db <<SQL
update public.review_settings set enabled = false where id = 1;
delete from public.room_reviews where venue_id = '${venue}';
delete from public.group_members where group_id = '${group_id}';
delete from public.groups where id = '${group_id}';
delete from public.rooms where id = '${room}';
delete from public.venues where id = '${venue}';
delete from auth.users where id in ('${owner}', '${player_a}', '${player_b}');
SQL
  if [[ -n "${DATABASE_URL:-}" ]]; then
    rm -f "$ready"
  else
    sudo rm -f "$ready"
  fi
}

trap cleanup EXIT

if [[ -n "${DATABASE_URL:-}" ]]; then
  rm -f "$ready"
else
  sudo rm -f "$ready"
fi

psql_db <<SQL
insert into auth.users (id, email, raw_user_meta_data) values
  ('${owner}', 'rollup-owner@example.com', '{"display_name":"Dona Rollup"}'),
  ('${player_a}', 'rollup-a@example.com', '{"display_name":"Ana Rollup"}'),
  ('${player_b}', 'rollup-b@example.com', '{"display_name":"Bia Rollup"}');
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  '${venue}',
  '${owner}',
  'curitiba',
  'Casa da Trava',
  'Centro',
  'Rua da Trava',
  '44',
  '80020000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '90908877000142',
  '41970001122',
  'approved'
);
insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  '${room}', '${venue}', 'Sala da Trava', 4, 2, 60, 'medium', 10000
);
insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values (
  '${group_id}', 'curitiba', '${venue}', '${room}',
  pg_catalog.now() - interval '2 days',
  4, 2, 10000, '${owner}'
);
insert into public.group_members (group_id, user_id, display_name, payment_status)
values
  ('${group_id}', '${player_a}', 'Ana Rollup', 'paid'),
  ('${group_id}', '${player_b}', 'Bia Rollup', 'paid');
update public.review_settings set enabled = true where id = 1;
SQL

psql_db <<SQL &
begin;
select set_config('request.jwt.claim.sub', '${player_a}', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
select public.submit_room_review(
  '${group_id}'::uuid, 5, 5, 5, 5, 5, 5, ''
);
\\! touch ${ready}
select pg_catalog.pg_sleep(4);
commit;
SQL
holder_pid=$!

arrived=0
for _ in $(seq 1 50); do
  if [[ -f "$ready" ]]; then
    arrived=1
    break
  fi
  sleep 0.1
done
if [[ "$arrived" -ne 1 ]]; then
  echo "a primeira avaliação não segurou a transação"
  kill "$holder_pid" 2>/dev/null || true
  cleanup
  exit 1
fi

psql_db <<SQL
begin;
select set_config('request.jwt.claim.sub', '${player_b}', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
select public.submit_room_review(
  '${group_id}'::uuid, 1, 1, 1, 1, 1, 1, ''
);
commit;
SQL

wait "$holder_pid" || true

psql_db <<SQL
do \$\$
declare
  v_count integer;
begin
  select review_count into v_count
  from public.room_rating_rollups
  where room_id = '${room}';
  if v_count is distinct from 2 then
    raise exception 'agregado concorrente ficou com % notas', v_count;
  end if;
end \$\$;
SQL

cleanup
echo "room review rollup race ok"
