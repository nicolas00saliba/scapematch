-- pg_net, quando existe, fica no schema extensions e a API net.http_post
-- continua no lugar. O Postgres do CI não traz a extensão; aí o teste
-- não tem o que afirmar e segue.

\set ON_ERROR_STOP on

do $$
declare
  v_schema name;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net ausente neste Postgres; asserção de schema ignorada';
    return;
  end if;

  select n.nspname
    into v_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_net';

  if v_schema is distinct from 'extensions' then
    raise exception 'pg_net está no schema %, esperado extensions', v_schema;
  end if;

  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception 'net.http_post(text,jsonb,jsonb,jsonb,integer) não existe';
  end if;
end $$;
