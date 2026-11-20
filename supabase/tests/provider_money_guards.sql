-- Saque pelo livro, reenvio de webhook, estorno idempotente e chargeback.
-- Não fala com provedor.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f9111111-1111-4111-8111-111111111111',
  'casa-livro@example.com',
  '{"display_name":"Casa Livro"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'f9200000-0000-4000-8000-000000000001',
  'f9111111-1111-4111-8111-111111111111',
  'curitiba',
  'Casa do Livro',
  'Centro',
  'Rua do Livro',
  '1',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '80706050000195',
  '4130000195',
  'approved'
);

insert into public.provider_payout_accounts (
  venue_id, provider, external_id, pix_key, status
) values (
  'f9200000-0000-4000-8000-000000000001',
  'woovi',
  'casa@pix',
  'casa@pix',
  'active'
);

update public.venue_payouts_settings set enabled = true where id = 1;

do $$
begin
  if pg_catalog.pg_get_functiondef(
    'public.claim_provider_withdrawal(uuid,uuid,text,text,integer,integer,text)'::regprocedure
  ) not like '%for update%' then
    raise exception 'o saque não trava a conta da casa';
  end if;
  begin
    perform public.claim_provider_withdrawal(
      'f9200000-0000-4000-8000-000000000001',
      'f9111111-1111-4111-8111-111111111111',
      'manual',
      '',
      100,
      999999,
      'woovi'
    );
    raise exception 'saque sem livro passou com saldo da subconta';
  exception
    when others then
      if sqlerrm <> 'saldo' then
        raise;
      end if;
  end;
end $$;

insert into public.ledger_entries (
  venue_id, account, direction, kind, amount_cents
) values (
  'f9200000-0000-4000-8000-000000000001',
  'house', 'credit', 'house_net', 8000
);

do $$
declare
  v_first jsonb;
  v_left integer;
begin
  if public.provider_house_withdrawable(
    'f9200000-0000-4000-8000-000000000001',
    'f9111111-1111-4111-8111-111111111111'
  ) <> 8000 then
    raise exception 'o disponível não veio do livro';
  end if;
  v_first := public.claim_provider_withdrawal(
    'f9200000-0000-4000-8000-000000000001',
    'f9111111-1111-4111-8111-111111111111',
    'manual',
    '',
    8000,
    999999,
    'woovi'
  );
  if (v_first ->> 'amount_cents')::integer <> 8000 then
    raise exception 'o saque não ficou no valor liquidado';
  end if;
  v_left := public.provider_house_withdrawable(
    'f9200000-0000-4000-8000-000000000001',
    'f9111111-1111-4111-8111-111111111111'
  );
  if v_left <> 0 then
    raise exception 'o pendente ainda aparece como disponível: %', v_left;
  end if;
  begin
    perform public.claim_provider_withdrawal(
      'f9200000-0000-4000-8000-000000000001',
      'f9111111-1111-4111-8111-111111111111',
      'manual',
      '',
      1,
      999999,
      'woovi'
    );
    raise exception 'dois saques passaram juntos';
  exception
    when others then
      if sqlerrm <> 'saldo' then
        raise;
      end if;
  end;
end $$;

do $$
begin
  if public.claim_provider_webhook('woovi', 'evt-falha-1') is not true then
    raise exception 'evento novo não entrou';
  end if;
  if public.release_provider_webhook('woovi', 'evt-falha-1') is not true then
    raise exception 'evento com falha não foi desfeito';
  end if;
  if public.claim_provider_webhook('woovi', 'evt-falha-1') is not true then
    raise exception 'o reenvio não foi reprocessado';
  end if;
end $$;

do $$
declare
  v_charge uuid := 'f9300000-0000-4000-8000-000000000001';
begin
  if public.claim_provider_refund(
    'woovi', 'E2ELIVRO', 5000, v_charge, 'refund:1', 4000, 'casa@pix'
  ) is distinct from 'refund' then
    raise exception 'o primeiro estorno não pediu a Woovi';
  end if;
  if public.claim_provider_refund(
    'woovi', 'E2ELIVRO', 5000, v_charge, 'refund:1', 4000, 'casa@pix'
  ) is distinct from 'busy' then
    raise exception 'o segundo estorno simultâneo não esperou';
  end if;
  if public.mark_provider_refund_recorded('woovi', 'E2ELIVRO', 5000) is not true then
    raise exception 'o estorno não ficou registrado antes do débito';
  end if;
  if public.claim_provider_refund(
    'woovi', 'E2ELIVRO', 5000, v_charge, 'refund:1', 4000, 'casa@pix'
  ) is distinct from 'debit' then
    raise exception 'a nova tentativa estornaria de novo';
  end if;
  if public.mark_provider_debit_done('woovi', 'E2ELIVRO', 5000) is not true then
    raise exception 'o débito não concluiu';
  end if;
  if public.claim_provider_refund(
    'woovi', 'E2ELIVRO', 5000, v_charge, 'refund:1', 4000, 'casa@pix'
  ) is distinct from 'done' then
    raise exception 'o estorno concluído não ficou idempotente';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'f9222222-2222-4222-8222-222222222222',
  'jogador-livro@example.com',
  '{"display_name":"Jogador Livro"}'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'f9300000-0000-4000-8000-000000000002',
  'f9200000-0000-4000-8000-000000000001',
  'Sala do Livro',
  '',
  4, 2, 60, 'medium', 8000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'f9310000-0000-4000-8000-000000000001',
  'f9300000-0000-4000-8000-000000000002',
  timestamptz '2026-11-12 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'f9400000-0000-4000-8000-000000000001',
  'curitiba',
  'f9200000-0000-4000-8000-000000000001',
  'f9300000-0000-4000-8000-000000000002',
  'f9310000-0000-4000-8000-000000000001',
  timestamptz '2026-11-12 18:00:00+00',
  4, 2, 8000,
  'f9111111-1111-4111-8111-111111111111'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, attendance, payment_status
) values (
  'f9400000-0000-4000-8000-000000000001',
  'f9222222-2222-4222-8222-222222222222',
  'Jogador Livro',
  false,
  'confirmed',
  'paid'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider, provider_ref, idempotency_key, commission_bps, paid_at
) values (
  'f9500000-0000-4000-8000-000000000001',
  'f9400000-0000-4000-8000-000000000001',
  'f9222222-2222-4222-8222-222222222222',
  'f9200000-0000-4000-8000-000000000001',
  8000, 'CREDIT_CARD', 'paid',
  'mercadopago', 'pay_livro', 'idem-livro-cb', 2000,
  timestamptz '2026-11-12 18:05:00+00'
);

insert into public.ledger_entries (
  venue_id, group_id, user_id, account, direction, kind, amount_cents,
  payment_charge_id
) values (
  'f9200000-0000-4000-8000-000000000001',
  'f9400000-0000-4000-8000-000000000001',
  'f9222222-2222-4222-8222-222222222222',
  'house', 'credit', 'house_net', 6400,
  'f9500000-0000-4000-8000-000000000001'
);

do $$
declare
  v_result jsonb;
  v_status text;
  v_refunded timestamptz;
  v_member text;
begin
  v_result := public.apply_payment_transition(
    'f9500000-0000-4000-8000-000000000001',
    'charged_back',
    false
  );
  if v_result ->> 'status' is distinct from 'charged_back' then
    raise exception 'chargeback virou %', v_result ->> 'status';
  end if;
  select status, refunded_at
  into v_status, v_refunded
  from public.payment_charges
  where id = 'f9500000-0000-4000-8000-000000000001';
  if v_status is distinct from 'charged_back' or v_refunded is not null then
    raise exception 'chargeback foi gravado como estorno';
  end if;
  select refund_status into v_member
  from public.group_members
  where group_id = 'f9400000-0000-4000-8000-000000000001'
    and user_id = 'f9222222-2222-4222-8222-222222222222';
  if v_member is distinct from 'none' then
    raise exception 'chargeback marcou o membro como estornado';
  end if;
end $$;

update public.venue_payouts_settings set enabled = false where id = 1;
