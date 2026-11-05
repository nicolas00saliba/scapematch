#!/bin/bash
# Duas sessões disputam a mesma reserva vencida. Só uma leva o attempt_id.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
db="${PGDATABASE:-scapematch_duplicates}"

psqlq() {
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tA "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 -tA "$@"
  fi
}

psqlq -f - <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'dd111111-1111-4111-8111-111111111111',
    'sessao-a@example.com',
    '{"display_name":"Sessão A"}'
  ),
  (
    'dd121111-1111-4111-8111-111111111111',
    'sessao-b@example.com',
    '{"display_name":"Sessão B"}'
  );

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'dd211111-1111-4111-8111-111111111111',
  'dd111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa Sessão',
  'Centro',
  'Rua das Sessões',
  '30',
  '80010030',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '44555666000181',
  '41988880031',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'dd311111-1111-4111-8111-111111111111',
  'dd211111-1111-4111-8111-111111111111',
  'Sala Sessão',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'dd411111-1111-4111-8111-111111111111',
  'dd311111-1111-4111-8111-111111111111',
  '2027-10-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'dd511111-1111-4111-8111-111111111111',
  'curitiba',
  'dd211111-1111-4111-8111-111111111111',
  'dd311111-1111-4111-8111-111111111111',
  'dd411111-1111-4111-8111-111111111111',
  '2027-10-01 18:00:00+00',
  4,
  2,
  10000,
  'dd111111-1111-4111-8111-111111111111'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, reserved_at, attempt_id
) values (
  'dd611111-1111-4111-8111-111111111111',
  'dd511111-1111-4111-8111-111111111111',
  'dd111111-1111-4111-8111-111111111111',
  'dd211111-1111-4111-8111-111111111111',
  10000,
  'PIX',
  'creating',
  null,
  'idem-sessao-claim',
  1000,
  now() - interval '5 minutes',
  'dd711111-1111-4111-8111-111111111111'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, reserved_at, attempt_id
) values (
  'dd811111-1111-4111-8111-111111111111',
  'dd511111-1111-4111-8111-111111111111',
  'dd121111-1111-4111-8111-111111111111',
  'dd211111-1111-4111-8111-111111111111',
  10000,
  'PIX',
  'creating',
  null,
  'idem-sessao-attach',
  1000,
  now(),
  'dd911111-1111-4111-8111-111111111111'
);
SQL

tmpdir="$(mktemp -d)"
psqlq -c "select coalesce(private.claim_expired_pix_reservation('dd611111-1111-4111-8111-111111111111')::text, '')" > "$tmpdir/a" &
psqlq -c "select coalesce(private.claim_expired_pix_reservation('dd611111-1111-4111-8111-111111111111')::text, '')" > "$tmpdir/b" &
wait

wins=0
[[ -n "$(cat "$tmpdir/a")" ]] && wins=$((wins + 1))
[[ -n "$(cat "$tmpdir/b")" ]] && wins=$((wins + 1))
if [[ "$wins" -ne 1 ]]; then
  echo "claim paralelo devolveu ${wins} vencedores" >&2
  echo "a=$(cat "$tmpdir/a") b=$(cat "$tmpdir/b")" >&2
  exit 1
fi

psqlq -c "begin; select id from public.payment_charges where id = 'dd811111-1111-4111-8111-111111111111' for update; select pg_sleep(2); update public.payment_charges set attempt_id = 'dda11111-1111-4111-8111-111111111111' where id = 'dd811111-1111-4111-8111-111111111111'; commit;" &
sleep 0.4
attached="$(psqlq -c "select coalesce(private.attach_pix_provider('dd811111-1111-4111-8111-111111111111', 'pay_sessao', 'dd911111-1111-4111-8111-111111111111')::text, '')")"
wait
provider="$(psqlq -c "select coalesce(provider_ref, '') from public.payment_charges where id = 'dd811111-1111-4111-8111-111111111111'")"
attempt="$(psqlq -c "select attempt_id::text from public.payment_charges where id = 'dd811111-1111-4111-8111-111111111111'")"
if [[ -n "$attached" || -n "$provider" || "$attempt" != "dda11111-1111-4111-8111-111111111111" ]]; then
  echo "attach de outra sessão gravou provider=${provider} retorno=${attached} attempt=${attempt}" >&2
  exit 1
fi

psqlq -f - <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values (
  'ee111111-1111-4111-8111-111111111111',
  'sessao-reconcile@example.com',
  '{"display_name":"Reconcile"}'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, reserved_at, attempt_id
) values (
  'ee611111-1111-4111-8111-111111111111',
  'dd511111-1111-4111-8111-111111111111',
  'ee111111-1111-4111-8111-111111111111',
  'dd211111-1111-4111-8111-111111111111',
  10000,
  'PIX',
  'creating',
  null,
  'idem-sessao-reconcile',
  1000,
  now() - interval '5 minutes',
  'ee711111-1111-4111-8111-111111111111'
);

select private.record_orphan_payment(
  'pay_ee_orfao',
  null,
  'ee711111-1111-4111-8111-111111111111',
  'PIX',
  'refund_failed'
);
SQL

psqlq -c "begin; select public.claim_payment_reconciliation(); select pg_sleep(2); commit;" > "$tmpdir/reconciler_a" &
sleep 0.5
psqlq -c "select public.claim_payment_reconciliation();" > "$tmpdir/reconciler_b" &
psqlq -c "select coalesce(public.claim_expired_pix_reservation('ee611111-1111-4111-8111-111111111111')::text, '')" > "$tmpdir/resume" &
wait

if [[ "$(grep -c 'ee611111-1111-4111-8111-111111111111' "$tmpdir/reconciler_a" "$tmpdir/reconciler_b" | awk -F: '{s+=$2} END {print s}')" -ne 1 ]]; then
  echo "dois reconciliadores não cercaram a cobrança uma vez" >&2
  echo "a=$(cat "$tmpdir/reconciler_a")" >&2
  echo "b=$(cat "$tmpdir/reconciler_b")" >&2
  exit 1
fi
if [[ "$(grep -c 'pay_ee_orfao' "$tmpdir/reconciler_a" "$tmpdir/reconciler_b" | awk -F: '{s+=$2} END {print s}')" -ne 1 ]]; then
  echo "dois reconciliadores não cercaram o órfão uma vez" >&2
  echo "a=$(cat "$tmpdir/reconciler_a")" >&2
  echo "b=$(cat "$tmpdir/reconciler_b")" >&2
  exit 1
fi
if [[ -n "$(cat "$tmpdir/resume")" ]]; then
  echo "retomada levou a reserva do reconciliador: $(cat "$tmpdir/resume")" >&2
  exit 1
fi
released="$(psqlq -c "select public.release_pix_reservation('ee611111-1111-4111-8111-111111111111', 'ee711111-1111-4111-8111-111111111111')")"
attempt="$(psqlq -c "select attempt_id::text from public.payment_charges where id = 'ee611111-1111-4111-8111-111111111111'")"
if [[ "$released" != "f" || "$attempt" == "ee711111-1111-4111-8111-111111111111" ]]; then
  echo "attempt antigo ainda solta a reserva release=${released} attempt=${attempt}" >&2
  exit 1
fi

psqlq -f - <<'SQL'
insert into auth.users (id, email, raw_user_meta_data)
values (
  'ee121111-1111-4111-8111-111111111111',
  'sessao-retomada@example.com',
  '{"display_name":"Retomada"}'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, reserved_at, attempt_id
) values (
  'ee811111-1111-4111-8111-111111111111',
  'dd511111-1111-4111-8111-111111111111',
  'ee121111-1111-4111-8111-111111111111',
  'dd211111-1111-4111-8111-111111111111',
  10000,
  'PIX',
  'creating',
  null,
  'idem-sessao-retomada',
  1000,
  now() - interval '5 minutes',
  'ee911111-1111-4111-8111-111111111111'
);
SQL

psqlq -f - <<'SQL'
do $$
declare
  v_work jsonb;
  v_owned uuid;
  v_resumed uuid;
  v_attached text;
  v_provider text;
begin
  v_work := public.claim_payment_reconciliation();
  select (elem->>'attempt_id')::uuid into v_owned
  from jsonb_array_elements(v_work->'creating') elem
  where elem->>'charge_id' = 'ee811111-1111-4111-8111-111111111111';
  if v_owned is null then
    raise exception 'claim não devolveu a reserva da retomada';
  end if;

  update public.payment_charges
  set reserved_at = pg_catalog.now() - interval '5 minutes'
  where id = 'ee811111-1111-4111-8111-111111111111'
    and attempt_id = v_owned;

  v_resumed := public.claim_expired_pix_reservation(
    'ee811111-1111-4111-8111-111111111111'
  );
  if v_resumed is null or v_resumed = v_owned then
    raise exception 'usuário não retomou a reserva vencida';
  end if;
  v_attached := public.attach_pix_provider(
    'ee811111-1111-4111-8111-111111111111',
    'pay_retomado',
    v_resumed
  );
  if v_attached is distinct from 'pay_retomado' then
    raise exception 'vínculo do usuário falhou: %', v_attached;
  end if;
  if public.confirm_reconcile_claim(
    'ee811111-1111-4111-8111-111111111111',
    v_owned
  ) then
    raise exception 'reconciliador vencido ainda confirmou o claim';
  end if;
  select provider_ref into v_provider
  from public.payment_charges
  where id = 'ee811111-1111-4111-8111-111111111111';
  if v_provider is distinct from 'pay_retomado' then
    raise exception 'confirm mexeu no pagamento do usuário: %', v_provider;
  end if;
end $$;
SQL

rm -rf "$tmpdir"
echo "payment sessions ok"
