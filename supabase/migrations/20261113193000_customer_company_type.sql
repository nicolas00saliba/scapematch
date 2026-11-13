-- Customer que sumiu da conta Asaas e o tipo de empresa da subconta.
-- Não aplicar no remoto até publicar create-charge, tokenize-card
-- e provision-venue-wallet.

alter table public.venues
  add column if not exists company_type text not null default 'LIMITED';

alter table public.venues
  drop constraint if exists venues_company_type_check;

alter table public.venues
  add constraint venues_company_type_check
  check (company_type in ('MEI', 'LIMITED', 'INDIVIDUAL', 'ASSOCIATION'));

comment on column public.venues.company_type is
  'Tipo de empresa na API do Asaas: MEI, LIMITED, INDIVIDUAL ou ASSOCIATION. CPF não envia companyType. LIMITED é o padrão.';

-- Desativa os cartões do customer que não existe mais nesta conta.
-- Roda antes de trocar profiles.asaas_customer_id: o gatilho do cartão
-- exige que o perfil ainda aponte para o mesmo customer.
create or replace function public.deactivate_customer_saved_cards(
  p_user_id uuid,
  p_customer_id text
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.saved_cards
  set deactivated_at = pg_catalog.now()
  where user_id = p_user_id
    and asaas_customer_id = p_customer_id
    and deactivated_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.deactivate_customer_saved_cards(uuid, text)
  from public, anon, authenticated;
grant execute on function public.deactivate_customer_saved_cards(uuid, text)
  to service_role;

-- Cartão desativado cujo customer não é mais o do perfil: o jogador
-- recadastra. Desativação feita pela própria pessoa não entra aqui.
create or replace function public.saved_card_needs_reregister(
  p_user_id uuid,
  p_card_id uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.saved_cards c
    join public.profiles p on p.id = c.user_id
    where c.id = p_card_id
      and c.user_id = p_user_id
      and c.deactivated_at is not null
      and c.asaas_customer_id is distinct from p.asaas_customer_id
  );
$$;

revoke all on function public.saved_card_needs_reregister(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.saved_card_needs_reregister(uuid, uuid)
  to service_role;
