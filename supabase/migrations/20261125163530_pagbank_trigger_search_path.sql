-- Advisor function_search_path_mutable.
-- private.sync_pagbank_charge() e private.sync_pagbank_withdrawal()
-- nasceram sem search_path. Recria as duas com search_path vazio.
-- lower fica em pg_catalog para o corpo não depender do caminho.
-- O gatilho continua o mesmo: create or replace preserva o oid da função.
-- Não aplicado no projeto remoto.

create or replace function private.sync_pagbank_charge()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.provider is null
      or pg_catalog.lower(new.provider) in (
        'asaas', 'woovi', 'openpix', 'mercadopago', 'mercado_pago'
      )
    then
      new.provider := 'pagbank';
    end if;
  elsif new.provider is distinct from old.provider then
    if new.provider is null
      or pg_catalog.lower(new.provider) in (
        'asaas', 'woovi', 'openpix', 'mercadopago', 'mercado_pago'
      )
    then
      new.provider := 'pagbank';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    if new.provider_fee_cents is distinct from old.provider_fee_cents then
      new.asaas_fee_cents := new.provider_fee_cents;
    elsif new.asaas_fee_cents is distinct from old.asaas_fee_cents then
      new.provider_fee_cents := new.asaas_fee_cents;
    end if;
  else
    if new.provider_fee_cents is not null then
      new.asaas_fee_cents := new.provider_fee_cents;
    else
      new.provider_fee_cents := new.asaas_fee_cents;
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.sync_pagbank_withdrawal()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.pagbank_transfer_id is not null then
      new.asaas_transfer_id := new.pagbank_transfer_id;
    end if;
    return new;
  end if;
  if new.pagbank_transfer_id is not null
    and new.pagbank_transfer_id is distinct from old.pagbank_transfer_id
  then
    new.asaas_transfer_id := new.pagbank_transfer_id;
  end if;
  return new;
end;
$$;
