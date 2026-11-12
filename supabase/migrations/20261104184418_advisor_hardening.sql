-- Funções de gatilho não devem ser chamáveis via /rpc.
-- Idempotente: a partir de 20261105180000 essas três funções saem de public.
do $advisor_hardening$
begin
  if to_regprocedure('public.handle_new_user()') is not null then
    execute 'revoke execute on function public.handle_new_user() from public, anon, authenticated';
  end if;
  if to_regprocedure('public.venues_guard()') is not null then
    execute 'revoke execute on function public.venues_guard() from public, anon, authenticated';
  end if;
  if to_regprocedure('public.profiles_guard()') is not null then
    execute 'revoke execute on function public.profiles_guard() from public, anon, authenticated';
  end if;
end
$advisor_hardening$;

-- search_path fixo.
alter function public.sessions_overlap(timestamptz, integer, timestamptz, integer) set search_path = public;
