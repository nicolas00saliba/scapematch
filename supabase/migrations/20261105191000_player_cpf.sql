-- CPF do jogador, para o customer do Asaas. Não altera a 190000.
-- authenticated lê e grava o próprio perfil, menos esta coluna.
-- O número só entra por set_my_cpf, e só enquanto o perfil está vazio.
-- Troca futura fica com suporte/admin. Cada definição vai para
-- profile_cpf_audit só com user_id e instante. Sem CPF e sem hash.
-- my_cpf_status devolve só boolean. service_role lê a coluna nas funções.
-- O valor não volta no erro.

create or replace function public.is_valid_cpf(p_cpf text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digits text;
  v_sum integer;
  v_i integer;
  v_digit integer;
begin
  if p_cpf is null then
    return false;
  end if;
  v_digits := pg_catalog.regexp_replace(p_cpf, '\D', '', 'g');
  if v_digits !~ '^\d{11}$' or v_digits ~ '^(\d)\1{10}$' then
    return false;
  end if;
  v_sum := 0;
  for v_i in 1..9 loop
    v_sum := v_sum + pg_catalog.substr(v_digits, v_i, 1)::pg_catalog.int4
      * (11 - v_i);
  end loop;
  v_digit := (v_sum * 10) % 11;
  if v_digit = 10 then
    v_digit := 0;
  end if;
  if v_digit <> pg_catalog.substr(v_digits, 10, 1)::pg_catalog.int4 then
    return false;
  end if;
  v_sum := 0;
  for v_i in 1..10 loop
    v_sum := v_sum + pg_catalog.substr(v_digits, v_i, 1)::pg_catalog.int4
      * (12 - v_i);
  end loop;
  v_digit := (v_sum * 10) % 11;
  if v_digit = 10 then
    v_digit := 0;
  end if;
  return v_digit = pg_catalog.substr(v_digits, 11, 1)::pg_catalog.int4;
end;
$$;

revoke all on function public.is_valid_cpf(text) from public, anon;
grant execute on function public.is_valid_cpf(text) to authenticated, service_role;

alter table public.profiles
  add column cpf text;

alter table public.profiles
  add constraint profiles_cpf_digits
  check (cpf is null or (cpf ~ '^\d{11}$' and public.is_valid_cpf(cpf)));

-- O grant da tabela cobre coluna nova. Tira select/update e devolve
-- só o que o app já lia e gravava. cpf fica de fora.
revoke select, update on table public.profiles from anon, authenticated;

grant select (
  id,
  display_name,
  birth_date,
  asaas_customer_id,
  created_at,
  username
) on public.profiles to authenticated;

grant update (
  display_name,
  birth_date,
  username,
  asaas_customer_id
) on public.profiles to authenticated;

-- Auditoria da definição. Só quem e quando. Sem CPF e sem hash.
create table public.profile_cpf_audit (
  user_id uuid not null references auth.users (id) on delete cascade,
  defined_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, defined_at)
);

alter table public.profile_cpf_audit enable row level security;

revoke all on table public.profile_cpf_audit from public, anon, authenticated;

create or replace function public.my_cpf_status()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.cpf is not null
    from public.profiles p
    where p.id = auth.uid()
  ), false);
$$;

create or replace function public.set_my_cpf(p_cpf text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_digits text;
  v_current text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_digits := pg_catalog.regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  if not public.is_valid_cpf(v_digits) then
    raise exception 'cpf invalido' using errcode = '22023';
  end if;
  select p.cpf into v_current
  from public.profiles p
  where p.id = auth.uid()
  for update;
  if not found then
    raise exception 'perfil ausente' using errcode = 'P0002';
  end if;
  if v_current is not null then
    raise exception 'cpf ja definido' using errcode = '55000';
  end if;
  update public.profiles
    set cpf = v_digits
    where id = auth.uid()
      and cpf is null;
  if not found then
    raise exception 'cpf ja definido' using errcode = '55000';
  end if;
  insert into public.profile_cpf_audit (user_id, defined_at)
  values (auth.uid(), pg_catalog.clock_timestamp());
  return true;
end;
$$;

revoke all on function public.my_cpf_status() from public, anon;
revoke all on function public.set_my_cpf(text) from public, anon;
grant execute on function public.my_cpf_status() to authenticated, service_role;
grant execute on function public.set_my_cpf(text) to authenticated, service_role;
