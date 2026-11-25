-- Cartão do provedor antigo fica inativo e pede recadastro.
-- Cartão PagBank do mesmo dono continua ativo. A linha não some.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f3111111-1111-4111-8111-111111111111',
  'cartao-antigo@example.com',
  '{"display_name":"Caio"}'
);

update public.profiles
set pagbank_customer_id = 'cus_pag_caio'
where id = 'f3111111-1111-4111-8111-111111111111';

select private.insert_saved_card(
  'f3111111-1111-4111-8111-111111111111',
  'cus_pag_caio',
  'CARD_ok_caio_1',
  '4242',
  'VISA',
  'e3111111-1111-4111-8111-111111111111'
);

select private.insert_saved_card(
  'f3111111-1111-4111-8111-111111111111',
  'cus_pag_caio',
  'asaas-token-sem-prefixo',
  '4343',
  'ELO',
  'e3333333-3333-4333-8333-333333333333'
);

alter table public.saved_cards disable trigger saved_cards_guard;

select private.insert_saved_card(
  'f3111111-1111-4111-8111-111111111111',
  'cus_asaas_caio',
  'asaas-token-antigo',
  '5151',
  'MASTERCARD',
  'e3222222-2222-4222-8222-222222222222'
);

alter table public.saved_cards enable trigger saved_cards_guard;

select private.deactivate_legacy_saved_cards();

do $$
declare
  v_rows integer;
begin
  select count(*) into v_rows
  from public.saved_cards
  where id in (
    'e3111111-1111-4111-8111-111111111111',
    'e3222222-2222-4222-8222-222222222222',
    'e3333333-3333-4333-8333-333333333333'
  );
  if v_rows <> 3 then
    raise exception 'cartão foi apagado: %', v_rows;
  end if;

  if exists (
    select 1 from public.saved_cards
    where id = 'e3222222-2222-4222-8222-222222222222'
      and deactivated_at is null
  ) then
    raise exception 'cartão antigo seguiu ativo';
  end if;
  if not public.saved_card_needs_reregister(
    'f3111111-1111-4111-8111-111111111111',
    'e3222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'cartão antigo não pediu recadastro';
  end if;

  if exists (
    select 1 from public.saved_cards
    where id = 'e3333333-3333-4333-8333-333333333333'
      and deactivated_at is null
  ) then
    raise exception 'cartão sem token PagBank seguiu ativo';
  end if;

  if exists (
    select 1 from public.saved_cards
    where id = 'e3111111-1111-4111-8111-111111111111'
      and deactivated_at is not null
  ) then
    raise exception 'cartão PagBank foi desativado';
  end if;
  if public.saved_card_needs_reregister(
    'f3111111-1111-4111-8111-111111111111',
    'e3111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'cartão PagBank pediu recadastro';
  end if;
end $$;
