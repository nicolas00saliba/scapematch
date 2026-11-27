-- Código de indicação por unidade.
--
-- Um login do Parceiro pode ter mais de uma unidade (ex.: a mesma casa em duas
-- cidades, com CNPJs diferentes). O RPC antigo `my_venue_referral_code()`
-- devolve o código da unidade mais nova do login. Este, com `p_venue_id`,
-- devolve o da unidade aberta no painel, e só se ela for do login.
-- O RPC antigo continua, para o app publicado antes desta mudança.

create or replace function public.my_venue_referral_code(p_venue_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_venue_id is null or not exists (
    select 1
    from public.venues
    where id = p_venue_id
      and owner_id = auth.uid()
  ) then
    return null;
  end if;
  perform private.ensure_venue_code(p_venue_id);
  select code into v_code
  from public.referral_codes
  where owner_venue_id = p_venue_id;
  return v_code;
end;
$$;

revoke all on function public.my_venue_referral_code(uuid) from public, anon, authenticated;
grant execute on function public.my_venue_referral_code(uuid) to authenticated;
