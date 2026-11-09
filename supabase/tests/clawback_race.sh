#!/bin/bash
# Duas sessões: uma estorna o consumidor enquanto a outra cobra o clawback.
# A trava da casa serializa. O offset cobre só o que já estava cobrado.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"
lock_file="/tmp/scapematch-clawback-locked"
venue="cd200000-0000-4000-8000-000000000001"
consumer="cd500000-0000-4000-8000-000000000003"
other="cd500000-0000-4000-8000-000000000004"

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
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email, raw_user_meta_data)
values (
  'cd100000-0000-4000-8000-000000000001',
  'corrida-clawback@example.com',
  '{"display_name":"Corrida"}'
);
insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'cd200000-0000-4000-8000-000000000001',
  'cd100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Corrida', 'Centro', 'Rua da Trava', '3', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '00000000000191', '4130000188', 'approved'
);
insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'cd300000-0000-4000-8000-000000000001',
  'cd200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'cd310000-0000-4000-8000-000000000001',
  'cd300000-0000-4000-8000-000000000001',
  '2027-06-01 18:00:00+00', 'partner_grid'
);
insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  ('cd400000-0000-4000-8000-000000000001', 'curitiba', 'cd200000-0000-4000-8000-000000000001', 'cd300000-0000-4000-8000-000000000001', 'cd310000-0000-4000-8000-000000000001', '2027-06-01 18:00:00+00', 4, 2, 10000, 'cd100000-0000-4000-8000-000000000001'),
  ('cd400000-0000-4000-8000-000000000002', 'curitiba', 'cd200000-0000-4000-8000-000000000001', 'cd300000-0000-4000-8000-000000000001', 'cd310000-0000-4000-8000-000000000001', '2027-06-02 18:00:00+00', 4, 2, 10000, 'cd100000-0000-4000-8000-000000000001'),
  ('cd400000-0000-4000-8000-000000000003', 'curitiba', 'cd200000-0000-4000-8000-000000000001', 'cd300000-0000-4000-8000-000000000001', 'cd310000-0000-4000-8000-000000000001', '2027-06-03 18:00:00+00', 4, 2, 10000, 'cd100000-0000-4000-8000-000000000001'),
  ('cd400000-0000-4000-8000-000000000004', 'curitiba', 'cd200000-0000-4000-8000-000000000001', 'cd300000-0000-4000-8000-000000000001', 'cd310000-0000-4000-8000-000000000001', '2027-06-04 18:00:00+00', 4, 2, 10000, 'cd100000-0000-4000-8000-000000000001'),
  ('cd400000-0000-4000-8000-000000000005', 'curitiba', 'cd200000-0000-4000-8000-000000000001', 'cd300000-0000-4000-8000-000000000001', 'cd310000-0000-4000-8000-000000000001', '2027-06-05 18:00:00+00', 4, 2, 10000, 'cd100000-0000-4000-8000-000000000001');
insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps, paid_at
) values
  ('cd500000-0000-4000-8000-000000000001', 'cd400000-0000-4000-8000-000000000001', 'cd100000-0000-4000-8000-000000000001', 'cd200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-race-o1', 'wal', 2500, now()),
  ('cd500000-0000-4000-8000-000000000002', 'cd400000-0000-4000-8000-000000000002', 'cd100000-0000-4000-8000-000000000001', 'cd200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-race-o2', 'wal', 2500, now()),
  ('cd500000-0000-4000-8000-000000000003', 'cd400000-0000-4000-8000-000000000003', 'cd100000-0000-4000-8000-000000000001', 'cd200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-race-u', 'wal', 2500, now()),
  ('cd500000-0000-4000-8000-000000000004', 'cd400000-0000-4000-8000-000000000004', 'cd100000-0000-4000-8000-000000000001', 'cd200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-race-c1', 'wal', 2500, now()),
  ('cd500000-0000-4000-8000-000000000005', 'cd400000-0000-4000-8000-000000000005', 'cd100000-0000-4000-8000-000000000001', 'cd200000-0000-4000-8000-000000000001', 10000, 'PIX', 'paid', 'idem-race-c2', 'wal', 2500, now());
insert into public.venue_referral_entries (
  venue_id, kind, amount_cents, program, settlement, source_charge_id,
  idempotency_key, available_at, applied_cents
) values
  ('cd200000-0000-4000-8000-000000000001', 'accrual', 200, 'b2c', 'released', 'cd500000-0000-4000-8000-000000000001', 'idem-race-cr-200', now(), 0),
  ('cd200000-0000-4000-8000-000000000001', 'accrual', 150, 'b2c', 'released', 'cd500000-0000-4000-8000-000000000002', 'idem-race-cr-150', now() + interval '1 second', 0);
select private.apply_venue_credit(
  'cd500000-0000-4000-8000-000000000003'::uuid,
  'cd200000-0000-4000-8000-000000000001'::uuid,
  10000
);
select private.reverse_referral_rewards('cd500000-0000-4000-8000-000000000001'::uuid);
select private.reverse_referral_rewards('cd500000-0000-4000-8000-000000000002'::uuid);
select private.apply_venue_clawback(
  'cd500000-0000-4000-8000-000000000004'::uuid,
  'cd200000-0000-4000-8000-000000000001'::uuid,
  200
);
select private.ledger_credit_charge('cd500000-0000-4000-8000-000000000003'::uuid);
select private.ledger_credit_charge('cd500000-0000-4000-8000-000000000004'::uuid);
SQL

psql_db <<SQL &
begin;
select id from public.venues where id = '${venue}' for update;
\\! touch ${lock_file}
select pg_catalog.pg_sleep(3);
select private.ledger_reverse_charge('${consumer}'::uuid);
commit;
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
  echo "a sessao do estorno nao travou a casa"
  kill "$locker_pid" 2>/dev/null || true
  exit 1
fi

psql_db -c "select private.apply_venue_clawback('${other}'::uuid, '${venue}'::uuid, 100000);"
wait "$locker_pid"

psql_db <<SQL
do \$\$
declare
  v_offset integer;
  v_open integer;
  v_house integer;
  v_neutral_without_offset integer;
begin
  select coalesce(sum(amount_cents), 0) into v_offset
  from public.ledger_entries
  where payment_charge_id = '${consumer}'
    and kind = 'venue_credit_clawback_offset';
  select coalesce(sum(amount_cents - applied_cents), 0) into v_open
  from public.venue_credit_clawbacks
  where venue_id = '${venue}'
    and voided_at is null
    and neutralized_at is null;
  select coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)
  into v_house
  from public.ledger_entries
  where venue_id = '${venue}'
    and account = 'house'
    and kind like 'venue_credit%';
  select count(*) into v_neutral_without_offset
  from public.venue_credit_clawbacks c
  where c.venue_id = '${venue}'
    and c.neutralized_at is not null
    and not exists (
      select 1 from public.ledger_entries l
      where l.kind = 'venue_credit_clawback_offset'
        and l.component_key = c.id::text
        and l.amount_cents = c.applied_cents
    );
  if v_offset <> 200 or v_open <> 0 or v_house <> 0
    or v_neutral_without_offset <> 0
  then
    raise exception
      'corrida do clawback offset % aberto % casa % sem offset %',
      v_offset, v_open, v_house, v_neutral_without_offset;
  end if;
end \$\$;
SQL

echo "clawback race ok"
