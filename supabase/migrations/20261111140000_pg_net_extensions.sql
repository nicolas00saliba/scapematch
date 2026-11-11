-- Move o pg_net do schema public para o schema extensions.
-- A extensão não é relocatable: ALTER EXTENSION SET SCHEMA falha.
-- O controle não fixa schema, então CREATE EXTENSION WITH SCHEMA
-- grava extnamespace em extensions. A API continua em net
-- (net.http_post e as demais), criada pelo próprio script da extensão.
-- private.invoke_reconcile_payments() e private.notify_settle_on_close()
-- chamam net.http_post pelo nome e não têm pg_depend na extensão,
-- então DROP EXTENSION sem CASCADE não as remove.
-- Efeito colateral: apaga a fila e o histórico em net._http_response.
-- Aborta se a fila não estiver vazia no momento do DROP.
-- O script da extensão devolve USAGE em net e ALL nas tabelas e na
-- sequência para PUBLIC. No projeto, o event trigger
-- issue_pg_net_access (0.20.4) ainda dá USAGE para
-- supabase_functions_admin, postgres, anon, authenticated e service_role.
-- supautils cria a extensão como supabase_admin; postgres não consegue
-- repetir esses GRANTs. Quando o papel atual é o dono de net, não há
-- event trigger, e os GRANTs saem daqui. Nos dois casos a migração
-- confere a ACL que existia antes da mudança.
-- Sem pg_net, ou com a extensão já em extensions, não faz nada.

do $move$
declare
  v_schema name;
  v_version text;
  v_owner oid;
  v_role name;
  v_rel text;
  v_priv text;
  v_can_grant boolean;
begin
  perform set_config('search_path', 'pg_catalog', true);

  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net ausente; schema da extensão não foi alterado';
    return;
  end if;

  select n.nspname, e.extversion
    into v_schema, v_version
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_net';

  if v_schema = 'extensions' then
    raise notice 'pg_net já está no schema extensions';
    return;
  end if;

  if to_regclass('net.http_request_queue') is not null then
    lock table net.http_request_queue in access exclusive mode;
    if exists (select 1 from net.http_request_queue) then
      raise exception 'fila do pg_net não está vazia; adie esta migração';
    end if;
  end if;

  if not exists (select 1 from pg_namespace where nspname = 'extensions') then
    create schema extensions;
  end if;

  execute 'drop extension pg_net';
  execute format(
    'create extension pg_net with schema extensions version %L',
    v_version
  );

  select n.nspowner
    into v_owner
  from pg_namespace n
  where n.nspname = 'net';

  v_can_grant := v_owner = (select oid from pg_roles where rolname = current_user)
    or coalesce((select rolsuper from pg_roles where rolname = current_user), false);

  if v_can_grant then
    foreach v_role in array array[
      'postgres',
      'anon',
      'authenticated',
      'service_role',
      'supabase_functions_admin'
    ]
    loop
      if exists (select 1 from pg_roles where rolname = v_role) then
        execute format('grant usage on schema net to %I', v_role);
      end if;
    end loop;

    grant usage on schema net to public;
    grant all on table net.http_request_queue to public;
    grant all on table net._http_response to public;

    if to_regclass('net.http_request_queue_id_seq') is not null then
      grant all on sequence net.http_request_queue_id_seq to public;
    end if;
  end if;

  select n.nspname
    into v_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_net';

  if v_schema is distinct from 'extensions' then
    raise exception 'pg_net ficou no schema %', coalesce(v_schema, '(sem extensão)');
  end if;

  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception 'net.http_post não foi recriado';
  end if;

  if not exists (
    select 1
    from aclexplode((select nspacl from pg_namespace where nspname = 'net')) acl
    where acl.grantee = 0
      and acl.privilege_type = 'USAGE'
  ) then
    raise exception 'public ficou sem usage no schema net';
  end if;

  foreach v_role in array array[
    'postgres',
    'anon',
    'authenticated',
    'service_role',
    'supabase_functions_admin'
  ]
  loop
    if exists (select 1 from pg_roles where rolname = v_role)
       and not exists (
         select 1
         from aclexplode((select nspacl from pg_namespace where nspname = 'net')) acl
         where acl.grantee = (select oid from pg_roles where rolname = v_role)
           and acl.privilege_type = 'USAGE'
       )
    then
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
        from aclexplode((
          select relacl from pg_class where oid = v_rel::regclass
        )) acl
        where acl.grantee = 0
          and acl.privilege_type = v_priv
      ) then
        raise exception 'public ficou sem % em %', v_priv, v_rel;
      end if;
    end loop;

    if current_setting('server_version_num')::int >= 170000
       and not exists (
         select 1
         from aclexplode((
           select relacl from pg_class where oid = v_rel::regclass
         )) acl
         where acl.grantee = 0
           and acl.privilege_type = 'MAINTAIN'
       )
    then
      raise exception 'public ficou sem MAINTAIN em %', v_rel;
    end if;
  end loop;

  if to_regclass('net.http_request_queue_id_seq') is not null then
    foreach v_priv in array array['USAGE', 'SELECT', 'UPDATE']
    loop
      if not exists (
        select 1
        from aclexplode((
          select relacl from pg_class where oid = 'net.http_request_queue_id_seq'::regclass
        )) acl
        where acl.grantee = 0
          and acl.privilege_type = v_priv
      ) then
        raise exception 'public ficou sem % na sequência da fila', v_priv;
      end if;
    end loop;
  end if;
end
$move$;
