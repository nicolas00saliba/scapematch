-- CPF do jogador: só o dono grava, e o número não volta no erro.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('a9111111-1111-1111-1111-111111111111', 'cpf-a@example.com', '{"display_name":"Ana Cpf"}'),
  ('a9222222-2222-2222-2222-222222222222', 'cpf-b@example.com', '{"display_name":"Beto Cpf"}');

do $$
begin
  if has_column_privilege('authenticated', 'public.profiles', 'cpf', 'select')
    or has_column_privilege('authenticated', 'public.profiles', 'cpf', 'update')
    or has_column_privilege('anon', 'public.profiles', 'cpf', 'select')
    or not has_column_privilege('service_role', 'public.profiles', 'cpf', 'select')
  then
    raise exception 'coluna cpf ficou visível para o papel errado';
  end if;
  if not has_function_privilege('authenticated', 'public.set_my_cpf(text)', 'execute')
    or not has_function_privilege('authenticated', 'public.my_cpf_status()', 'execute')
    or not has_function_privilege('authenticated', 'public.my_cpf()', 'execute')
    or has_function_privilege('anon', 'public.set_my_cpf(text)', 'execute')
    or has_function_privilege('anon', 'public.my_cpf()', 'execute')
  then
    raise exception 'execute do cpf saiu do combinado';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'my_cpf'
      and p.prosecdef
      and 'search_path=""' = any (p.proconfig)
  ) then
    raise exception 'my_cpf sem security definer ou search_path vazio';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('set_my_cpf', 'my_cpf_status')
      and p.prosecdef
      and 'search_path=""' = any (p.proconfig)
    having count(*) = 2
  ) then
    raise exception 'funcao de cpf sem security definer ou search_path vazio';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_valid_cpf'
      and not p.prosecdef
      and 'search_path=""' = any (p.proconfig)
      and p.prosrc like '%pg_catalog.regexp_replace%'
      and p.prosrc like '%pg_catalog.substr%'
      and p.prosrc not like '%:= regexp_replace%'
      and p.prosrc not like '%+ substr(%'
  ) then
    raise exception 'is_valid_cpf sem search_path ou chamada qualificada';
  end if;
  if public.is_valid_cpf('529.982.247-25') is not true
    or public.is_valid_cpf('111.111.111-11') is not false
  then
    raise exception 'is_valid_cpf mudou o veredito';
  end if;
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profile_cpf_audit'
      and column_name not in ('user_id', 'defined_at', 'cpf_hash')
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profile_cpf_audit'
      and column_name = 'cpf_hash'
      and udt_name = 'bytea'
  ) then
    raise exception 'auditoria do cpf ganhou coluna a mais';
  end if;
  if has_table_privilege('authenticated', 'public.profile_cpf_audit', 'select')
    or has_table_privilege('authenticated', 'public.profile_cpf_audit', 'insert')
    or has_table_privilege('anon', 'public.profile_cpf_audit', 'select')
  then
    raise exception 'auditoria do cpf ficou aberta';
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', 'a9111111-1111-1111-1111-111111111111', true);
set local role authenticated;

do $$
begin
  if public.my_cpf_status() then
    raise exception 'perfil nasceu com cpf';
  end if;
  begin
    perform public.set_my_cpf('111.111.111-11');
    raise exception 'aceitou cpf invalido';
  exception
    when invalid_parameter_value then
      if sqlerrm ~ '[0-9]' then
        raise exception 'mensagem do cpf levou digito';
      end if;
  end;
  if not public.set_my_cpf('529.982.247-25') then
    raise exception 'nao guardou o cpf';
  end if;
  if not public.my_cpf_status() then
    raise exception 'status nao viu o cpf guardado';
  end if;
  if public.my_cpf() is distinct from '52998224725' then
    raise exception 'my_cpf nao devolveu o cpf do dono';
  end if;
  begin
    perform public.set_my_cpf('390.533.447-05');
    raise exception 'trocou cpf ja definido';
  exception
    when object_not_in_prerequisite_state then
      if sqlerrm ~ '[0-9]' then
        raise exception 'mensagem de troca levou digito';
      end if;
  end;
  if public.my_cpf() is distinct from '52998224725' then
    raise exception 'cpf mudou depois do bloqueio';
  end if;
  begin
    perform 1 from public.profile_cpf_audit where user_id = auth.uid();
    raise exception 'authenticated leu a auditoria';
  exception
    when insufficient_privilege then
      if sqlerrm ~ '[0-9]' then
        raise exception 'erro da auditoria levou digito';
      end if;
  end;
  begin
    update public.profiles set cpf = '52998224725' where id = auth.uid();
    raise exception 'update direto da coluna passou';
  exception
    when insufficient_privilege then
      if sqlerrm ~ '[0-9]' then
        raise exception 'erro de coluna levou digito';
      end if;
  end;
end $$;

reset role;
select set_config('request.jwt.claim.sub', 'a9222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
begin
  if public.my_cpf_status() or public.my_cpf() is not null then
    raise exception 'outro jogador viu o cpf';
  end if;
  begin
    perform cpf from public.profiles
      where id = 'a9111111-1111-1111-1111-111111111111';
    raise exception 'select da coluna passou';
  exception
    when insufficient_privilege then
      if sqlerrm ~ '[0-9]' then
        raise exception 'erro de select levou digito';
      end if;
  end;
  if not exists (
    select 1 from public.profiles
    where id = 'a9222222-2222-2222-2222-222222222222'
      and display_name = 'Beto Cpf'
  ) then
    raise exception 'o restante do perfil deixou de ser legivel';
  end if;
end $$;

reset role;
set role service_role;

do $$
begin
  if not exists (
    select 1 from public.profiles
    where id = 'a9111111-1111-1111-1111-111111111111'
      and cpf = '52998224725'
  ) then
    raise exception 'service_role nao leu o cpf normalizado';
  end if;
  if (
    select count(*)
    from public.profile_cpf_audit
    where user_id = 'a9111111-1111-1111-1111-111111111111'
  ) <> 1 then
    raise exception 'auditoria nao registrou uma definicao';
  end if;
  if exists (
    select 1
    from public.profile_cpf_audit
    where user_id = 'a9111111-1111-1111-1111-111111111111'
      and (
        cpf_hash is distinct from extensions.digest('52998224725', 'sha256')
        or encode(cpf_hash, 'hex') like '%52998224725%'
        or defined_at is null
      )
  ) then
    raise exception 'auditoria guardou o cpf ou o hash nao confere';
  end if;
end $$;

reset role;
commit;
