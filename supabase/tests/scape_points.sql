-- Cálculo, idempotência, janela de um ano, estorno, antifraude e RLS.
-- Não fala com o Asaas.

\set ON_ERROR_STOP on

-- Os cenários antigos medem a comissão cheia. O desconto de 20% tem teste próprio.
-- Cada cobrança de teste nasce com um pagador verificável e distinto.
-- O caso sem documento fica no teste de estorno.
create or replace function private.test_stamp_payer_hash()
returns trigger
language plpgsql
as $$
begin
  if new.payer_document_hash is null and new.payer_card_key is null then
    new.payer_document_hash := md5(coalesce(new.id, gen_random_uuid())::text)
      || md5(coalesce(new.idempotency_key, 'pagador'));
  end if;
  return new;
end;
$$;

drop trigger if exists test_stamp_payer_hash on public.payment_charges;
create trigger test_stamp_payer_hash
  before insert on public.payment_charges
  for each row execute function private.test_stamp_payer_hash();

update public.referral_program_settings
set first_booking_discount_bps = 0,
    redeem_min_points = 1,
    redeem_max_bps = 10000
where id = 1;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb111111-1111-1111-1111-111111111111',
  'indicador@example.com',
  '{"display_name":"Indicador"}'
);

insert into public.admins (user_id)
values ('bb111111-1111-1111-1111-111111111111');

update public.profiles
set cpf = '52998224725', phone = '41988880010'
where id = 'bb111111-1111-1111-1111-111111111111';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb222222-2222-2222-2222-222222222222',
  'indicado@example.com',
  jsonb_build_object(
    'display_name', 'Indicado',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '39053344705', phone = '41977770020'
where id = 'bb222222-2222-2222-2222-222222222222';

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'bb311111-1111-1111-1111-111111111111',
  'bb111111-1111-1111-1111-111111111111',
  'curitiba',
  'Casa Pontos',
  'Centro',
  'Rua do Ponto',
  '10',
  '80010000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '99888777000166',
  '4133330000',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'bb411111-1111-1111-1111-111111111111',
  'bb311111-1111-1111-1111-111111111111',
  'Sala Pontos',
  '',
  6,
  2,
  60,
  'medium',
  10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'bb511111-1111-1111-1111-111111111111',
  'bb411111-1111-1111-1111-111111111111',
  '2027-08-01 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'bb611111-1111-1111-1111-111111111111',
  'curitiba',
  'bb311111-1111-1111-1111-111111111111',
  'bb411111-1111-1111-1111-111111111111',
  'bb511111-1111-1111-1111-111111111111',
  '2027-08-01 18:00:00+00',
  4,
  2,
  10000,
  'bb222222-2222-2222-2222-222222222222'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bb611111-1111-1111-1111-111111111111',
  'bb222222-2222-2222-2222-222222222222',
  'Indicado',
  true,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps
) values (
  'bb711111-1111-1111-1111-111111111111',
  'bb611111-1111-1111-1111-111111111111',
  'bb222222-2222-2222-2222-222222222222',
  'bb311111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'pending',
  'pay_points',
  'idem-points-c2c',
  2500
);

do $$
declare
  v_pending integer;
  v_available integer;
  v_house integer;
  v_fee integer;
  v_count integer;
begin
  if not exists (
    select 1 from public.referral_attributions
    where subject_user_id = 'bb222222-2222-2222-2222-222222222222'
      and referrer_user_id = 'bb111111-1111-1111-1111-111111111111'
      and status = 'active'
      and ends_at = starts_at + interval '365 days'
  ) then
    raise exception 'atribuicao C2C nao nasceu no cadastro';
  end if;

  perform private.record_payer_document_status(
    'bb711111-1111-1111-1111-111111111111',
    'matched'
  );
  perform private.apply_payment_transition(
    'bb711111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  perform private.post_referral_rewards('bb711111-1111-1111-1111-111111111111');

  select count(*) into v_count
  from public.scape_point_entries
  where source_charge_id = 'bb711111-1111-1111-1111-111111111111'
    and kind = 'accrual';
  if v_count <> 2 then
    raise exception 'lancamento duplicou ou faltou o cashback: %', v_count;
  end if;
  if not private.cashback_points_ok('bb711111-1111-1111-1111-111111111111') then
    raise exception 'cashback sorteado nao entrou';
  end if;

  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances('bb111111-1111-1111-1111-111111111111');
  if v_pending <> 250 or v_available <> 0 then
    raise exception 'saldo pendente inesperado % / %', v_pending, v_available;
  end if;

  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = 'bb711111-1111-1111-1111-111111111111'
    and kind = 'house_net';
  select amount_cents into v_fee
  from public.ledger_entries
  where payment_charge_id = 'bb711111-1111-1111-1111-111111111111'
    and kind = 'commission';
  if v_house <> 7500 or v_fee <> 2500 then
    raise exception 'a casa nao ficou com o liquido % / %', v_house, v_fee;
  end if;
end $$;

do $$
declare
  v_pending integer;
  v_available integer;
begin
  perform private.release_due_scape_points('2026-06-01 00:00:00+00');
  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances('bb111111-1111-1111-1111-111111111111');
  if v_pending <> 250 or v_available <> 0 then
    raise exception 'liberou antes dos 30 dias';
  end if;

  perform private.release_due_scape_points(pg_catalog.now() + interval '31 days');
  perform private.release_due_scape_points(pg_catalog.now() + interval '31 days');
  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances('bb111111-1111-1111-1111-111111111111');
  if v_pending <> 0 or v_available <> 250 then
    raise exception 'liberacao nao idempotente % / %', v_pending, v_available;
  end if;
  if (
    select count(*) from public.scape_point_entries
    where kind = 'release'
      and user_id = 'bb111111-1111-1111-1111-111111111111'
  ) <> 1 then
    raise exception 'duas liberacoes';
  end if;
end $$;

do $$
declare
  v_available integer;
begin
  perform private.apply_payment_transition(
    'bb711111-1111-1111-1111-111111111111',
    'refunded',
    false
  );
  perform private.reverse_referral_rewards('bb711111-1111-1111-1111-111111111111');
  select available_points into v_available
  from private.scape_balances('bb111111-1111-1111-1111-111111111111');
  if v_available <> 0 then
    raise exception 'estorno nao zerou o saldo %', v_available;
  end if;
  if (
    select count(*) from public.scape_point_entries
    where kind = 'reversal'
      and user_id = 'bb111111-1111-1111-1111-111111111111'
  ) <> 1 then
    raise exception 'estorno duplicou ou faltou';
  end if;
  if (
    select count(*) from public.scape_point_entries
    where kind = 'reversal'
      and program = 'cashback'
      and user_id = 'bb222222-2222-2222-2222-222222222222'
  ) <> 1 then
    raise exception 'o cashback nao foi estornado';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb333333-3333-3333-3333-333333333333',
  'fora@example.com',
  jsonb_build_object(
    'display_name', 'Fora',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '15350946056'
where id = 'bb333333-3333-3333-3333-333333333333';

update public.referral_attributions
set
  starts_at = pg_catalog.now() - interval '400 days',
  ends_at = pg_catalog.now() - interval '35 days'
where subject_user_id = 'bb333333-3333-3333-3333-333333333333';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bb611111-1111-1111-1111-111111111111',
  'bb333333-3333-3333-3333-333333333333',
  'Fora',
  false,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, paid_at
) values (
  'bb811111-1111-1111-1111-111111111111',
  'bb611111-1111-1111-1111-111111111111',
  'bb333333-3333-3333-3333-333333333333',
  'bb311111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'paid',
  'pay_late',
  'idem-points-late',
  2500,
  pg_catalog.now()
);

do $$
begin
  perform private.post_referral_rewards('bb811111-1111-1111-1111-111111111111');
  if exists (
    select 1 from public.scape_point_entries
    where source_charge_id = 'bb811111-1111-1111-1111-111111111111'
      and kind = 'accrual'
      and program is distinct from 'cashback'
  ) then
    raise exception 'pagou fora da janela de um ano';
  end if;
  if not private.cashback_points_ok('bb811111-1111-1111-1111-111111111111') then
    raise exception 'cashback nao entrou fora da indicacao';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb444444-4444-4444-4444-444444444444',
  'gemeo@example.com',
  jsonb_build_object(
    'display_name', 'Gemeo',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '52998224725'
where id = 'bb444444-4444-4444-4444-444444444444';

do $$
declare
  v_status text;
begin
  delete from public.referral_attributions
  where subject_user_id = 'bb444444-4444-4444-4444-444444444444';
  perform private.attach_referral(
    'player',
    'bb444444-4444-4444-4444-444444444444',
    null,
    (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    ),
    false
  );
  select status into v_status
  from public.referral_attributions
  where subject_user_id = 'bb444444-4444-4444-4444-444444444444';
  if v_status <> 'blocked' then
    raise exception 'CPF igual nao bloqueou: %', v_status;
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb000000-0000-0000-0000-000000000000',
  'outro-indicador@example.com',
  '{"display_name":"Outro indicador"}'
);

update public.profiles
set cpf = '19100000000'
where id = 'bb000000-0000-0000-0000-000000000000';

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb555555-5555-5555-5555-555555555555',
  'pagador@example.com',
  jsonb_build_object(
    'display_name', 'Pagador',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
    )
  )
);

update public.profiles
set cpf = '15350946056'
where id = 'bb555555-5555-5555-5555-555555555555';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bb611111-1111-1111-1111-111111111111',
  'bb555555-5555-5555-5555-555555555555',
  'Pagador',
  false,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps
) values (
  'bb911111-1111-1111-1111-111111111111',
  'bb611111-1111-1111-1111-111111111111',
  'bb555555-5555-5555-5555-555555555555',
  'bb311111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'pending',
  'pay_unverified',
  'idem-points-unverified',
  2500
);

do $$
declare
  v_house integer;
begin
  perform private.record_payer_document_status(
    'bb911111-1111-1111-1111-111111111111',
    'unverified'
  );
  perform private.apply_payment_transition(
    'bb911111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bb911111-1111-1111-1111-111111111111'
      and kind = 'accrual'
      and program = 'c2c'
  ) is distinct from 250 then
    raise exception 'pagamento por terceiro nao liberou a indicacao';
  end if;
  if not private.cashback_points_ok('bb911111-1111-1111-1111-111111111111') then
    raise exception 'cashback nao entrou sem indicacao conferida';
  end if;
  if exists (
    select 1 from public.referral_withholdings
    where payment_charge_id = 'bb911111-1111-1111-1111-111111111111'
  ) then
    raise exception 'nao verificado virou bloqueio definitivo';
  end if;
  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = 'bb911111-1111-1111-1111-111111111111'
    and kind = 'house_net';
  if v_house is distinct from 7500 then
    raise exception 'a reserva parou sem o CPF do pagador';
  end if;

  if private.record_payer_document_status(
    'bb911111-1111-1111-1111-111111111111',
    'matched'
  ) is distinct from 'matched' then
    raise exception 'nao promoveu documento verificado';
  end if;
  perform private.post_referral_rewards('bb911111-1111-1111-1111-111111111111');
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bb911111-1111-1111-1111-111111111111'
      and kind = 'accrual'
      and program = 'c2c'
  ) is distinct from 250 then
    raise exception 'depois de conferir o CPF a recompensa nao entrou';
  end if;
  if private.referral_benefit_allowed(
    'bb911111-1111-1111-1111-111111111111'
  ) is not true then
    raise exception 'desconto de indicacao continuaria bloqueado';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bb666666-6666-6666-6666-666666666666',
  'outro-cartao@example.com',
  jsonb_build_object(
    'display_name', 'Outro cartao',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
    )
  )
);

update public.profiles
set cpf = '11144477735'
where id = 'bb666666-6666-6666-6666-666666666666';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bb611111-1111-1111-1111-111111111111',
  'bb666666-6666-6666-6666-666666666666',
  'Outro cartao',
  false,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps
) values (
  'bba11111-1111-1111-1111-111111111111',
  'bb611111-1111-1111-1111-111111111111',
  'bb666666-6666-6666-6666-666666666666',
  'bb311111-1111-1111-1111-111111111111',
  8000,
  'CREDIT_CARD',
  'pending',
  'pay_mismatch',
  'idem-points-mismatch',
  2500
);

do $$
declare
  v_house integer;
begin
  perform private.record_payer_document_status(
    'bba11111-1111-1111-1111-111111111111',
    'mismatch'
  );
  perform private.apply_payment_transition(
    'bba11111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bba11111-1111-1111-1111-111111111111'
      and kind = 'accrual'
      and program = 'c2c'
  ) is distinct from 200 then
    raise exception 'cartao de terceiro nao liberou a indicacao';
  end if;
  if not private.cashback_points_ok('bba11111-1111-1111-1111-111111111111') then
    raise exception 'cashback de terceiro nao entrou';
  end if;
  if exists (
    select 1 from public.referral_withholdings
    where payment_charge_id = 'bba11111-1111-1111-1111-111111111111'
      and reason = 'payer_cpf_mismatch'
  ) then
    raise exception 'CPF diferente ainda barrou a indicacao';
  end if;
  if private.referral_benefit_allowed(
    'bba11111-1111-1111-1111-111111111111'
  ) is not true then
    raise exception 'pagamento de terceiro nao liberou o desconto';
  end if;
  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = 'bba11111-1111-1111-1111-111111111111'
    and kind = 'house_net';
  if v_house is distinct from 6000 then
    raise exception 'a casa nao recebeu o liquido com CPF diferente %', v_house;
  end if;
end $$;

do $$
declare
  v_quote jsonb;
  v_reserved jsonb;
  v_house integer;
  v_fee integer;
  v_available integer;
begin
  update public.scape_point_entries
  set available_at = pg_catalog.now() - interval '1 day'
  where user_id = 'bb111111-1111-1111-1111-111111111111'
    and kind = 'accrual';
  delete from public.scape_point_entries
  where user_id = 'bb111111-1111-1111-1111-111111111111'
    and kind = 'reversal';
  perform private.release_due_scape_points(pg_catalog.now());

  v_quote := private.hold_point_redemption(
    'bb111111-1111-1111-1111-111111111111',
    'idem-subsidio-pontos',
    10000,
    2500,
    1000
  );
  if (v_quote ->> 'points')::integer <> 250
    or (v_quote ->> 'charged_cents')::integer <> 9750
    or (v_quote ->> 'house_net_cents')::integer <> 7500
  then
    raise exception 'quote de abatimento inesperada %', v_quote;
  end if;

  v_reserved := private.reserve_pix_charge(
    'bb611111-1111-1111-1111-111111111111',
    'bb111111-1111-1111-1111-111111111111',
    'bb311111-1111-1111-1111-111111111111',
    (v_quote ->> 'charged_cents')::integer,
    'idem-subsidio-pontos',
    'wal_house',
    2500,
    (v_quote ->> 'gross_cents')::integer,
    (v_quote ->> 'subsidy_cents')::integer,
    (v_quote ->> 'points')::integer,
    (v_quote ->> 'split_percent')::numeric
  );
  if (v_reserved ->> 'split_percent')::numeric <> 76.9231 then
    raise exception 'split nao devolve o liquido %', v_reserved;
  end if;

  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'bb611111-1111-1111-1111-111111111111',
    'bb111111-1111-1111-1111-111111111111',
    'Indicador',
    false,
    'pending',
    'none',
    'none'
  );

  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid,
    'paid',
    true
  );
  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = (v_reserved ->> 'id')::uuid
    and kind = 'house_net';
  select amount_cents into v_fee
  from public.ledger_entries
  where payment_charge_id = (v_reserved ->> 'id')::uuid
    and kind = 'commission';
  if v_house <> 7500 or v_fee <> 2250 then
    raise exception 'abatimento comeu a casa % / %', v_house, v_fee;
  end if;
  select available_points into v_available
  from private.scape_balances('bb111111-1111-1111-1111-111111111111');
  if v_available <> 0 then
    raise exception 'os pontos usados continuaram no saldo %', v_available;
  end if;
end $$;

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'bb321111-1111-1111-1111-111111111111',
  'bb000000-0000-0000-0000-000000000000',
  'curitiba',
  'Casa que indicou',
  'Batel',
  'Rua da Indicação',
  '20',
  '80420000',
  -25.44,
  -49.29,
  4000,
  'cnpj',
  '88777666000155',
  '4133330011',
  'approved'
);

insert into public.referral_attributions (
  subject_kind, subject_venue_id, referrer_kind, referrer_venue_id,
  code, starts_at, ends_at, status
)
select
  'venue',
  'bb311111-1111-1111-1111-111111111111',
  'venue',
  'bb321111-1111-1111-1111-111111111111',
  code,
  pg_catalog.now() - interval '10 days',
  pg_catalog.now() + interval '355 days',
  'active'
from public.referral_codes
where owner_venue_id = 'bb321111-1111-1111-1111-111111111111';

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'bb777777-7777-7777-7777-777777777777',
    'primeira@example.com',
    '{"display_name":"Primeira"}'
  ),
  (
    'bb888888-8888-8888-8888-888888888888',
    'seguinte@example.com',
    '{"display_name":"Seguinte"}'
  );

update public.profiles
set cpf = '15350946056'
where id = 'bb777777-7777-7777-7777-777777777777';

update public.profiles
set cpf = '11144477735'
where id = 'bb888888-8888-8888-8888-888888888888';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values
  (
    'bb611111-1111-1111-1111-111111111111',
    'bb777777-7777-7777-7777-777777777777',
    'Primeira',
    false,
    'pending',
    'none',
    'none'
  ),
  (
    'bb611111-1111-1111-1111-111111111111',
    'bb888888-8888-8888-8888-888888888888',
    'Seguinte',
    false,
    'pending',
    'none',
    'none'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, payer_document_status,
  first_booking_discount_cents
) values
  (
    'bbc11111-1111-1111-1111-111111111111',
    'bb611111-1111-1111-1111-111111111111',
    'bb777777-7777-7777-7777-777777777777',
    'bb311111-1111-1111-1111-111111111111',
    10000,
    'PIX',
    'pending',
    'pay_b2b_discount',
    'idem-b2b-discount',
    2500,
    'matched',
    2000
  );

do $$
declare
  v_cents integer;
begin
  perform private.apply_payment_transition(
    'bbc11111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  if exists (
    select 1 from public.venue_referral_entries
    where source_charge_id = 'bbc11111-1111-1111-1111-111111111111'
      and program = 'b2b'
      and kind = 'accrual'
  ) then
    raise exception 'B2B entrou na reserva com desconto de primeira reserva';
  end if;
end $$;

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'bbe11111-1111-1111-1111-111111111111',
  'curitiba',
  'bb311111-1111-1111-1111-111111111111',
  'bb411111-1111-1111-1111-111111111111',
  'bb511111-1111-1111-1111-111111111111',
  '2027-09-01 18:00:00+00',
  4,
  2,
  10000,
  'bb777777-7777-7777-7777-777777777777'
);

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values
  (
    'bbe11111-1111-1111-1111-111111111111',
    'bb777777-7777-7777-7777-777777777777',
    'Primeira',
    true,
    'pending',
    'none',
    'none'
  ),
  (
    'bbe11111-1111-1111-1111-111111111111',
    'bb888888-8888-8888-8888-888888888888',
    'Seguinte',
    false,
    'pending',
    'none',
    'none'
  );

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, payer_document_status,
  first_booking_discount_cents
) values
  (
    'bbf11111-1111-1111-1111-111111111111',
    'bbe11111-1111-1111-1111-111111111111',
    'bb777777-7777-7777-7777-777777777777',
    'bb311111-1111-1111-1111-111111111111',
    10000,
    'PIX',
    'pending',
    'pay_b2b_again',
    'idem-b2b-again',
    2500,
    'matched',
    0
  ),
  (
    'bc011111-1111-1111-1111-111111111111',
    'bbe11111-1111-1111-1111-111111111111',
    'bb888888-8888-8888-8888-888888888888',
    'bb311111-1111-1111-1111-111111111111',
    10000,
    'PIX',
    'pending',
    'pay_b2b_other',
    'idem-b2b-other',
    2500,
    'matched',
    0
  );

do $$
begin
  perform private.apply_payment_transition(
    'bbf11111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  perform private.apply_payment_transition(
    'bc011111-1111-1111-1111-111111111111',
    'paid',
    true
  );
  if (
    select amount_cents from public.venue_referral_entries
    where source_charge_id = 'bbf11111-1111-1111-1111-111111111111'
      and program = 'b2b' and kind = 'accrual'
  ) is distinct from 500 then
    raise exception 'a volta do mesmo cliente nao gerou B2B';
  end if;
  if (
    select amount_cents from public.venue_referral_entries
    where source_charge_id = 'bc011111-1111-1111-1111-111111111111'
      and program = 'b2b' and kind = 'accrual'
  ) is distinct from 500 then
    raise exception 'outro cliente nao gerou B2B';
  end if;
end $$;

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'bd611111-1111-4111-8111-111111111111',
  'curitiba',
  'bb311111-1111-1111-1111-111111111111',
  'bb411111-1111-1111-1111-111111111111',
  'bb511111-1111-1111-1111-111111111111',
  '2027-10-15 18:00:00+00',
  8,
  2,
  10000,
  'bb111111-1111-1111-1111-111111111111'
);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bd511111-1111-4111-8111-111111111115',
  'filho@example.com',
  jsonb_build_object(
    'display_name', 'Filho',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '00240289838'
where id = 'bd511111-1111-4111-8111-111111111115';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bd611111-1111-4111-8111-111111111111',
  'bd511111-1111-4111-8111-111111111115',
  'Filho',
  true,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, payer_document_hash
) values (
  'bd711111-1111-4111-8111-111111111115',
  'bd611111-1111-4111-8111-111111111111',
  'bd511111-1111-4111-8111-111111111115',
  'bb311111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'pending',
  'pay_self',
  'idem-payer-self',
  2500,
  private.document_hash('52998224725')
);

do $$
begin
  if private.document_hash('529.982.247-25') is distinct from
    '7281dfb5e8becca0a1c5e77c1268baacb0f983572b8c204fd8df72b24175b231'
  then
    raise exception 'hash do documento divergiu do SHA-256';
  end if;
  perform private.apply_payment_transition(
    'bd711111-1111-4111-8111-111111111115',
    'paid',
    true
  );
  if exists (
    select 1 from public.scape_point_entries
    where source_charge_id = 'bd711111-1111-4111-8111-111111111115'
      and program = 'c2c' and kind = 'accrual'
  ) then
    raise exception 'pagador indicador ainda ganhou C2C';
  end if;
  if not private.cashback_points_ok('bd711111-1111-4111-8111-111111111115') then
    raise exception 'cashback saiu junto com a trava do pagador';
  end if;
  if not exists (
    select 1 from public.referral_withholdings
    where payment_charge_id = 'bd711111-1111-4111-8111-111111111115'
      and reason = 'payer_is_referrer'
      and program = 'c2c'
  ) then
    raise exception 'nao registrou pagador indicador';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'bd111111-1111-4111-8111-111111111111',
    'cap1@example.com',
    jsonb_build_object(
      'display_name', 'Cap Um',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
      )
    )
  ),
  (
    'bd222222-2222-4222-8222-222222222222',
    'cap2@example.com',
    jsonb_build_object(
      'display_name', 'Cap Dois',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
      )
    )
  ),
  (
    'bd333333-3333-4333-8333-333333333333',
    'cap3@example.com',
    jsonb_build_object(
      'display_name', 'Cap Tres',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
      )
    )
  ),
  (
    'bd444444-4444-4444-8444-444444444444',
    'cap4@example.com',
    jsonb_build_object(
      'display_name', 'Cap Quatro',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb000000-0000-0000-0000-000000000000'
      )
    )
  );

update public.profiles set cpf = '04153389056'
where id = 'bd111111-1111-4111-8111-111111111111';
update public.profiles set cpf = '17301662378'
where id = 'bd222222-2222-4222-8222-222222222222';
update public.profiles set cpf = '44251803051'
where id = 'bd333333-3333-4333-8333-333333333333';
update public.profiles set cpf = '47890507348'
where id = 'bd444444-4444-4444-8444-444444444444';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values
  ('bd611111-1111-4111-8111-111111111111', 'bd111111-1111-4111-8111-111111111111', 'Cap Um', false, 'pending', 'none', 'none'),
  ('bd611111-1111-4111-8111-111111111111', 'bd222222-2222-4222-8222-222222222222', 'Cap Dois', false, 'pending', 'none', 'none'),
  ('bd611111-1111-4111-8111-111111111111', 'bd333333-3333-4333-8333-333333333333', 'Cap Tres', false, 'pending', 'none', 'none'),
  ('bd611111-1111-4111-8111-111111111111', 'bd444444-4444-4444-8444-444444444444', 'Cap Quatro', false, 'pending', 'none', 'none');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'bd311111-1111-4111-8111-111111111111',
  'bb000000-0000-0000-0000-000000000000',
  'curitiba',
  'Casa sem indicacao',
  'Centro',
  'Rua sem codigo',
  '30',
  '80020000',
  -25.42,
  -49.25,
  3000,
  'cnpj',
  '25092680453952',
  '4133330022',
  'approved'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps, payer_card_key
) values
  ('bd811111-1111-4111-8111-111111111111', 'bd611111-1111-4111-8111-111111111111', 'bd111111-1111-4111-8111-111111111111', 'bd311111-1111-4111-8111-111111111111', 10000, 'CREDIT_CARD', 'pending', 'pay_cap1', 'idem-cap-1', 2500, 'visa:1111'),
  ('bd822222-2222-4222-8222-222222222222', 'bd611111-1111-4111-8111-111111111111', 'bd222222-2222-4222-8222-222222222222', 'bd311111-1111-4111-8111-111111111111', 10000, 'CREDIT_CARD', 'pending', 'pay_cap2', 'idem-cap-2', 2500, 'visa:1111'),
  ('bd833333-3333-4333-8333-333333333333', 'bd611111-1111-4111-8111-111111111111', 'bd333333-3333-4333-8333-333333333333', 'bd311111-1111-4111-8111-111111111111', 10000, 'CREDIT_CARD', 'pending', 'pay_cap3', 'idem-cap-3', 2500, 'visa:1111'),
  ('bd844444-4444-4444-8444-444444444444', 'bd611111-1111-4111-8111-111111111111', 'bd444444-4444-4444-8444-444444444444', 'bd311111-1111-4111-8111-111111111111', 10000, 'CREDIT_CARD', 'pending', 'pay_cap4', 'idem-cap-4', 2500, 'visa:1111');

do $$
begin
  perform private.apply_payment_transition('bd811111-1111-4111-8111-111111111111', 'paid', true);
  perform private.apply_payment_transition('bd822222-2222-4222-8222-222222222222', 'paid', true);
  perform private.apply_payment_transition('bd833333-3333-4333-8333-333333333333', 'paid', true);
  perform private.apply_payment_transition('bd844444-4444-4444-8444-444444444444', 'paid', true);
  if (
    select count(*) from public.scape_point_entries
    where program = 'c2c' and kind = 'accrual'
      and source_charge_id in (
        'bd811111-1111-4111-8111-111111111111',
        'bd822222-2222-4222-8222-222222222222',
        'bd833333-3333-4333-8333-333333333333'
      )
  ) <> 3 then
    raise exception 'as tres primeiras contas do pagador nao premiaram';
  end if;
  if exists (
    select 1 from public.scape_point_entries
    where source_charge_id = 'bd844444-4444-4444-8444-444444444444'
      and program = 'c2c' and kind = 'accrual'
  ) then
    raise exception 'a quarta conta do mesmo pagador ainda premiou';
  end if;
  if not private.cashback_points_ok('bd844444-4444-4444-8444-444444444444') then
    raise exception 'o teto do pagador comeu o cashback';
  end if;
  if not exists (
    select 1 from public.referral_withholdings
    where payment_charge_id = 'bd844444-4444-4444-8444-444444444444'
      and reason = 'payer_account_cap'
  ) then
    raise exception 'nao registrou o teto de contas do pagador';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'bd666666-6666-4666-8666-666666666666',
  'aparelho1@example.com',
  jsonb_build_object(
    'display_name', 'Aparelho Um',
    'device_install_id', '11111111-1111-4111-8111-111111111111',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '95190826708'
where id = 'bd666666-6666-4666-8666-666666666666';

insert into public.group_members (
  group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
) values (
  'bd611111-1111-4111-8111-111111111111',
  'bd666666-6666-4666-8666-666666666666',
  'Aparelho Um',
  false,
  'pending',
  'none',
  'none'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  provider_ref, idempotency_key, commission_bps
) values (
  'bd911111-1111-4111-8111-111111111111',
  'bd611111-1111-4111-8111-111111111111',
  'bd666666-6666-4666-8666-666666666666',
  'bb311111-1111-1111-1111-111111111111',
  10000,
  'PIX',
  'pending',
  'pay_device1',
  'idem-device-1',
  2500
);

do $$
declare
  v_review uuid;
  v_second uuid;
begin
  perform private.apply_payment_transition(
    'bd911111-1111-4111-8111-111111111111', 'paid', true
  );
  if (
    select review_status from public.scape_point_entries
    where source_charge_id = 'bd911111-1111-4111-8111-111111111111'
      and program = 'c2c' and kind = 'accrual'
  ) is not null then
    raise exception 'uma conta so foi para revisao';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'bd777777-7777-4777-8777-777777777777',
    'aparelho2@example.com',
    jsonb_build_object(
      'display_name', 'Aparelho Dois',
      'device_install_id', '11111111-1111-4111-8111-111111111111',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
      )
    )
  );
  update public.profiles
  set cpf = '46834757406'
  where id = 'bd777777-7777-4777-8777-777777777777';

  if (
    select review_status from public.scape_point_entries
    where source_charge_id = 'bd911111-1111-4111-8111-111111111111'
      and program = 'c2c' and kind = 'accrual'
  ) is distinct from 'em_revisao' then
    raise exception 'a segunda conta no aparelho nao segurou a primeira';
  end if;

  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'bd611111-1111-4111-8111-111111111111',
    'bd777777-7777-4777-8777-777777777777',
    'Aparelho Dois',
    false,
    'pending',
    'none',
    'none'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider_ref, idempotency_key, commission_bps
  ) values (
    'bd922222-2222-4222-8222-222222222222',
    'bd611111-1111-4111-8111-111111111111',
    'bd777777-7777-4777-8777-777777777777',
    'bb311111-1111-1111-1111-111111111111',
    10000,
    'PIX',
    'pending',
    'pay_device2',
    'idem-device-2',
    2500
  );
  perform private.apply_payment_transition(
    'bd922222-2222-4222-8222-222222222222', 'paid', true
  );
  select id into v_second
  from public.scape_point_entries
  where source_charge_id = 'bd922222-2222-4222-8222-222222222222'
    and program = 'c2c' and kind = 'accrual';
  if (
    select review_status from public.scape_point_entries where id = v_second
  ) is distinct from 'em_revisao' then
    raise exception 'a segunda recompensa nao ficou em revisao';
  end if;
  if (
    select review_status from public.scape_point_entries
    where source_charge_id = 'bd922222-2222-4222-8222-222222222222'
      and program = 'cashback' and kind = 'accrual'
  ) is not null then
    raise exception 'o cashback entrou na revisao';
  end if;

  update public.scape_point_entries
  set available_at = pg_catalog.now() - interval '1 day'
  where source_charge_id in (
    'bd911111-1111-4111-8111-111111111111',
    'bd922222-2222-4222-8222-222222222222'
  );
  perform private.release_due_scape_points(pg_catalog.now());
  if exists (
    select 1 from public.scape_point_entries
    where relates_to in (
      select id from public.scape_point_entries
      where source_charge_id = 'bd911111-1111-4111-8111-111111111111'
        and program = 'c2c' and kind = 'accrual'
    )
      and kind = 'release'
  ) then
    raise exception 'revisao liberou sozinha';
  end if;
  if not exists (
    select 1 from public.scape_point_entries
    where source_charge_id = 'bd911111-1111-4111-8111-111111111111'
      and program = 'cashback' and kind = 'release'
  ) then
    raise exception 'o cashback da revisao nao liberou';
  end if;

  select id into v_review
  from public.scape_point_entries
  where source_charge_id = 'bd911111-1111-4111-8111-111111111111'
    and program = 'c2c' and kind = 'accrual';
  perform set_config(
    'request.jwt.claim.sub',
    'bb111111-1111-1111-1111-111111111111',
    true
  );
  perform public.admin_decide_referral_review(v_review, 'points', 'approve');
  perform public.admin_decide_referral_review(v_second, 'points', 'reject');
  if (
    select review_status from public.scape_point_entries where id = v_review
  ) is distinct from 'approved' then
    raise exception 'aprovar nao saiu da revisao';
  end if;
  if not exists (
    select 1 from public.scape_point_entries
    where relates_to = v_review and kind = 'release'
  ) then
    raise exception 'aprovar nao liberou o ponto vencido';
  end if;
  if not exists (
    select 1 from public.scape_point_entries
    where relates_to = v_second and kind = 'reversal'
  ) then
    raise exception 'recusar nao estornou';
  end if;
end $$;

update public.referral_program_settings
set first_booking_discount_bps = 2000
where id = 1;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'be111111-1111-4111-8111-111111111111',
  'primeira@example.com',
  jsonb_build_object(
    'display_name', 'Primeira',
    'phone', '41999990001',
    'referral_code', (
      select code from public.referral_codes
      where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
    )
  )
);

update public.profiles
set cpf = '39053344705'
where id = 'be111111-1111-4111-8111-111111111111'
  and cpf is null;

do $$
declare
  v_reserved jsonb;
  v_house integer;
  v_fee integer;
  v_second jsonb;
begin
  if (
    select phone from public.profiles
    where id = 'be111111-1111-4111-8111-111111111111'
  ) is distinct from '41999990001' then
    raise exception 'telefone do cadastro nao entrou no perfil';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be611111-1111-4111-8111-111111111111',
    'curitiba',
    'bd311111-1111-4111-8111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-11-01 18:00:00+00',
    4,
    2,
    10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'be611111-1111-4111-8111-111111111111',
    'be111111-1111-4111-8111-111111111111',
    'Primeira',
    true,
    'pending',
    'none',
    'none'
  );

  v_reserved := private.reserve_pix_charge(
    'be611111-1111-4111-8111-111111111111',
    'be111111-1111-4111-8111-111111111111',
    'bd311111-1111-4111-8111-111111111111',
    10000,
    'idem-primeira-reserva',
    'wal_house',
    2500
  );
  if (v_reserved ->> 'amount_cents')::integer <> 8000
    or (
      select first_booking_discount_cents
      from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 2000
  then
    raise exception 'desconto de 20%% nao saiu da comissao %', v_reserved;
  end if;

  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'paid', true
  );
  select amount_cents into v_house
  from public.ledger_entries
  where payment_charge_id = (v_reserved ->> 'id')::uuid
    and kind = 'house_net';
  select amount_cents into v_fee
  from public.ledger_entries
  where payment_charge_id = (v_reserved ->> 'id')::uuid
    and kind = 'commission';
  if v_house <> 7500 or v_fee <> 500 then
    raise exception 'a casa nao ficou com o liquido no desconto % / %', v_house, v_fee;
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be622222-2222-4222-8222-222222222222',
    'curitiba',
    'bd311111-1111-4111-8111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-11-02 18:00:00+00',
    4,
    2,
    10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'be622222-2222-4222-8222-222222222222',
    'be111111-1111-4111-8111-111111111111',
    'Primeira',
    true,
    'pending',
    'none',
    'none'
  );
  v_second := private.reserve_pix_charge(
    'be622222-2222-4222-8222-222222222222',
    'be111111-1111-4111-8111-111111111111',
    'bd311111-1111-4111-8111-111111111111',
    10000,
    'idem-segunda-reserva',
    'wal_house',
    2500
  );
  if (v_second ->> 'amount_cents')::integer <> 10000 then
    raise exception 'a segunda reserva repetiu o desconto %', v_second;
  end if;
end $$;

insert into public.venue_referral_entries (
  venue_id, kind, amount_cents, program, idempotency_key, settlement, available_at
) values (
  'bd311111-1111-4111-8111-111111111111',
  'accrual',
  400,
  'b2c',
  'idem-credito-casa',
  'pending',
  pg_catalog.now() - interval '1 day'
);

do $$
declare
  v_reserved jsonb;
  v_credit integer;
begin
  perform private.release_due_venue_credits(pg_catalog.now());
  if (
    select settlement from public.venue_referral_entries
    where idempotency_key = 'idem-credito-casa'
  ) is distinct from 'released' then
    raise exception 'credito da casa nao liberou em 30 dias';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'be222222-2222-4222-8222-222222222222',
    'semcodigo@example.com',
    '{"display_name":"Sem codigo"}'
  );
  update public.profiles
  set cpf = '15350946056'
  where id = 'be222222-2222-4222-8222-222222222222';
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be633333-3333-4333-8333-333333333333',
    'curitiba',
    'bd311111-1111-4111-8111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-11-03 18:00:00+00',
    4,
    2,
    10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'be633333-3333-4333-8333-333333333333',
    'be222222-2222-4222-8222-222222222222',
    'Sem codigo',
    true,
    'pending',
    'none',
    'none'
  );
  v_reserved := private.reserve_pix_charge(
    'be633333-3333-4333-8333-333333333333',
    'be222222-2222-4222-8222-222222222222',
    'bd311111-1111-4111-8111-111111111111',
    10000,
    'idem-repasse-credito',
    'wal_house',
    2500
  );
  select venue_credit_applied_cents into v_credit
  from public.payment_charges
  where id = (v_reserved ->> 'id')::uuid;
  if v_credit <> 400 then
    raise exception 'credito da casa nao entrou no split %', v_reserved;
  end if;
  if (
    select settlement from public.venue_referral_entries
    where idempotency_key = 'idem-credito-casa'
  ) is distinct from 'applied' then
    raise exception 'credito da casa ficou liberado depois do repasse';
  end if;
  perform private.apply_payment_transition(
    (v_reserved ->> 'id')::uuid, 'paid', true
  );
  if (
    select amount_cents from public.ledger_entries
    where payment_charge_id = (v_reserved ->> 'id')::uuid
      and kind = 'venue_credit_applied'
  ) is distinct from 400 then
    raise exception 'livro nao recebeu o repasse do credito';
  end if;
  if (
    select amount_cents from public.ledger_entries
    where payment_charge_id = (v_reserved ->> 'id')::uuid
      and kind = 'house_net'
  ) is distinct from 7500 then
    raise exception 'repasse do credito mudou o liquido da reserva';
  end if;
end $$;

update public.referral_program_settings
set redeem_min_points = 1000,
    redeem_max_bps = 3000,
    welcome_points = 100
where id = 1;

do $$
declare
  v_quote jsonb;
  v_bonus integer;
begin
  perform private.grant_welcome_points('be222222-2222-4222-8222-222222222222');
  perform private.grant_welcome_points('be222222-2222-4222-8222-222222222222');
  if (
    select count(*) from public.scape_point_entries
    where user_id = 'be222222-2222-4222-8222-222222222222'
      and program = 'welcome'
      and kind = 'release'
  ) <> 1 then
    raise exception 'boas-vindas duplicou ou nao entrou';
  end if;
  v_quote := private.subsidy_quote(
    'be222222-2222-4222-8222-222222222222', 10000, 2500, 5000, false
  );
  if (v_quote ->> 'points')::integer <> 0 then
    raise exception 'menos de 1000 pontos ainda resgata %', v_quote;
  end if;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'be222222-2222-4222-8222-222222222222',
    'release', 4000, 4000, 'welcome', 'teste-saldo-resgate'
  );
  v_quote := private.subsidy_quote(
    'be222222-2222-4222-8222-222222222222', 10000, 10000, 9000, false
  );
  if (v_quote ->> 'points')::integer <> 3000 then
    raise exception 'teto de 30%% nao segurou o resgate %', v_quote;
  end if;
  if private.referrer_tier_bonus('be222222-2222-4222-8222-222222222222') <> 0 then
    raise exception 'conta sem indicado nao ficou no bronze';
  end if;
  v_bonus := private.referrer_tier_bonus('bb111111-1111-1111-1111-111111111111');
  if v_bonus not in (0, 50, 100) then
    raise exception 'bonus de nivel inesperado %', v_bonus;
  end if;
end $$;

-- Cotação e cap usam a mesma conta. Pontos, desconto, crédito e débito
-- não se apagam quando a cobrança não consegue absorver.
do $$
declare
  v_cap integer;
  v_quote jsonb;
  v_held jsonb;
  v_reserved jsonb;
  v_id uuid;
  v_again integer;
  v_c2c integer;
  v_weekday integer;
  v_paid timestamptz := timestamptz '2026-11-09 15:00:00+00';
begin
  insert into public.venue_commissions (venue_id, commission_bps, updated_by)
  values (
    'bb311111-1111-1111-1111-111111111111',
    3000,
    'bb111111-1111-1111-1111-111111111111'
  );

  update public.referral_program_settings
  set cashback_distribution = '[{"bps":10000,"weight":100},{"bps":50,"weight":100}]'::jsonb
  where id = 1;
  if (
    select count(*) from private.cashback_distribution()
    where bps = 50 and weight = 100
  ) <> 1 or exists (
    select 1 from private.cashback_distribution() where bps <> 50
  ) then
    raise exception 'faixa fora de 0,5%% a 5%% entrou na media';
  end if;
  update public.referral_program_settings
  set cashback_distribution = '[{"bps":500,"weight":1}]'::jsonb
  where id = 1;
  if (
    select count(*) from private.cashback_distribution()
    where bps = 50 and weight = 1
  ) <> 1 then
    raise exception 'media acima de 1%% nao caiu para a taxa minima';
  end if;
  update public.referral_program_settings
  set cashback_distribution =
    '[{"bps":50,"weight":700},{"bps":100,"weight":170},{"bps":200,"weight":90},{"bps":500,"weight":40}]'::jsonb
  where id = 1;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'be555555-5555-4555-8555-555555555555',
    'sopontos@example.com',
    '{"display_name":"So pontos"}'
  );
  update public.profiles
  set cpf = '04153389056', phone = '41955550055'
  where id = 'be555555-5555-4555-8555-555555555555';
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'be555555-5555-4555-8555-555555555555',
    'release', 5000, 5000, 'welcome', 'saldo-so-pontos'
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000001',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-01 18:00:00+00',
    4, 2, 10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'be710000-0000-4000-8000-000000000001',
    'be555555-5555-4555-8555-555555555555',
    'So pontos', true, 'pending', 'none', 'none'
  );
  v_cap := public.cap_point_redemption(
    'be710000-0000-4000-8000-000000000001',
    'be555555-5555-4555-8555-555555555555',
    9000
  );
  perform set_config(
    'request.jwt.claim.sub',
    'be555555-5555-4555-8555-555555555555',
    true
  );
  v_quote := public.quote_my_point_subsidy(
    'be710000-0000-4000-8000-000000000001',
    9000
  );
  if v_cap <> 2652 or (v_quote ->> 'points')::integer <> v_cap
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 0
  then
    raise exception 'cap e cotacao divergiram sem desconto % / %', v_cap, v_quote;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  v_held := private.hold_point_redemption(
    'be555555-5555-4555-8555-555555555555',
    'idem-so-pontos-01',
    10000,
    3000,
    v_cap
  );
  v_reserved := private.reserve_pix_charge(
    'be710000-0000-4000-8000-000000000001',
    'be555555-5555-4555-8555-555555555555',
    'bb311111-1111-1111-1111-111111111111',
    (v_held ->> 'charged_cents')::integer,
    'idem-so-pontos-01',
    'wal_house',
    3000,
    (v_held ->> 'gross_cents')::integer,
    (v_held ->> 'subsidy_cents')::integer,
    (v_held ->> 'points')::integer,
    (v_held ->> 'split_percent')::numeric
  );
  v_id := (v_reserved ->> 'id')::uuid;
  if (v_reserved ->> 'amount_cents')::integer <> 7348
    or (v_reserved ->> 'gross_amount_cents')::integer <> 10000
    or (v_reserved ->> 'subsidy_cents')::integer <> 2652
  then
    raise exception 'so pontos nao gravou o bruto %', v_reserved;
  end if;
  alter table public.payment_charges
    drop constraint payment_charges_subsidy_matches;
  update public.payment_charges
  set gross_amount_cents = null
  where id = v_id;
  perform private.apply_share_adjustments(v_id);
  if (
    select gross_amount_cents from public.payment_charges where id = v_id
  ) is distinct from 10000 then
    raise exception 'saida sem desconto apagou o bruto dos pontos';
  end if;
  alter table public.payment_charges
    add constraint payment_charges_subsidy_matches
    check (
      subsidy_cents = 0
      or (
        gross_amount_cents is not null
        and points_redeemed > 0
        and gross_amount_cents = amount_cents
          + subsidy_cents
          + first_booking_discount_cents
      )
    );
  perform private.apply_payment_transition(v_id, 'paid', true);
  if (
    select amount_cents from public.ledger_entries
    where payment_charge_id = v_id and kind = 'house_net'
  ) is distinct from 7000 or (
    select amount_cents from public.ledger_entries
    where payment_charge_id = v_id and kind = 'commission'
  ) is distinct from 348 then
    raise exception 'livro usou o liquido como bruto na cobranca so com pontos';
  end if;

  insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
  values ('bb311111-1111-1111-1111-111111111111', v_id, 100);

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000002',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-02 18:00:00+00',
    4, 2, 10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps,
    gross_amount_cents, subsidy_cents, points_redeemed
  ) values (
    'be720000-0000-4000-8000-000000000002',
    'be710000-0000-4000-8000-000000000002',
    'be555555-5555-4555-8555-555555555555',
    'bb311111-1111-1111-1111-111111111111',
    5000, 'PIX', 'creating',
    'idem-guarda-debito', 'wal_house', 1000,
    10000, 5000, 5000
  );
  insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
  values (
    'bb311111-1111-1111-1111-111111111111',
    'be720000-0000-4000-8000-000000000002',
    999999
  );
  perform private.apply_share_adjustments('be720000-0000-4000-8000-000000000002');
  if (
    select coalesce(sum(applied_cents), 0) from public.venue_cashback_debits
    where venue_id = 'bb311111-1111-1111-1111-111111111111'
  ) <> 0 or (
    select empty_slot_offset_cents from public.payment_charges
    where id = 'be720000-0000-4000-8000-000000000002'
  ) <> 0 then
    raise exception 'o guard consumiu debito sem gravar a cobranca';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000003',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-03 18:00:00+00',
    4, 2, 10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  v_reserved := private.reserve_pix_charge(
    'be710000-0000-4000-8000-000000000003',
    'be555555-5555-4555-8555-555555555555',
    'bb311111-1111-1111-1111-111111111111',
    10000,
    'idem-absorve-debito',
    'wal_house',
    3000
  );
  if (
    select empty_slot_offset_cents from public.payment_charges
    where id = (v_reserved ->> 'id')::uuid
  ) <> 100 or (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = v_id
  ) <> 100 or (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = 'be720000-0000-4000-8000-000000000002'
  ) <> 0 then
    raise exception 'debito grande sumiu ou o pequeno nao ficou na cobranca seguinte';
  end if;
  perform private.apply_share_adjustments((v_reserved ->> 'id')::uuid);
  if (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = v_id
  ) <> 100 then
    raise exception 'repetir o ajuste cobrou o debito de novo';
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'be444444-4444-4444-8444-444444444444',
    'desconto-pontos@example.com',
    jsonb_build_object(
      'display_name', 'Desconto e pontos',
      'phone', '41944440044',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
      )
    )
  );
  update public.profiles
  set cpf = '11144477735'
  where id = 'be444444-4444-4444-8444-444444444444'
    and cpf is null;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program, idempotency_key
  ) values (
    'be444444-4444-4444-8444-444444444444',
    'release', 8000, 8000, 'welcome', 'saldo-desconto-pontos'
  );
  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, idempotency_key, settlement, available_at
  ) values (
    'bb311111-1111-1111-1111-111111111111',
    'accrual', 5000, 'b2c', 'credito-que-nao-cabe', 'released', pg_catalog.now()
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000004',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-04 18:00:00+00',
    4, 2, 20000,
    'bb111111-1111-1111-1111-111111111111'
  );
  v_cap := public.cap_point_redemption(
    'be710000-0000-4000-8000-000000000004',
    'be444444-4444-4444-8444-444444444444',
    9000
  );
  perform set_config(
    'request.jwt.claim.sub',
    'be444444-4444-4444-8444-444444444444',
    true
  );
  v_quote := public.quote_my_point_subsidy(
    'be710000-0000-4000-8000-000000000004',
    9000
  );
  if v_cap <> 1353
    or (v_quote ->> 'points')::integer <> 1353
    or (v_quote ->> 'subsidy_cents')::integer <> 1353
    or (v_quote ->> 'first_booking_discount_cents')::integer <> 4000
    or (v_quote ->> 'charged_cents')::integer <> 14647
    or (v_quote ->> 'max_points')::integer <> 1353
  then
    raise exception 'cap nao descontou os 20%% como a cotacao % / %', v_cap, v_quote;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  v_held := private.hold_point_redemption(
    'be444444-4444-4444-8444-444444444444',
    'idem-desconto-pontos',
    20000,
    3000,
    v_cap
  );
  v_reserved := private.reserve_pix_charge(
    'be710000-0000-4000-8000-000000000004',
    'be444444-4444-4444-8444-444444444444',
    'bb311111-1111-1111-1111-111111111111',
    (v_held ->> 'charged_cents')::integer,
    'idem-desconto-pontos',
    'wal_house',
    3000,
    20000,
    (v_held ->> 'subsidy_cents')::integer,
    (v_held ->> 'points')::integer,
    (v_held ->> 'split_percent')::numeric
  );
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'be710000-0000-4000-8000-000000000004',
    'be444444-4444-4444-8444-444444444444',
    'Desconto e pontos', true, 'pending', 'none', 'none'
  );
  if (v_reserved ->> 'amount_cents')::integer <> 14647
    or (v_reserved ->> 'gross_amount_cents')::integer <> 20000
    or (
      select first_booking_discount_cents from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 4000
    or (
      select venue_credit_applied_cents from public.payment_charges
      where id = (v_reserved ->> 'id')::uuid
    ) <> 0
    or (
      select settlement from public.venue_referral_entries
      where idempotency_key = 'credito-que-nao-cabe'
    ) is distinct from 'released'
  then
    raise exception 'pontos e desconto comeram o credito ou o bruto %', v_reserved;
  end if;
  perform private.apply_payment_transition((v_reserved ->> 'id')::uuid, 'paid', true);
  if (
    select amount_cents from public.ledger_entries
    where payment_charge_id = (v_reserved ->> 'id')::uuid
      and kind = 'house_net'
  ) is distinct from 14000 then
    raise exception 'livro errou a casa na combinacao de pontos e desconto';
  end if;

  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000005',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-05 18:00:00+00',
    4, 2, 20000,
    'bb111111-1111-1111-1111-111111111111'
  );
  v_reserved := private.reserve_pix_charge(
    'be710000-0000-4000-8000-000000000005',
    'be444444-4444-4444-8444-444444444444',
    'bb311111-1111-1111-1111-111111111111',
    20000,
    'idem-credito-depois',
    'wal_house',
    3000
  );
  if (
    select venue_credit_applied_cents from public.payment_charges
    where id = (v_reserved ->> 'id')::uuid
  ) <> 5000 or (
    select settlement from public.venue_referral_entries
    where idempotency_key = 'credito-que-nao-cabe'
  ) is distinct from 'applied' then
    raise exception 'credito que nao cabia na primeira nao esperou a seguinte %', v_reserved;
  end if;

  insert into auth.users (id, email, raw_user_meta_data)
  values (
    'be666666-6666-4666-8666-666666666666',
    'replay-cashback@example.com',
    jsonb_build_object(
      'display_name', 'Replay',
      'phone', '41966660066',
      'referral_code', (
        select code from public.referral_codes
        where owner_user_id = 'bb111111-1111-1111-1111-111111111111'
      )
    )
  );
  update public.profiles
  set cpf = '00240289838', phone = '41966660066'
  where id = 'be666666-6666-4666-8666-666666666666';
  -- A indicação começa agora. O horário fixo de 15:00 UTC ficava
  -- antes da janela assim que o relógio passava desse instante.
  v_paid := pg_catalog.clock_timestamp();
  update public.referral_program_settings
  set cashback_distribution = '[{"bps":100,"weight":1}]'::jsonb
  where id = 1;
  v_weekday := extract(isodow from v_paid at time zone 'America/Sao_Paulo')::integer;
  insert into public.venue_empty_slots (
    venue_id, weekday, starts_minute, ends_minute
  ) values (
    'bb311111-1111-1111-1111-111111111111',
    v_weekday, 0, 1440
  );
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values (
    'be710000-0000-4000-8000-000000000006',
    'curitiba',
    'bb311111-1111-1111-1111-111111111111',
    'bb411111-1111-1111-1111-111111111111',
    'bb511111-1111-1111-1111-111111111111',
    '2027-12-06 18:00:00+00',
    4, 2, 10000,
    'bb111111-1111-1111-1111-111111111111'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'be720000-0000-4000-8000-000000000006',
    'be710000-0000-4000-8000-000000000006',
    'be666666-6666-4666-8666-666666666666',
    'bb311111-1111-1111-1111-111111111111',
    10000, 'PIX', 'paid',
    'idem-replay-cashback', 'wal_house', 180, v_paid
  );
  v_again := private.post_player_cashback('be720000-0000-4000-8000-000000000006', 180);
  if v_again <> 150
    or private.post_player_cashback('be720000-0000-4000-8000-000000000006', 180) <> 150
  then
    raise exception 'replay do cashback nao devolveu a parte da plataforma %', v_again;
  end if;
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'be720000-0000-4000-8000-000000000006'
      and program = 'cashback' and kind = 'accrual'
  ) <> 200 or (
    select count(*) from public.scape_point_entries
    where source_charge_id = 'be720000-0000-4000-8000-000000000006'
      and program = 'cashback' and kind = 'accrual'
  ) <> 1 or (
    select applied_cents from public.venue_cashback_debits
    where source_charge_id = 'be720000-0000-4000-8000-000000000006'
  ) <> 0 or (
    select amount_cents from public.venue_cashback_debits
    where source_charge_id = 'be720000-0000-4000-8000-000000000006'
  ) <> 50 then
    raise exception 'dobro do horario vazio nao ficou como obrigacao da casa';
  end if;
  if not exists (
    select 1 from public.referral_attributions
    where subject_user_id = 'be666666-6666-4666-8666-666666666666'
      and status = 'active'
      and referrer_user_id = 'bb111111-1111-1111-1111-111111111111'
  ) then
    raise exception 'indicacao do replay nao entrou';
  end if;
  perform private.post_referral_rewards('be720000-0000-4000-8000-000000000006');
  select amount_cents into v_c2c
  from public.scape_point_entries
  where source_charge_id = 'be720000-0000-4000-8000-000000000006'
    and program = 'c2c' and kind = 'accrual';
  if v_c2c is distinct from 30 then
    raise exception 'replay do cashback encolheu a indicacao %', v_c2c;
  end if;
  update public.referral_program_settings
  set cashback_distribution =
    '[{"bps":50,"weight":700},{"bps":100,"weight":170},{"bps":200,"weight":90},{"bps":500,"weight":40}]'::jsonb
  where id = 1;
end $$;

begin;
select set_config('request.jwt.claim.sub', 'bb222222-2222-2222-2222-222222222222', true);
set local role authenticated;
do $$
begin
  if (
    select count(*) from public.scape_point_entries
    where user_id = 'bb111111-1111-1111-1111-111111111111'
  ) <> 0 then
    raise exception 'jogador leu ponto de outra pessoa';
  end if;
  begin
    insert into public.scape_point_entries (
      user_id, kind, points, amount_cents, program, idempotency_key
    ) values (
      'bb222222-2222-2222-2222-222222222222',
      'accrual',
      1,
      1,
      'c2c',
      'jogador-escreveu'
    );
    raise exception 'jogador inseriu ponto';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;
rollback;
