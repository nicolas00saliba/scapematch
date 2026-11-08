-- Cálculo, idempotência, janela de um ano, estorno, antifraude e RLS.
-- Não fala com o Asaas.

\set ON_ERROR_STOP on

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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bb711111-1111-1111-1111-111111111111'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 100 then
    raise exception 'cashback de 1%% nao entrou';
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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bb811111-1111-1111-1111-111111111111'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 100 then
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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bb911111-1111-1111-1111-111111111111'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 100 then
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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bba11111-1111-1111-1111-111111111111'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 80 then
    raise exception 'cashback de 1%% sobre 8000 nao entrou';
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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bd711111-1111-4111-8111-111111111115'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 100 then
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
  if (
    select points from public.scape_point_entries
    where source_charge_id = 'bd844444-4444-4444-8444-444444444444'
      and program = 'cashback' and kind = 'accrual'
  ) is distinct from 100 then
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
