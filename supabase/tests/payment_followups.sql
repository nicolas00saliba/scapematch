-- Chave da subconta cifrada, wallet fora do cliente, órfão e compensação.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'cc111111-1111-4111-8111-111111111111',
  'followup@example.com',
  '{"display_name":"Follow-up"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, asaas_wallet_id
) values (
  'cc211111-1111-4111-8111-111111111111',
  'cc111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa Follow-up',
  'Centro',
  'Rua da Chave',
  '20',
  '80010020',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '33444555000181',
  '41988880021',
  'approved',
  'wal_follow'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'cc311111-1111-4111-8111-111111111111',
  'cc211111-1111-4111-8111-111111111111',
  'Sala Follow-up',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'cc411111-1111-4111-8111-111111111111',
  'cc311111-1111-4111-8111-111111111111',
  '2027-09-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'cc511111-1111-4111-8111-111111111111',
  'curitiba',
  'cc211111-1111-4111-8111-111111111111',
  'cc311111-1111-4111-8111-111111111111',
  'cc411111-1111-4111-8111-111111111111',
  '2027-09-01 18:00:00+00',
  4,
  2,
  10000,
  'cc111111-1111-4111-8111-111111111111'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'cc511111-1111-4111-8111-111111111111',
  'cc111111-1111-4111-8111-111111111111',
  'Follow-up',
  true,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, reserved_at, attempt_id
) values (
  'cc611111-1111-4111-8111-111111111111',
  'cc511111-1111-4111-8111-111111111111',
  'cc111111-1111-4111-8111-111111111111',
  'cc211111-1111-4111-8111-111111111111',
  10000,
  'CREDIT_CARD',
  'creating',
  null,
  'idem-follow-creating',
  1000,
  now() - interval '5 minutes',
  'cc711111-1111-4111-8111-111111111111'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'cca11111-1111-4111-8111-111111111111',
  'followup-credito@example.com',
  '{"display_name":"Crédito"}'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'cc511111-1111-4111-8111-111111111111',
  'cca11111-1111-4111-8111-111111111111',
  'Crédito',
  false,
  'released',
  'none',
  'hold_released'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, attempt_id
) values (
  'cc811111-1111-4111-8111-111111111111',
  'cc511111-1111-4111-8111-111111111111',
  'cca11111-1111-4111-8111-111111111111',
  'cc211111-1111-4111-8111-111111111111',
  8000,
  'CREDIT_CARD',
  'cancelled',
  'pay_com_credito',
  'idem-follow-credit',
  1000,
  'cc911111-1111-4111-8111-111111111111'
);

insert into public.ledger_entries (
  venue_id, group_id, user_id, account, direction, kind,
  amount_cents, payment_charge_id
) values (
  'cc211111-1111-4111-8111-111111111111',
  'cc511111-1111-4111-8111-111111111111',
  'cca11111-1111-4111-8111-111111111111',
  'house',
  'credit',
  'house_net',
  7200,
  'cc811111-1111-4111-8111-111111111111'
);

select public.store_venue_asaas_key(
  'cc211111-1111-4111-8111-111111111111',
  'chave-super-secreta'
);

do $$
declare
  v_plain text;
  v_raw text;
  v_type text;
  v_result text;
  v_work jsonb;
  v_orphan uuid;
  v_deleted boolean;
  v_attempt uuid;
  v_settle jsonb;
  v_status text;
  v_def text;
  v_claimed text;
  v_debits integer;
  v_member text;
  v_wallet text;
begin
  select data_type into v_type
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'venue_asaas_keys'
    and column_name = 'api_key';
  if v_type is distinct from 'bytea' then
    raise exception 'api_key não está cifrada: %', v_type;
  end if;

  v_plain := public.read_venue_asaas_key('cc211111-1111-4111-8111-111111111111');
  if v_plain is distinct from 'chave-super-secreta' then
    raise exception 'leitura da chave não bate';
  end if;
  select encode(api_key, 'escape') into v_raw
  from public.venue_asaas_keys
  where venue_id = 'cc211111-1111-4111-8111-111111111111';
  if v_raw like '%chave-super-secreta%' then
    raise exception 'api_key da subconta ficou em claro';
  end if;

  select pg_get_function_result('public.venue_private(uuid)'::regprocedure)
    into v_result;
  if v_result ilike '%asaas_wallet_id%' then
    raise exception 'venue_private ainda devolve a wallet';
  end if;
  if v_result not ilike '%document_number%' then
    raise exception 'venue_private perdeu o documento';
  end if;

  select pg_get_functiondef('private.claim_payment_reconciliation()'::regprocedure)
    into v_def;
  if v_def not ilike '%limit 10%'
    or v_def not ilike '%skip locked%'
    or v_def not ilike '%order by%' then
    raise exception 'claim sem lote ordenado';
  end if;

  v_work := public.claim_payment_reconciliation();
  if v_work::text not like '%cc611111-1111-4111-8111-111111111111%' then
    raise exception 'creating vencido fora do claim';
  end if;
  if v_work::text not like '%idem-follow-creating%' then
    raise exception 'externalReference do cartão não entrou no claim';
  end if;
  select elem->>'attempt_id' into v_attempt
  from jsonb_array_elements(v_work->'creating') elem
  where elem->>'charge_id' = 'cc611111-1111-4111-8111-111111111111';
  if v_attempt is not distinct from 'cc711111-1111-4111-8111-111111111111'::uuid then
    raise exception 'claim não renovou o attempt';
  end if;
  if not public.confirm_reconcile_claim(
    'cc611111-1111-4111-8111-111111111111',
    v_attempt
  ) then
    raise exception 'confirm do attempt vigente falhou';
  end if;
  if public.confirm_reconcile_claim(
    'cc611111-1111-4111-8111-111111111111',
    'cc711111-1111-4111-8111-111111111111'
  ) then
    raise exception 'confirm do attempt antigo passou';
  end if;

  v_work := public.claim_payment_reconciliation();
  if v_work::text like '%cc611111-1111-4111-8111-111111111111%' then
    raise exception 'lease fresco foi reivindicado de novo';
  end if;
  if public.claim_expired_pix_reservation(
    'cc611111-1111-4111-8111-111111111111'
  ) is not null then
    raise exception 'create-charge retomou a linha do reconciliador';
  end if;
  if public.release_pix_reservation(
    'cc611111-1111-4111-8111-111111111111',
    'cc711111-1111-4111-8111-111111111111'
  ) then
    raise exception 'attempt antigo soltou a reserva cercada';
  end if;

  perform public.apply_payment_transition(
    'cc611111-1111-4111-8111-111111111111',
    'authorized',
    false
  );

  if public.delete_compensated_charge(
    'cc611111-1111-4111-8111-111111111111',
    'cc711111-1111-4111-8111-111111111111',
    'pay_ainda_authorized'
  ) then
    raise exception 'apagar authorized não pode passar';
  end if;

  begin
    update public.payment_charges
    set provider_ref = 'pay_pago'
    where id = 'cc611111-1111-4111-8111-111111111111';
    perform public.apply_payment_transition(
      'cc611111-1111-4111-8111-111111111111',
      'paid',
      true
    );
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      'cc711111-1111-4111-8111-111111111111',
      'pay_pago',
      'refunded'
    );
    if coalesce((v_settle->>'skipped')::boolean, false)
      or v_settle->>'status' = 'refunded' then
      raise exception 'paid com attempt errado foi encerrado';
    end if;
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      v_attempt,
      'pay_outro',
      'refunded'
    );
    if coalesce((v_settle->>'skipped')::boolean, false)
      or v_settle->>'status' = 'refunded' then
      raise exception 'paid com provider errado foi encerrado';
    end if;
    select status into v_status
    from public.payment_charges
    where id = 'cc611111-1111-4111-8111-111111111111';
    if v_status is distinct from 'paid' then
      raise exception 'paid mudou sem identidade: %', v_status;
    end if;
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      v_attempt,
      'pay_pago',
      'refunded'
    );
    if v_settle->>'status' is distinct from 'refunded' then
      raise exception 'paid reembolsado no Asaas não virou refunded: %', v_settle;
    end if;
    select count(*) into v_debits
    from public.ledger_entries
    where payment_charge_id = 'cc611111-1111-4111-8111-111111111111'
      and direction = 'debit'
      and kind in ('house_refund', 'commission_refund');
    if v_debits <> 2 then
      raise exception 'ledger do pago não foi revertido: %', v_debits;
    end if;
    raise exception 'ok_paid';
  exception
    when others then
      if sqlerrm is distinct from 'ok_paid' then
        raise;
      end if;
  end;

  begin
    update public.payment_charges
    set provider_ref = 'pay_orfao_cc'
    where id = 'cc611111-1111-4111-8111-111111111111';
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      'cc711111-1111-4111-8111-111111111111',
      'pay_orfao_cc',
      'cancelled'
    );
    if coalesce((v_settle->>'skipped')::boolean, false)
      or v_settle->>'status' = 'cancelled' then
      raise exception 'attempt divergente moveu a cobrança';
    end if;
    select status into v_status
    from public.payment_charges
    where id = 'cc611111-1111-4111-8111-111111111111';
    if v_status is distinct from 'authorized' then
      raise exception 'status mudou com attempt errado: %', v_status;
    end if;
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      v_attempt,
      'pay_outro',
      'cancelled'
    );
    if coalesce((v_settle->>'skipped')::boolean, false) is not true then
      raise exception 'provider diferente não foi pulado';
    end if;
    v_settle := public.settle_orphan_charge(
      'cc611111-1111-4111-8111-111111111111',
      v_attempt,
      'pay_orfao_cc',
      'cancelled'
    );
    if v_settle->>'status' is distinct from 'cancelled' then
      raise exception 'settle não cancelou: %', v_settle;
    end if;
    raise exception 'ok_settle';
  exception
    when others then
      if sqlerrm is distinct from 'ok_settle' then
        raise;
      end if;
  end;

  v_orphan := public.record_orphan_payment(
    'pay_orfao_cc',
    'cc611111-1111-4111-8111-111111111111',
    'cc711111-1111-4111-8111-111111111111',
    'CREDIT_CARD',
    'refund_failed'
  );
  v_work := public.claim_payment_reconciliation();
  if v_work::text not like '%pay_orfao_cc%' then
    raise exception 'órfão não entrou na reconciliação';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_work->'orphans') elem
    where elem ? 'external_reference'
  ) then
    raise exception 'órfão levou externalReference da cobrança atual';
  end if;
  select elem->>'claimed_at' into v_claimed
  from jsonb_array_elements(v_work->'orphans') elem
  where elem->>'provider_ref' = 'pay_orfao_cc';
  if v_claimed is null then
    raise exception 'claim do órfão não devolveu claimed_at';
  end if;
  if not public.confirm_orphan_claim(v_orphan, v_claimed::timestamptz) then
    raise exception 'confirm do órfão vigente falhou';
  end if;
  if public.confirm_orphan_claim(v_orphan, v_claimed::timestamptz) then
    raise exception 'claimed_at antigo ainda confirma o órfão';
  end if;
  if not public.mark_orphan_resolved(v_orphan) then
    raise exception 'órfão não foi marcado';
  end if;
  if public.mark_orphan_resolved(v_orphan) then
    raise exception 'órfão resolvido foi marcado de novo';
  end if;
  v_work := public.claim_payment_reconciliation();
  if v_work::text like '%pay_orfao_cc%' then
    raise exception 'órfão resolvido continua na lista';
  end if;

  perform public.apply_payment_transition(
    'cc611111-1111-4111-8111-111111111111',
    'cancelled',
    false
  );
  select payment_status into v_member
  from public.group_members
  where group_id = 'cc511111-1111-4111-8111-111111111111'
    and user_id = 'cc111111-1111-4111-8111-111111111111';
  if v_member is distinct from 'released' then
    raise exception 'membro não foi liberado: %', v_member;
  end if;

  update public.payment_charges
  set provider_ref = 'pay_estornado'
  where id = 'cc611111-1111-4111-8111-111111111111';
  v_deleted := public.delete_compensated_charge(
    'cc611111-1111-4111-8111-111111111111',
    v_attempt,
    'pay_estornado'
  );
  if not v_deleted then
    raise exception 'cobrança estornada não foi apagada';
  end if;
  if exists (
    select 1 from public.payment_charges
    where id = 'cc611111-1111-4111-8111-111111111111'
  ) then
    raise exception 'cobrança compensada ainda existe';
  end if;

  if public.delete_compensated_charge(
    'cc811111-1111-4111-8111-111111111111',
    'cc911111-1111-4111-8111-111111111111',
    'pay_com_credito'
  ) then
    raise exception 'cobrança com crédito não pode ser apagada';
  end if;
end $$;

set role service_role;
select asaas_wallet_id as wallet_servidor
from public.venues
where id = 'cc211111-1111-4111-8111-111111111111';
reset role;

do $$
begin
  begin
    execute 'set local role authenticated';
    perform 1 from public.venues
    where id = 'cc211111-1111-4111-8111-111111111111'
      and asaas_wallet_id is not null;
    raise exception 'asaas_wallet_id visível para authenticated';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    execute 'set local role authenticated';
    perform 1 from public.payment_charges
    where wallet_id is not null;
    raise exception 'wallet_id visível para authenticated';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    execute 'set local role anon';
    perform public.read_venue_asaas_key('cc211111-1111-4111-8111-111111111111');
    raise exception 'anon leu a chave da subconta';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    execute 'set local role authenticated';
    perform public.read_venue_asaas_key('cc211111-1111-4111-8111-111111111111');
    raise exception 'authenticated leu a chave da subconta';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

do $$
declare
  v_wallet text;
begin
  set local role service_role;
  select asaas_wallet_id into v_wallet
  from public.venues
  where id = 'cc211111-1111-4111-8111-111111111111';
  if v_wallet is distinct from 'wal_follow' then
    raise exception 'service_role perdeu a wallet: %', v_wallet;
  end if;
end $$;
