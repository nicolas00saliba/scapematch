-- DESATIVAÇÃO DA CONTA PAGBANK DA NINJA ESCAPE ROOM. NÃO É MIGRATION.
-- Roda uma vez, à mão, com o ok do Nícolas, ANTES da migration
-- 20261126170000_pagbank_conta_unica.sql e antes de publicar as functions.
--
-- O que faz, numa transação só:
--   * confere que a casa é a Ninja e que a conta ligada termina em 13CA;
--   * recusa se houver saque pendente ou cobrança a caminho para a conta;
--   * grava o histórico em admin_audit_log (conta inteira só aqui, tabela de
--     admin; o ator é o único admin) antes de soltar a casa;
--   * apaga o token (segredo) e zera venues.pagbank_account_id.
-- Não apaga a casa, cobranças, saques nem auditoria. Rodar de novo, com a casa
-- já sem conta, não faz nada.
--
-- A tabela não tem status nem disconnected_at: "conta ativa" é
-- venues.pagbank_account_id preenchido. Desativar é zerar esse ponteiro e
-- registrar o antes na auditoria.
--
-- A outra conta conectada hoje de manhã (14:15 BRT) foi sobrescrita pela das
-- 14:46 (BRT): o banco só guarda a última e não há id dela em lugar nenhum.
-- O token dela já foi substituído. Quem a autorizou pode revogar o acesso do
-- EscapeMatch no app do PagBank.

begin;

do $$
declare
  v_venue constant uuid := '8e6cbbc4-ff74-4976-85b0-c684e7eb528f';
  v_expected_last4 constant text := '13CA';
  v_account text;
  v_name text;
  v_actor uuid;
  v_admins integer;
  v_busy integer;
begin
  select pg_catalog.count(*) into v_admins from public.admins;
  if v_admins <> 1 then
    raise exception 'esperava um único admin, achei %; escolha o ator à mão', v_admins;
  end if;
  select user_id into v_actor from public.admins;

  select v.name, v.pagbank_account_id
    into v_name, v_account
  from public.venues v
  where v.id = v_venue
  for update;
  if not found or v_name is distinct from 'Ninja Escape Room' then
    raise exception 'a casa não é a Ninja Escape Room; nada foi feito';
  end if;

  if v_account is null or pg_catalog.btrim(v_account) = '' then
    delete from public.venue_pagbank_tokens where venue_id = v_venue;
    raise notice 'a casa já estava sem conta; nada a fazer';
    return;
  end if;
  if right(v_account, 4) is distinct from v_expected_last4 then
    raise exception 'a conta da casa termina em %, esperava %; nada foi feito',
      right(v_account, 4), v_expected_last4;
  end if;

  select
    (select pg_catalog.count(*) from public.venue_withdrawals w
      where w.venue_id = v_venue and w.status = 'pending')
    + (select pg_catalog.count(*) from public.payment_charges c
      where c.venue_id = v_venue
        and (c.status in ('creating', 'pending', 'authorized')
          or (c.status = 'paid' and c.custody_released_at is null
              and c.refunded_at is null)))
    into v_busy;
  if v_busy > 0 then
    raise exception 'há % item(ns) a caminho para a conta atual; nada foi feito', v_busy;
  end if;

  insert into public.admin_audit_log (
    actor_id, action, target_table, target_id, before_state, after_state
  ) values (
    v_actor,
    'disconnect_pagbank',
    'venues',
    v_venue::text,
    pg_catalog.jsonb_build_object(
      'account_id', v_account,
      'account_last4', right(v_account, 4),
      'motivo', 'duas contas conectadas na mesma casa; decisão do dono do EscapeMatch'
    ),
    pg_catalog.jsonb_build_object('account_last4', null, 'by_admin', true)
  );

  delete from public.venue_pagbank_tokens where venue_id = v_venue;
  delete from public.pagbank_connect_states
  where venue_id = v_venue and used_at is null;
  update public.venues set pagbank_account_id = null where id = v_venue;
  raise notice 'Ninja desconectada da conta final %', v_expected_last4;
end $$;

-- Conferência: a casa fica sem conta e sem token; o histórico fica.
select
  (select pagbank_account_id is null from public.venues
    where id = '8e6cbbc4-ff74-4976-85b0-c684e7eb528f') as casa_sem_conta,
  not exists (select 1 from public.venue_pagbank_tokens
    where venue_id = '8e6cbbc4-ff74-4976-85b0-c684e7eb528f') as sem_token,
  (select pg_catalog.count(*) from public.admin_audit_log
    where action = 'disconnect_pagbank'
      and target_id = '8e6cbbc4-ff74-4976-85b0-c684e7eb528f') as linhas_de_historico;

commit;
