#!/bin/bash
# Exercita a mudança de schema do pg_net quando o pacote está instalado.
# Sem o pacote (o Postgres do CI), só confere o SQL e segue.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
migration="$root/supabase/migrations/20261111140000_pg_net_extensions.sql"
db="scapematch_pg_net"

if ! grep -Eq "execute 'drop extension pg_net'" "$migration"; then
  echo "a migração não dá DROP EXTENSION pg_net sem CASCADE"
  exit 1
fi
if grep -Eiq 'drop extension[[:space:]]+(if exists[[:space:]]+)?pg_net[[:space:]]+cascade' "$migration"; then
  echo "DROP EXTENSION pg_net não pode usar CASCADE"
  exit 1
fi
if ! grep -Eq 'create extension pg_net with schema extensions' "$migration"; then
  echo "a migração não recria pg_net no schema extensions"
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
  if [[ -n "${DATABASE_URL:-}" ]]; then
    psql "${DATABASE_URL%/*}/${db}" -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d "$db" -v ON_ERROR_STOP=1 "$@"
  fi
}

available="$(admin_psql -tAc "select exists (select 1 from pg_available_extensions where name = 'pg_net')")"
available="$(echo "$available" | tr -d '[:space:]')"
if [[ "$available" != "t" ]]; then
  echo "pg_net ausente; movimentação não foi exercitada"
  exit 0
fi

created_sfa=0
cleanup() {
  admin_psql -c "drop database if exists ${db} with (force);" >/dev/null || true
  if [[ "$created_sfa" == "1" ]]; then
    admin_psql -c "drop role if exists supabase_functions_admin;" >/dev/null || true
  fi
}
trap cleanup EXIT

sfa="$(admin_psql -tAc "select exists (select 1 from pg_roles where rolname = 'supabase_functions_admin')")"
sfa="$(echo "$sfa" | tr -d '[:space:]')"
if [[ "$sfa" != "t" ]]; then
  admin_psql -c "create role supabase_functions_admin nologin noinherit;" >/dev/null
  created_sfa=1
fi

admin_psql -c "drop database if exists ${db} with (force);" >/dev/null
admin_psql -c "create database ${db};" >/dev/null

psql_db <<'SQL' >/dev/null
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_functions_admin') then
    create role supabase_functions_admin nologin noinherit;
  end if;
end $$;

create schema if not exists extensions;
create schema if not exists private;

create extension pg_net;

create function private.invoke_reconcile_payments()
returns void
language plpgsql
security definer
set search_path = ''
as $body$
begin
  perform net.http_post(
    url := 'https://example.invalid/reconcile',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 90000
  );
end;
$body$;

create function private.notify_settle_on_close()
returns trigger
language plpgsql
security definer
set search_path = ''
as $body$
begin
  perform net.http_post(
    url := 'https://example.invalid/settle',
    body := pg_catalog.jsonb_build_object('id', new.id),
    headers := pg_catalog.jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 90000
  );
  return new;
end;
$body$;
SQL

installed="$(psql_db -tAc "select n.nspname || '|' || e.extversion from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_net'")"
installed="$(echo "$installed" | tr -d '[:space:]')"
if [[ "$installed" != "public|"* ]]; then
  echo "pg_net não nasceu no schema public: ${installed}"
  exit 1
fi
version="${installed#public|}"
fn_hash="$(psql_db -tAc "select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'invoke_reconcile_payments'")"
fn_hash="$(echo "$fn_hash" | tr -d '[:space:]')"

set +e
abort="$(psql_db -v ON_ERROR_STOP=1 <<SQL 2>&1
begin;
insert into net.http_request_queue (method, url, timeout_milliseconds)
values ('GET', 'https://example.invalid/queue', 1000);
\\i ${migration}
commit;
SQL
)"
abort_status=$?
set -e
if [[ "$abort_status" -eq 0 ]]; then
  echo "a migração seguiu com a fila do pg_net ocupada"
  printf '%s\n' "$abort"
  exit 1
fi
if ! grep -q 'fila do pg_net não está vazia' <<<"$abort"; then
  echo "a fila ocupada não abortou com a mensagem esperada"
  printf '%s\n' "$abort"
  exit 1
fi

still_public="$(psql_db -tAc "select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_net'")"
still_public="$(echo "$still_public" | tr -d '[:space:]')"
if [[ "$still_public" != "public" ]]; then
  echo "o aborto mudou o schema do pg_net para ${still_public}"
  exit 1
fi

psql_db -c "insert into net._http_response (id) values (7);" >/dev/null
psql_db -f "$migration" >/dev/null

after="$(psql_db -tAc "
select concat_ws('|',
  (select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_net'),
  (select extversion from pg_extension where extname = 'pg_net'),
  to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')::text,
  (select count(*)::text from net._http_response),
  (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'invoke_reconcile_payments'),
  (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'private' and p.proname = 'notify_settle_on_close')
)
")"
after="$(echo "$after" | tr -d '[:space:]')"
want="extensions|${version}|net.http_post(text,jsonb,jsonb,jsonb,integer)|0|${fn_hash}|1"
if [[ "$after" != "$want" ]]; then
  echo "resultado inesperado depois da mudança: ${after}"
  echo "esperado: ${want}"
  exit 1
fi

psql_db <<'SQL' >/dev/null
do $$
declare
  v_role name;
  v_rel text;
  v_priv text;
begin
  if not exists (
    select 1
    from aclexplode((select nspacl from pg_namespace where nspname = 'net')) acl
    where acl.grantee = 0 and acl.privilege_type = 'USAGE'
  ) then
    raise exception 'public ficou sem usage no schema net';
  end if;

  foreach v_role in array array[
    'postgres', 'anon', 'authenticated', 'service_role', 'supabase_functions_admin'
  ]
  loop
    if not exists (
      select 1
      from aclexplode((select nspacl from pg_namespace where nspname = 'net')) acl
      where acl.grantee = (select oid from pg_roles where rolname = v_role)
        and acl.privilege_type = 'USAGE'
    ) then
      raise exception 'o papel % ficou sem usage no schema net', v_role;
    end if;
  end loop;

  foreach v_rel in array array['net.http_request_queue', 'net._http_response']
  loop
    foreach v_priv in array array[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ]
    loop
      if not exists (
        select 1
        from aclexplode((select relacl from pg_class where oid = v_rel::regclass)) acl
        where acl.grantee = 0 and acl.privilege_type = v_priv
      ) then
        raise exception 'public ficou sem % em %', v_priv, v_rel;
      end if;
    end loop;
  end loop;

  foreach v_priv in array array['USAGE', 'SELECT', 'UPDATE']
  loop
    if not exists (
      select 1
      from aclexplode((
        select relacl from pg_class where oid = 'net.http_request_queue_id_seq'::regclass
      )) acl
      where acl.grantee = 0 and acl.privilege_type = v_priv
    ) then
      raise exception 'public ficou sem % na sequência da fila', v_priv;
    end if;
  end loop;
end $$;
SQL

psql_db -c "insert into net._http_response (id) values (8);" >/dev/null
psql_db -f "$migration" >/dev/null
kept="$(psql_db -tAc "select count(*) from net._http_response where id = 8")"
kept="$(echo "$kept" | tr -d '[:space:]')"
if [[ "$kept" != "1" ]]; then
  echo "a segunda execução recriou o pg_net e apagou o histórico"
  exit 1
fi

echo "pg_net move ok"
