-- O dono desativa uma unidade: só a dele, nunca a última, nunca com grupo
-- futuro ou dinheiro a caminho. Desativada some do jogador. Desfaz no fim.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e2a11111-1111-4111-8111-111111111111', 'dono-unidades@example.com', '{"display_name":"Dono"}'),
  ('e2a22222-2222-4222-8222-222222222222', 'outro-unidades@example.com', '{"display_name":"Outro"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  ('e2a11111-1111-4111-8111-1111111111a1', 'e2a11111-1111-4111-8111-111111111111',
   'curitiba', 'Unidade Curitiba', 'Centro', 'Rua A', '1', '80020010',
   -25.43, -49.27, 5000, 'cnpj', '27180000000101', '41977770001', 'approved'),
  ('e2a11111-1111-4111-8111-1111111111a2', 'e2a11111-1111-4111-8111-111111111111',
   'curitiba', 'Unidade Dois', 'Centro', 'Rua B', '2', '80020011',
   -25.43, -49.27, 5000, 'cnpj', '27180000000202', '41977770002', 'approved'),
  ('e2a11111-1111-4111-8111-1111111111a3', 'e2a11111-1111-4111-8111-111111111111',
   'curitiba', 'Unidade Tres', 'Centro', 'Rua C', '3', '80020012',
   -25.43, -49.27, 5000, 'cnpj', '27180000000303', '41977770003', 'approved'),
  ('e2a22222-2222-4222-8222-2222222222b1', 'e2a22222-2222-4222-8222-222222222222',
   'curitiba', 'Casa De Outro', 'Centro', 'Rua D', '4', '80020013',
   -25.43, -49.27, 5000, 'cnpj', '27180000000404', '41977770004', 'approved');

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'e2a30000-0000-4000-8000-000000000001',
  'e2a11111-1111-4111-8111-1111111111a2',
  'Sala Futura', '', 6, 2, 60, 'medium', 10000
);
insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'e2a31000-0000-4000-8000-000000000001',
  'e2a30000-0000-4000-8000-000000000001',
  now() + interval '3 days', 'partner_grid'
);
insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'e2a40000-0000-4000-8000-000000000001', 'curitiba',
  'e2a11111-1111-4111-8111-1111111111a2',
  'e2a30000-0000-4000-8000-000000000001',
  'e2a31000-0000-4000-8000-000000000001',
  now() + interval '3 days', 4, 2, 10000,
  'e2a11111-1111-4111-8111-111111111111'
);
insert into public.venue_withdrawals (
  id, venue_id, amount_cents, status, source, period_key, external_reference
) values (
  'e2a50000-0000-4000-8000-000000000001',
  'e2a11111-1111-4111-8111-1111111111a3', 1000, 'pending',
  'manual', 'manual:teste-unidades', 'ref-unidades-1'
);

select set_config('request.jwt.claim.sub', 'e2a11111-1111-4111-8111-111111111111', true);
set local role authenticated;

do $$
declare
  v_state text;
  v_ok boolean;
begin
  -- Unidade de outro dono.
  v_ok := false;
  begin
    perform public.deactivate_my_unit('e2a22222-2222-4222-8222-2222222222b1');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'desativou unidade de outro dono'; end if;

  -- Grupo futuro.
  v_ok := false;
  begin
    perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a2');
  exception when others then
    v_ok := sqlerrm = 'unit_future_groups';
  end;
  if not v_ok then raise exception 'não barrou grupo futuro'; end if;

  -- Saque pendente.
  v_ok := false;
  begin
    perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a3');
  exception when others then
    v_ok := sqlerrm = 'unit_pending_money';
  end;
  if not v_ok then raise exception 'não barrou dinheiro a caminho'; end if;

  -- O dono não liga a desativação por update direto.
  update public.venues
  set deactivated_at = now(), suspended_at = now()
  where id = 'e2a11111-1111-4111-8111-1111111111a1';
  if exists (
    select 1 from public.venues
    where id = 'e2a11111-1111-4111-8111-1111111111a1'
      and deactivated_at is not null
  ) then
    raise exception 'update direto desativou a unidade';
  end if;
end $$;

reset role;
-- Libera a unidade 3: o saque termina.
update public.venue_withdrawals set status = 'done'
where id = 'e2a50000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub', 'e2a11111-1111-4111-8111-111111111111', true);
set local role authenticated;

do $$
declare
  v_ok boolean;
begin
  perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a3');
  if not exists (
    select 1 from public.venues
    where id = 'e2a11111-1111-4111-8111-1111111111a3'
      and deactivated_at is not null
  ) then
    raise exception 'unidade não ficou desativada';
  end if;
  -- Repetir não quebra.
  perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a3');
end $$;

reset role;
-- Cancela o grupo futuro e desativa a unidade 2: resta só a 1.
update public.groups set cancelled_at = now()
where id = 'e2a40000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub', 'e2a11111-1111-4111-8111-111111111111', true);
set local role authenticated;

do $$
declare
  v_ok boolean := false;
begin
  perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a2');
  begin
    perform public.deactivate_my_unit('e2a11111-1111-4111-8111-1111111111a1');
  exception when others then
    v_ok := sqlerrm = 'unit_last';
  end;
  if not v_ok then raise exception 'desativou a última unidade'; end if;
end $$;

-- O jogador (anon) não vê a unidade desativada.
reset role;
set local role anon;
do $$
begin
  if exists (
    select 1 from public.venues
    where id in (
      'e2a11111-1111-4111-8111-1111111111a2',
      'e2a11111-1111-4111-8111-1111111111a3'
    )
  ) then
    raise exception 'anon vê unidade desativada';
  end if;
  if not exists (
    select 1 from public.venues
    where id = 'e2a11111-1111-4111-8111-1111111111a1'
  ) then
    raise exception 'anon deixou de ver a unidade ativa';
  end if;
end $$;

reset role;
rollback;
