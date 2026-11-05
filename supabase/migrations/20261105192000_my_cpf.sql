-- O jogador lê o próprio CPF para preencher "O cartão é meu".
-- Não devolve o CPF de outra pessoa. O titular do cartão não é gravado.

create or replace function public.my_cpf()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.cpf
  from public.profiles p
  where p.id = auth.uid();
$$;

revoke all on function public.my_cpf() from public, anon;
grant execute on function public.my_cpf() to authenticated;
