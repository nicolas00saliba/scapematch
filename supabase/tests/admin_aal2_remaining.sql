-- Dono em aal1 segue no ramo próprio. Admin em aal1 perde o atalho.
-- Admin em aal2 passa. O CI sobe postgres sem pgtap, então o caso
-- entra no harness SQL, no mesmo formato de admin_aal2_venue.sql.
-- Policy recusa em silêncio (zero linhas ou RLS). RPC de admin levanta
-- 'mfa obrigatorio'. Gatilho que só congela campo não aborta a linha.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  (
    'd0111111-1111-4111-8111-111111111111',
    'dono-restante@example.com',
    '{"display_name":"Dono Restante"}'
  ),
  (
    'd0222222-2222-4222-8222-222222222222',
    'admin-restante@example.com',
    '{"display_name":"Admin Restante"}'
  ),
  (
    'd0333333-3333-4333-8333-333333333333',
    'jogador-restante@example.com',
    '{"display_name":"Jogador Restante"}'
  ),
  (
    'd0444444-4444-4444-8444-444444444444',
    'indicador-restante@example.com',
    '{"display_name":"Indicador Restante"}'
  );

insert into public.admins (user_id)
values ('d0222222-2222-4222-8222-222222222222');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    'd0511111-1111-4111-8111-111111111111',
    'd0111111-1111-4111-8111-111111111111',
    'curitiba', 'Casa Restante', 'Centro', 'Rua do Portao', '10',
    '80010010', -25.43, -49.27, 5000, 'cnpj', '19110000000191',
    '41910002001', 'approved'
  ),
  (
    'd0522222-2222-4222-8222-222222222222',
    'd0111111-1111-4111-8111-111111111111',
    'curitiba', 'Casa Pendente Restante', 'Centro', 'Rua da Fila', '11',
    '80010011', -25.43, -49.27, 5000, 'cnpj', '19110000000192',
    '41910002002', 'pending'
  ),
  (
    'd0544444-4444-4444-8444-444444444444',
    'd0111111-1111-4111-8111-111111111111',
    'curitiba', 'Casa Suspensa Restante', 'Centro', 'Rua da Pausa', '12',
    '80010012', -25.43, -49.27, 5000, 'cnpj', '19110000000194',
    '41910002004', 'approved'
  ),
  (
    'd0555555-5555-4555-8555-555555555555',
    'd0111111-1111-4111-8111-111111111111',
    'curitiba', 'Casa Oculta Restante', 'Centro', 'Rua Oculta', '13',
    '80010013', -25.43, -49.27, 5000, 'cnpj', '19110000000195',
    '41910002005', 'pending'
  );

update public.venues
  set suspended_at = pg_catalog.now()
where id = 'd0544444-4444-4444-8444-444444444444';

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  (
    'd0611111-1111-4111-8111-111111111111',
    'd0522222-2222-4222-8222-222222222222',
    'Sala Pendente', '', 6, 2, 60, 'medium', 9000
  ),
  (
    'd0622222-2222-4222-8222-222222222222',
    'd0511111-1111-4111-8111-111111111111',
    'Sala Aberta', '', 6, 2, 60, 'medium', 9000
  ),
  (
    'd0633333-3333-4333-8333-333333333333',
    'd0544444-4444-4444-8444-444444444444',
    'Sala Suspensa', '', 6, 2, 60, 'medium', 9000
  );

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'd0711111-1111-4111-8111-111111111111',
  'd0622222-2222-4222-8222-222222222222',
  '2020-01-15 18:00:00+00',
  'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'd0811111-1111-4111-8111-111111111111',
  'curitiba',
  'd0511111-1111-4111-8111-111111111111',
  'd0622222-2222-4222-8222-222222222222',
  'd0711111-1111-4111-8111-111111111111',
  '2020-01-15 18:00:00+00',
  4, 2, 9000,
  'd0333333-3333-4333-8333-333333333333'
);

insert into public.group_members (group_id, user_id, display_name)
values (
  'd0811111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  'Jogador Restante'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, commission_bps
) values (
  'd0911111-1111-4111-8111-111111111111',
  'd0811111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  'd0511111-1111-4111-8111-111111111111',
  9000, 'PIX', 'paid', 'idem-aal2-restante', 1000
);

insert into public.ledger_entries (
  id, venue_id, group_id, account, direction, kind, amount_cents,
  payment_charge_id
) values (
  'd0a11111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  'd0811111-1111-4111-8111-111111111111',
  'house', 'credit', 'house_net', 8000,
  'd0911111-1111-4111-8111-111111111111'
);

insert into public.fiscal_invoices (
  id, payment_charge_id, group_id, venue_id, issuer, kind, status,
  value_cents, description
) values (
  'd0b11111-1111-4111-8111-111111111111',
  'd0911111-1111-4111-8111-111111111111',
  'd0811111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  'platform', 'commission', 'scheduled', 1000, 'comissao'
);

insert into public.cashback_draws (
  payment_charge_id, user_id, drawn_bps, applied_bps, seed, distribution
) values (
  'd0911111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  50, 50, 'semente', '[]'::jsonb
);

insert into public.scape_point_entries (
  id, user_id, kind, points, amount_cents, program, idempotency_key
) values (
  'd0c11111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  'accrual', 10, 10, 'c2c', 'idem-ponto-restante'
);

insert into public.referral_attributions (
  id, subject_kind, subject_venue_id, referrer_kind, referrer_user_id,
  code, starts_at, ends_at, status
) values (
  'd0d11111-1111-4111-8111-111111111111',
  'venue',
  'd0522222-2222-4222-8222-222222222222',
  'player',
  'd0444444-4444-4444-8444-444444444444',
  'RESTANTE',
  pg_catalog.now(),
  pg_catalog.now() + interval '30 days',
  'active'
);

insert into public.referral_withholdings (
  id, payment_charge_id, user_id, reason, program
) values (
  'd0e11111-1111-4111-8111-111111111111',
  'd0911111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  'payer_is_referrer',
  'c2c'
);

insert into public.venue_referral_entries (
  id, venue_id, kind, amount_cents, program, idempotency_key
) values (
  'd0f11111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  'accrual', 100, 'b2c', 'idem-credito-restante'
);

insert into public.venue_fiscal (venue_id, municipal_inscription)
values ('d0511111-1111-4111-8111-111111111111', 'inscricao');

insert into public.terms_acceptances (
  user_id, venue_id, audience, document_code, document_version
) values (
  'd0333333-3333-4333-8333-333333333333',
  'd0511111-1111-4111-8111-111111111111',
  'partner', 'partner_terms', '2026-11-06'
);

insert into public.promotions (id, venue_id, title, active)
values (
  'd1211111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  'Promo quieta',
  false
);

insert into public.room_photos (id, room_id, storage_path)
values (
  'd1311111-1111-4111-8111-111111111111',
  'd0622222-2222-4222-8222-222222222222',
  'd0511111-1111-4111-8111-111111111111/capa.jpg'
);

insert into public.partner_invites (code, label, city_id, active)
values ('aal2-off', 'Convite fechado', 'curitiba', false);

insert into storage.buckets (id, name)
values ('room-photos', 'room-photos')
on conflict (id) do nothing;

insert into storage.objects (bucket_id, name)
values (
  'room-photos',
  'd0522222-2222-4222-8222-222222222222/pendente.jpg'
),
(
  'room-photos',
  'd0555555-5555-4555-8555-555555555555/oculta.jpg'
);

select set_config(
  'request.jwt.claim.sub',
  'd0333333-3333-4333-8333-333333333333',
  false
);
select set_config('request.jwt.claim.aal', 'aal1', false);
insert into public.venue_claims (id, venue_id, claimant_id, note)
values (
  'd1011111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  'd0333333-3333-4333-8333-333333333333',
  'A casa é minha'
);
select set_config('request.jwt.claim.sub', '', false);
select set_config('request.jwt.claim.aal', '', false);
select set_config(
  'scapematch.referrer_code',
  (
    select code
    from public.referral_codes
    where owner_user_id = 'd0444444-4444-4444-8444-444444444444'
  ),
  false
);

do $$
declare
  v_policy record;
begin
  for v_policy in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where coalesce(qual, '') ~ 'is_admin\(\)'
      or coalesce(with_check, '') ~ 'is_admin\(\)'
  loop
    raise exception 'policy % ainda chama is_admin()', v_policy.policyname;
  end loop;
end $$;

create procedure pg_temp.expect_err(p_sql text, p_msg text)
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'passou indevido: %', p_sql;
exception
  when others then
    if sqlerrm is distinct from p_msg then
      raise exception '% devolveu %', p_sql, sqlerrm;
    end if;
end;
$$;

create procedure pg_temp.expect_rls(p_sql text)
language plpgsql
as $$
begin
  execute p_sql;
  raise exception 'passou o RLS: %', p_sql;
exception
  when insufficient_privilege then
    if sqlerrm not like '%row-level security%' then
      raise exception '% devolveu %', p_sql, sqlerrm;
    end if;
end;
$$;

-- Dono em aal1: o ramo próprio continua aberto.
begin;
select set_config(
  'request.jwt.claim.sub',
  'd0111111-1111-4111-8111-111111111111',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
declare
  v_code text;
  v_claim text;
  v_seen integer;
begin
  if not exists (
    select 1 from public.venues
    where id = 'd0522222-2222-4222-8222-222222222222'
  ) or not exists (
    select 1 from public.venues
    where id = 'd0544444-4444-4444-8444-444444444444'
  ) or not exists (
    select 1 from public.rooms
    where id = 'd0611111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.rooms
    where id = 'd0633333-3333-4333-8333-333333333333'
  ) then
    raise exception 'dono aal1 perdeu casa pendente ou suspensa';
  end if;
  if not exists (
    select 1 from public.venues
    where id = 'd0555555-5555-4555-8555-555555555555'
  ) then
    raise exception 'dono aal1 perdeu a casa oculta';
  end if;

  perform public.venue_private('d0511111-1111-4111-8111-111111111111');
  perform public.accept_terms(
    'partner', 'd0511111-1111-4111-8111-111111111111'
  );
  if (
    select count(*) from public.terms_acceptances
    where user_id = 'd0111111-1111-4111-8111-111111111111'
      and audience = 'partner'
  ) <> 3 then
    raise exception 'dono aal1 nao aceitou os termos';
  end if;

  v_code := current_setting('scapematch.referrer_code', true);
  v_claim := public.claim_venue_referral(
    'd0511111-1111-4111-8111-111111111111', v_code
  );
  if v_claim <> 'ok' then
    raise exception 'dono aal1 nao indicou a casa: %', v_claim;
  end if;

  perform public.mark_absence(
    'd0811111-1111-4111-8111-111111111111',
    'd0333333-3333-4333-8333-333333333333'
  );
  if not exists (
    select 1 from public.absences
    where group_id = 'd0811111-1111-4111-8111-111111111111'
      and marked_by = 'd0111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'dono aal1 nao marcou falta';
  end if;

  select count(*) into v_seen from public.platform_settings;
  if v_seen <> 0 then
    raise exception 'dono leu configuracao da plataforma';
  end if;

  if not exists (
    select 1 from public.partner_invites where code = 'ninja-cwb'
  ) or exists (
    select 1 from public.partner_invites where code = 'aal2-off'
  ) then
    raise exception 'dono viu convite inativo';
  end if;

  if not exists (
    select 1 from public.promotions
    where id = 'd1211111-1111-4111-8111-111111111111'
  ) then
    raise exception 'dono nao leu promocao inativa';
  end if;

  if not exists (
    select 1 from public.absences
    where id is not null
      and group_id = 'd0811111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.ledger_entries
    where id = 'd0a11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.fiscal_invoices
    where id = 'd0b11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.payment_charges
    where id = 'd0911111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venue_fiscal
    where venue_id = 'd0511111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venue_referral_entries
    where id = 'd0f11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.referral_attributions
    where id = 'd0d11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.terms_acceptances
    where venue_id = 'd0511111-1111-4111-8111-111111111111'
      and user_id = 'd0333333-3333-4333-8333-333333333333'
  ) then
    raise exception 'dono aal1 perdeu leitura da propria casa';
  end if;

  if exists (
    select 1 from public.cashback_draws
    where payment_charge_id = 'd0911111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.scape_point_entries
    where id = 'd0c11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.referral_withholdings
    where id = 'd0e11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
  ) or exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
  ) then
    raise exception 'dono leu linha que nao e dele';
  end if;

  insert into public.news_items (
    venue_id, title, summary, category, carousel_rank
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'Novidade do dono', 'Texto do dono', 'event', 3
  );
  if exists (
    select 1 from public.news_items
    where title = 'Novidade do dono' and carousel_rank is not null
  ) then
    raise exception 'dono gravou carousel_rank';
  end if;

  insert into public.promotions (venue_id, title)
  values ('d0511111-1111-4111-8111-111111111111', 'Promo do dono');

  insert into public.rooms (
    venue_id, name, capacity, minimum_players, duration_minutes,
    difficulty, price_cents, featured_rank
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'Sala do dono', 4, 2, 60, 'medium', 8000, 4
  );
  if exists (
    select 1 from public.rooms
    where name = 'Sala do dono' and featured_rank is not null
  ) then
    raise exception 'dono gravou featured_rank';
  end if;

  insert into public.room_photos (room_id, storage_path)
  values (
    'd0622222-2222-4222-8222-222222222222',
    'd0511111-1111-4111-8111-111111111111/dono.jpg'
  );

  update public.venues
    set neighborhood = 'Bairro do dono'
  where id = 'd0511111-1111-4111-8111-111111111111';
  if not exists (
    select 1 from public.venues
    where id = 'd0511111-1111-4111-8111-111111111111'
      and neighborhood = 'Bairro do dono'
      and status = 'approved'
  ) then
    raise exception 'dono nao gravou o bairro';
  end if;
end $$;

call pg_temp.expect_err(
  $sql$select * from public.review_venue(
    'd0522222-2222-4222-8222-222222222222', 'approved', null
  )$sql$,
  'not admin'
);
call pg_temp.expect_err(
  $sql$select * from public.review_venue_claim(
    'd1011111-1111-4111-8111-111111111111', 'rejected'
  )$sql$,
  'not admin'
);
call pg_temp.expect_err(
  'select * from public.commission_board()',
  'not admin'
);
call pg_temp.expect_err(
  'select * from public.set_platform_commission(1100)',
  'not admin'
);
call pg_temp.expect_err(
  $sql$select * from public.set_venue_commission(
    'd0511111-1111-4111-8111-111111111111', 800
  )$sql$,
  'not admin'
);

reset role;

do $$
begin
  perform * from private.venue_link_status(
    'd0511111-1111-4111-8111-111111111111'
  );
  if not private.venue_is_visible('d0522222-2222-4222-8222-222222222222')
    or not private.venue_is_visible('d0544444-4444-4444-8444-444444444444')
    or not private.venue_is_visible('d0555555-5555-4555-8555-555555555555')
    or not private.room_photo_object_allowed(
      'd0555555-5555-4555-8555-555555555555/oculta.jpg'
    )
  then
    raise exception 'dono aal1 perdeu auxiliar da propria casa';
  end if;
  update public.venues
    set merged_into = 'd0511111-1111-4111-8111-111111111111'
  where id = 'd0522222-2222-4222-8222-222222222222';
  if exists (
    select 1 from public.venues
    where id = 'd0522222-2222-4222-8222-222222222222'
      and merged_into is not null
  ) then
    raise exception 'dono gravou merged_into';
  end if;
  update public.profiles
    set suspended_at = pg_catalog.now()
  where id = 'd0333333-3333-4333-8333-333333333333';
  if exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
      and suspended_at is not null
  ) then
    raise exception 'dono suspendeu jogador';
  end if;
end $$;

rollback;

-- Titular da linha, em aal1, continua lendo o que já era dele.
begin;
select set_config(
  'request.jwt.claim.sub',
  'd0333333-3333-4333-8333-333333333333',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  if not exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
  ) or not exists (
    select 1 from public.cashback_draws
    where payment_charge_id = 'd0911111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.scape_point_entries
    where id = 'd0c11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.referral_withholdings
    where id = 'd0e11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.payment_charges
    where id = 'd0911111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venues
    where id = 'd0511111-1111-4111-8111-111111111111'
  ) then
    raise exception 'jogador perdeu a propria linha';
  end if;
  if exists (
    select 1 from public.venues
    where id = 'd0522222-2222-4222-8222-222222222222'
  ) or exists (
    select 1 from public.venues
    where id = 'd0555555-5555-4555-8555-555555555555'
  ) or exists (
    select 1 from public.rooms
    where id = 'd0611111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.promotions
    where id = 'd1211111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from storage.objects
    where name = 'd0522222-2222-4222-8222-222222222222/pendente.jpg'
  ) then
    raise exception 'jogador viu casa pendente';
  end if;
end $$;
reset role;
do $$
begin
  if private.venue_is_visible('d0522222-2222-4222-8222-222222222222')
    or private.room_photo_object_allowed(
      'd0522222-2222-4222-8222-222222222222/pendente.jpg'
    )
  then
    raise exception 'auxiliar abriu casa pendente para o jogador';
  end if;
  if not private.venue_is_visible('d0511111-1111-4111-8111-111111111111')
    or not private.room_photo_object_allowed(
      'd0511111-1111-4111-8111-111111111111/capa.jpg'
    )
  then
    raise exception 'casa aprovada sumiu do jogador';
  end if;
end $$;
rollback;

-- Admin em aal1: recusado. Dono de nada aqui.
begin;
grant update on public.venue_claims to authenticated;
select set_config(
  'request.jwt.claim.sub',
  'd0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;

do $$
begin
  if exists (
    select 1 from public.venues
    where id in (
      'd0522222-2222-4222-8222-222222222222',
      'd0544444-4444-4444-8444-444444444444',
      'd0555555-5555-4555-8555-555555555555'
    )
  ) or exists (
    select 1 from public.rooms
    where id in (
      'd0611111-1111-4111-8111-111111111111',
      'd0633333-3333-4333-8333-333333333333'
    )
  ) or exists (
    select 1 from public.promotions
    where id = 'd1211111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.partner_invites where code = 'aal2-off'
  ) or exists (
    select 1 from public.platform_settings
  ) or exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
  ) or exists (
    select 1 from public.cashback_draws
  ) or exists (
    select 1 from public.scape_point_entries
    where id = 'd0c11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.referral_withholdings
    where id = 'd0e11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.referral_attributions
    where id = 'd0d11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.payment_charges
    where id = 'd0911111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.ledger_entries
    where id = 'd0a11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.fiscal_invoices
    where id = 'd0b11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.venue_fiscal
    where venue_id = 'd0511111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.venue_referral_entries
    where id = 'd0f11111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from public.terms_acceptances
    where user_id = 'd0333333-3333-4333-8333-333333333333'
  ) or exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
  ) or exists (
    select 1 from storage.objects
    where name = 'd0522222-2222-4222-8222-222222222222/pendente.jpg'
  ) then
    raise exception 'admin aal1 leu pelo atalho';
  end if;

  update public.venue_claims
    set status = 'rejected'
  where id = 'd1011111-1111-4111-8111-111111111111';
  if exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
      and status = 'rejected'
  ) then
    raise exception 'admin aal1 atualizou reivindicacao';
  end if;

  update public.venues
    set neighborhood = 'Bairro admin aal1'
  where id = 'd0511111-1111-4111-8111-111111111111';
  if exists (
    select 1 from public.venues
    where id = 'd0511111-1111-4111-8111-111111111111'
      and neighborhood = 'Bairro admin aal1'
  ) then
    raise exception 'admin aal1 atualizou casa alheia';
  end if;
end $$;

call pg_temp.expect_rls(
  $sql$insert into public.news_items (
    venue_id, title, summary, category
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'News admin', 'Texto', 'event'
  )$sql$
);
call pg_temp.expect_rls(
  $sql$insert into public.promotions (venue_id, title)
  values ('d0511111-1111-4111-8111-111111111111', 'Promo admin')$sql$
);
call pg_temp.expect_rls(
  $sql$insert into public.rooms (
    venue_id, name, capacity, minimum_players, duration_minutes,
    difficulty, price_cents
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'Sala admin', 4, 2, 60, 'medium', 8000
  )$sql$
);
call pg_temp.expect_rls(
  $sql$insert into public.room_photos (room_id, storage_path)
  values (
    'd0622222-2222-4222-8222-222222222222',
    'd0511111-1111-4111-8111-111111111111/admin.jpg'
  )$sql$
);
call pg_temp.expect_err(
  $sql$select * from public.venue_private('d0511111-1111-4111-8111-111111111111')$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select public.accept_terms(
    'partner', 'd0511111-1111-4111-8111-111111111111'
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select public.claim_venue_referral(
    'd0511111-1111-4111-8111-111111111111', 'ABCD1234'
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select public.mark_absence(
    'd0811111-1111-4111-8111-111111111111',
    'd0333333-3333-4333-8333-333333333333'
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select * from public.review_venue(
    'd0522222-2222-4222-8222-222222222222', 'approved', null
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select * from public.review_venue_claim(
    'd1011111-1111-4111-8111-111111111111', 'rejected'
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  'select * from public.commission_board()',
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  'select * from public.set_platform_commission(1100)',
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$select * from public.set_venue_commission(
    'd0511111-1111-4111-8111-111111111111', 800
  )$sql$,
  'mfa obrigatorio'
);

reset role;

do $$
begin
  if private.venue_is_visible('d0555555-5555-4555-8555-555555555555')
    or private.venue_is_visible('d0544444-4444-4444-8444-444444444444')
    or private.room_photo_object_allowed(
      'd0555555-5555-4555-8555-555555555555/oculta.jpg'
    )
  then
    raise exception 'auxiliar abriu casa alheia para admin aal1';
  end if;
  if exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
      and status <> 'pending'
  ) then
    raise exception 'admin aal1 mudou a reivindicacao';
  end if;
  update public.rooms
    set featured_rank = 9
  where id = 'd0622222-2222-4222-8222-222222222222';
  if exists (
    select 1 from public.rooms
    where id = 'd0622222-2222-4222-8222-222222222222'
      and featured_rank is not null
  ) then
    raise exception 'admin aal1 gravou destaque';
  end if;
  update public.profiles
    set suspended_at = pg_catalog.now()
  where id = 'd0333333-3333-4333-8333-333333333333';
  if exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
      and suspended_at is not null
  ) then
    raise exception 'admin aal1 suspendeu perfil';
  end if;
end $$;

call pg_temp.expect_err(
  $sql$select * from private.venue_link_status(
    'd0511111-1111-4111-8111-111111111111'
  )$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$update public.venue_claims
    set status = 'rejected'
  where id = 'd1011111-1111-4111-8111-111111111111'$sql$,
  'mfa obrigatorio'
);
call pg_temp.expect_err(
  $sql$update public.venues
    set status = 'rejected'
  where id = 'd0511111-1111-4111-8111-111111111111'$sql$,
  'not owner'
);

rollback;

-- Admin em aal2: o atalho volta.
begin;
grant update on public.venue_claims to authenticated;
select set_config(
  'request.jwt.claim.sub',
  'd0222222-2222-4222-8222-222222222222',
  true
);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;

do $$
declare
  v_code text;
  v_claim text;
  v_bps integer;
  v_status text;
begin
  if not exists (
    select 1 from public.venues
    where id = 'd0522222-2222-4222-8222-222222222222'
  ) or not exists (
    select 1 from public.venues
    where id = 'd0544444-4444-4444-8444-444444444444'
  ) or not exists (
    select 1 from public.rooms
    where id = 'd0611111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.promotions
    where id = 'd1211111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.partner_invites where code = 'aal2-off'
  ) or not exists (
    select 1 from public.platform_settings where id = 1
  ) or not exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
  ) or not exists (
    select 1 from public.cashback_draws
    where payment_charge_id = 'd0911111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.scape_point_entries
    where id = 'd0c11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.referral_withholdings
    where id = 'd0e11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.referral_attributions
    where id = 'd0d11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.payment_charges
    where id = 'd0911111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.ledger_entries
    where id = 'd0a11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.fiscal_invoices
    where id = 'd0b11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venue_fiscal
    where venue_id = 'd0511111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.venue_referral_entries
    where id = 'd0f11111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from public.terms_acceptances
    where user_id = 'd0333333-3333-4333-8333-333333333333'
  ) or not exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
  ) or not exists (
    select 1 from storage.objects
    where name = 'd0522222-2222-4222-8222-222222222222/pendente.jpg'
  ) then
    raise exception 'admin aal2 nao leu pelo atalho';
  end if;
  if not exists (
    select 1 from public.venues
    where id = 'd0555555-5555-4555-8555-555555555555'
  ) then
    raise exception 'admin aal2 nao leu a casa oculta';
  end if;

  perform public.venue_private('d0511111-1111-4111-8111-111111111111');
  perform public.accept_terms(
    'partner', 'd0511111-1111-4111-8111-111111111111'
  );
  v_code := current_setting('scapematch.referrer_code', true);
  v_claim := public.claim_venue_referral(
    'd0511111-1111-4111-8111-111111111111', v_code
  );
  if v_claim <> 'ok' then
    raise exception 'admin aal2 nao indicou a casa: %', v_claim;
  end if;
  perform public.mark_absence(
    'd0811111-1111-4111-8111-111111111111',
    'd0333333-3333-4333-8333-333333333333'
  );
  if not exists (
    select 1 from public.absences
    where group_id = 'd0811111-1111-4111-8111-111111111111'
      and marked_by = 'd0222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'admin aal2 nao marcou falta';
  end if;

  select reviewed.status into v_status
  from public.review_venue(
    'd0522222-2222-4222-8222-222222222222', 'approved', null
  ) as reviewed;
  if v_status <> 'approved' then
    raise exception 'admin aal2 nao aprovou a casa';
  end if;

  perform public.set_platform_commission(1600);
  select commission_bps into v_bps
  from public.commission_board()
  where venue_id is null;
  if v_bps <> 1600 then
    raise exception 'painel nao viu a comissao nova: %', v_bps;
  end if;
  perform public.set_venue_commission(
    'd0511111-1111-4111-8111-111111111111', 800
  );
  if not exists (
    select 1 from public.commission_board()
    where venue_id = 'd0511111-1111-4111-8111-111111111111'
      and commission_bps = 800
      and is_override
  ) then
    raise exception 'override da casa nao entrou no painel';
  end if;

  insert into public.news_items (
    venue_id, title, summary, category, carousel_rank
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'News aal2', 'Texto', 'event', 2
  );
  if not exists (
    select 1 from public.news_items
    where title = 'News aal2' and carousel_rank = 2
  ) then
    raise exception 'admin aal2 nao gravou o carrossel';
  end if;

  insert into public.promotions (venue_id, title)
  values ('d0511111-1111-4111-8111-111111111111', 'Promo aal2');
  insert into public.rooms (
    venue_id, name, capacity, minimum_players, duration_minutes,
    difficulty, price_cents, featured_rank
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'Sala aal2', 4, 2, 60, 'medium', 8000, 1
  );
  if not exists (
    select 1 from public.rooms
    where name = 'Sala aal2' and featured_rank = 1
  ) then
    raise exception 'admin aal2 nao gravou o destaque';
  end if;
  insert into public.room_photos (room_id, storage_path)
  values (
    'd0622222-2222-4222-8222-222222222222',
    'd0511111-1111-4111-8111-111111111111/aal2.jpg'
  );

  update public.venues
    set neighborhood = 'Bairro aal2'
  where id = 'd0511111-1111-4111-8111-111111111111';
  if not exists (
    select 1 from public.venues
    where id = 'd0511111-1111-4111-8111-111111111111'
      and neighborhood = 'Bairro aal2'
  ) then
    raise exception 'admin aal2 nao atualizou a casa';
  end if;

  update public.venue_claims
    set status = 'rejected'
  where id = 'd1011111-1111-4111-8111-111111111111';
  if not exists (
    select 1 from public.venue_claims
    where id = 'd1011111-1111-4111-8111-111111111111'
      and status = 'rejected'
      and reviewed_by = 'd0222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'admin aal2 nao recusou a reivindicacao';
  end if;
end $$;

reset role;

do $$
begin
  if not private.venue_is_visible('d0544444-4444-4444-8444-444444444444')
    or not private.venue_is_visible('d0555555-5555-4555-8555-555555555555')
    or not private.room_photo_object_allowed(
      'd0555555-5555-4555-8555-555555555555/oculta.jpg'
    )
  then
    raise exception 'auxiliar fechou a casa para admin aal2';
  end if;
  perform * from private.venue_link_status(
    'd0511111-1111-4111-8111-111111111111'
  );
  update public.profiles
    set suspended_at = pg_catalog.now()
  where id = 'd0333333-3333-4333-8333-333333333333';
  if not exists (
    select 1 from public.profiles
    where id = 'd0333333-3333-4333-8333-333333333333'
      and suspended_at is not null
  ) then
    raise exception 'admin aal2 nao suspendeu o perfil';
  end if;
  update public.venues
    set merged_into = 'd0511111-1111-4111-8111-111111111111'
  where id = 'd0544444-4444-4444-8444-444444444444';
  if not exists (
    select 1 from public.venues
    where id = 'd0544444-4444-4444-8444-444444444444'
      and merged_into = 'd0511111-1111-4111-8111-111111111111'
  ) then
    raise exception 'admin aal2 nao gravou merged_into';
  end if;
end $$;

rollback;
