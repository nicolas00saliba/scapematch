-- O CPF de quem pagou não precisa ser o da conta. Pais pagam pelos filhos.
-- O estado abaixo fica só como registro. A trava nova está em
-- 20261108160000_referral_payer_antifraud.sql.
-- Pix: o documento vem de GET /v3/pix/transactions/{id}. O webhook não traz.
-- O exemplo oficial mascara o CPF. Sem 11 ou 14 dígitos não há hash.
-- Não guarda o CPF do pagador. Não foi aplicado no projeto remoto.

comment on column public.payment_charges.payer_document_status is
  'matched: CPF de quem pagou é o da conta. mismatch: outro documento. unverified: o Asaas não devolveu 11 ou 14 dígitos.';

alter table public.saved_cards
  add column holder_cpf_matches boolean;

comment on column public.saved_cards.holder_cpf_matches is
  'O CPF do titular enviado ao Asaas bate com o CPF da conta. Nulo em cartão antigo: não verificado.';

comment on table public.referral_withholdings is
  'Motivo imutável para não lançar recompensa nem desconto de indicação. Não guarda documento.';

create or replace function private.record_payer_document_status(
  p_charge_id uuid,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current text;
  v_next text;
begin
  if p_status is null or p_status not in ('matched', 'mismatch', 'unverified') then
    raise exception 'status invalido' using errcode = '22023';
  end if;
  select payer_document_status into v_current
  from public.payment_charges
  where id = p_charge_id
  for update;
  if not found then
    raise exception 'charge_not_found' using errcode = 'P0002';
  end if;
  v_next := case
    when v_current in ('matched', 'mismatch') then v_current
    else p_status
  end;
  if v_current is distinct from v_next then
    update public.payment_charges
    set payer_document_status = v_next
    where id = p_charge_id;
  end if;
  return v_next;
end;
$$;

create or replace function private.referral_benefit_allowed(p_charge_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.payment_charges
    where id = p_charge_id
  );
$$;

create or replace function public.record_payer_document_status(
  p_charge_id uuid,
  p_status text
)
returns text
language sql
security invoker
set search_path = ''
as $$
  select private.record_payer_document_status(p_charge_id, p_status);
$$;

create or replace function public.referral_benefit_allowed(p_charge_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.referral_benefit_allowed(p_charge_id);
$$;

create or replace function public.mark_saved_card_holder_match(
  p_card_id uuid,
  p_user_id uuid,
  p_matches boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.saved_cards
  set holder_cpf_matches = p_matches
  where id = p_card_id
    and user_id = p_user_id;
  if not found then
    raise exception 'cartão não encontrado' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.saved_card_holder_status(
  p_user_id uuid,
  p_card_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case c.holder_cpf_matches
    when true then 'matched'
    when false then 'mismatch'
    else 'unverified'
  end
  from public.saved_cards c
  where c.id = p_card_id
    and c.user_id = p_user_id;
$$;

revoke all on function private.record_payer_document_status(uuid, text) from public, anon, authenticated;
revoke all on function private.referral_benefit_allowed(uuid) from public, anon, authenticated;

revoke all on function public.record_payer_document_status(uuid, text) from public, anon, authenticated;
revoke all on function public.referral_benefit_allowed(uuid) from public, anon, authenticated;
revoke all on function public.mark_saved_card_holder_match(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.saved_card_holder_status(uuid, uuid) from public, anon, authenticated;

grant execute on function private.record_payer_document_status(uuid, text) to service_role;
grant execute on function public.record_payer_document_status(uuid, text) to service_role;
grant execute on function public.referral_benefit_allowed(uuid) to service_role;
grant execute on function public.mark_saved_card_holder_match(uuid, uuid, boolean) to service_role;
grant execute on function public.saved_card_holder_status(uuid, uuid) to service_role;
