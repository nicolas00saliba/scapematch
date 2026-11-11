-- Passaporte: flag, carimbo idempotente, marcos, estorno, mimo e RLS.

\set ON_ERROR_STOP on

do $$
begin
  if has_table_privilege('anon', 'public.passport_stamps', 'select')
    or has_table_privilege('authenticated', 'public.passport_stamps', 'insert')
    or has_table_privilege('authenticated', 'public.passport_stamps', 'update')
    or has_table_privilege('authenticated', 'public.passport_stamps', 'delete')
    or has_table_privilege('service_role', 'public.passport_plays', 'select')
    or not has_table_privilege('authenticated', 'public.passport_stamps', 'select')
  then
    raise exception 'privilegio de tabela do passaporte saiu do combinado';
  end if;
  if has_function_privilege('anon', 'public.my_passport()', 'execute')
    or has_function_privilege('anon', 'public.save_passport_gift(uuid,uuid,text,text,text,boolean,uuid)', 'execute')
    or has_function_privilege('authenticated', 'private.passport_apply_charge(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.my_passport()', 'execute')
    or not has_function_privilege('authenticated', 'public.deliver_passport_gift(text)', 'execute')
    or not has_function_privilege('authenticated', 'public.confirm_session_attendance(uuid,uuid)', 'execute')
    or has_function_privilege('anon', 'public.confirm_session_attendance(uuid,uuid)', 'execute')
    or has_table_privilege('authenticated', 'public.session_checkins', 'insert')
    or not has_table_privilege('authenticated', 'public.session_checkins', 'select')
  then
    raise exception 'execute do passaporte saiu do combinado';
  end if;
  if (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef
      and 'search_path=""' = any (p.proconfig)
      and (
        (n.nspname = 'public' and p.proname in (
          'my_passport', 'passport_program_enabled', 'save_passport_gift',
          'my_passport_desk', 'deliver_passport_gift',
          'admin_passport_settings', 'admin_save_passport_settings',
          'confirm_session_attendance'
        ))
        or (n.nspname = 'private' and p.proname in (
          'passport_apply_charge', 'passport_sync_user', 'subsidy_quote'
        ))
      )
  ) <> 11 then
    raise exception 'funcao do passaporte sem security definer ou search_path vazio';
  end if;
  if public.passport_program_enabled() then
    raise exception 'a flag do passaporte nao nasceu desligada';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('d0111111-1111-4111-8111-111111111111', 'pp-jogador@example.com', '{"display_name":"Jogador Passaporte"}'),
  ('d0222222-2222-4222-8222-222222222222', 'pp-casa@example.com', '{"display_name":"Casa Passaporte"}'),
  ('d0333333-3333-4333-8333-333333333333', 'pp-admin@example.com', '{"display_name":"Admin Passaporte"}'),
  ('d0444444-4444-4444-8444-444444444444', 'pp-outro@example.com', '{"display_name":"Outro Passaporte"}'),
  ('d0555555-5555-4555-8555-555555555555', 'pp-desconto@example.com', '{"display_name":"Desconto"}'),
  ('d0666666-6666-4666-8666-666666666666', 'pp-vaga@example.com', '{"display_name":"Vaga"}');

insert into public.admins (user_id)
values ('d0333333-3333-4333-8333-333333333333');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  (
    'd0511111-1111-4111-8111-111111111111',
    'd0222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa do Carimbo', 'Centro', 'Rua do Selo', '10',
    '80010000', -25.43, -49.27, 5000, 'cnpj', '11222333000181', '4130001001',
    'approved'
  ),
  (
    'd0522222-2222-4222-8222-222222222222',
    'd0222222-2222-4222-8222-222222222222',
    'curitiba', 'Casa Solo', 'Batel', 'Rua Unica', '2',
    '80010000', -25.44, -49.28, 5000, 'cnpj', '11222333000182', '4130001002',
    'approved'
  );

insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values
  ('d0611111-1111-4111-8111-111111111111', 'd0511111-1111-4111-8111-111111111111', 'Sala Alfa', 6, 2, 60, 'medium', 10000),
  ('d0622222-2222-4222-8222-222222222222', 'd0511111-1111-4111-8111-111111111111', 'Sala Beta', 6, 2, 60, 'medium', 10000),
  ('d0633333-3333-4333-8333-333333333333', 'd0522222-2222-4222-8222-222222222222', 'Sala Unica', 6, 2, 60, 'easy', 8000);

insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values
  ('d0711111-1111-4111-8111-111111111111', 'curitiba', 'd0511111-1111-4111-8111-111111111111', 'd0611111-1111-4111-8111-111111111111', '2026-10-01 18:00:00+00', 4, 2, 10000, 'd0111111-1111-4111-8111-111111111111'),
  ('d0722222-2222-4222-8222-222222222222', 'curitiba', 'd0511111-1111-4111-8111-111111111111', 'd0611111-1111-4111-8111-111111111111', '2026-10-08 18:00:00+00', 4, 2, 10000, 'd0111111-1111-4111-8111-111111111111'),
  ('d0733333-3333-4333-8333-333333333333', 'curitiba', 'd0511111-1111-4111-8111-111111111111', 'd0622222-2222-4222-8222-222222222222', '2026-10-15 18:00:00+00', 4, 2, 10000, 'd0111111-1111-4111-8111-111111111111'),
  ('d0744444-4444-4444-8444-444444444444', 'curitiba', 'd0511111-1111-4111-8111-111111111111', 'd0611111-1111-4111-8111-111111111111', '2026-12-01 18:00:00+00', 4, 2, 10000, 'd0111111-1111-4111-8111-111111111111'),
  ('d0755555-5555-4555-8555-555555555555', 'curitiba', 'd0522222-2222-4222-8222-222222222222', 'd0633333-3333-4333-8333-333333333333', '2026-10-20 18:00:00+00', 4, 2, 8000, 'd0111111-1111-4111-8111-111111111111');

insert into public.group_members (
  group_id, user_id, display_name, payment_status, attendance
) values
  ('d0711111-1111-4111-8111-111111111111', 'd0111111-1111-4111-8111-111111111111', 'Jogador Passaporte', 'paid', 'confirmed'),
  ('d0722222-2222-4222-8222-222222222222', 'd0111111-1111-4111-8111-111111111111', 'Jogador Passaporte', 'paid', 'confirmed'),
  ('d0733333-3333-4333-8333-333333333333', 'd0111111-1111-4111-8111-111111111111', 'Jogador Passaporte', 'paid', 'confirmed'),
  ('d0744444-4444-4444-8444-444444444444', 'd0111111-1111-4111-8111-111111111111', 'Jogador Passaporte', 'paid', 'confirmed'),
  ('d0755555-5555-4555-8555-555555555555', 'd0111111-1111-4111-8111-111111111111', 'Jogador Passaporte', 'paid', 'confirmed');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  commission_bps, idempotency_key, paid_at
) values (
  'd0811111-1111-4111-8111-111111111111',
  'd0711111-1111-4111-8111-111111111111',
  'd0111111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  10000, 'PIX', 'paid', 2500, 'pp-charge-alfa-1', '2026-09-20 12:00:00+00'
);

do $$
begin
  if exists (
    select 1 from public.passport_stamps
    where user_id = 'd0111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'flag desligada carimbou a sala';
  end if;
end $$;

update public.referral_program_settings
set passport_enabled = true,
    passport_rooms_5 = 1,
    passport_points_5 = 500,
    passport_rooms_10 = 2,
    passport_points_10 = 1000,
    passport_rooms_25 = 3,
    passport_points_25 = 3000,
    passport_house_points = 300
where id = 1;

select private.passport_catch_up();

do $$
begin
  if exists (
    select 1 from public.passport_stamps
    where user_id = 'd0111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'catch-up carimbou sem comparecimento da casa';
  end if;
end $$;

select set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', false);
select public.confirm_session_attendance(
  'd0711111-1111-4111-8111-111111111111',
  'd0111111-1111-4111-8111-111111111111'
);

do $$
declare
  v_count integer;
  v_points integer;
begin
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'primeiro carimbo ficou % visitas e % pontos', v_count, v_points;
  end if;
  if (
    select count(*) from public.admin_audit_log
    where actor_id = 'd0222222-2222-4222-8222-222222222222'
      and action = 'confirm_session_attendance'
  ) <> 1 then
    raise exception 'o comparecimento nao ficou na auditoria';
  end if;
  perform public.confirm_session_attendance(
    'd0711111-1111-4111-8111-111111111111',
    'd0111111-1111-4111-8111-111111111111'
  );
  perform private.passport_catch_up();
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'repetir o comparecimento duplicou o carimbo % %', v_count, v_points;
  end if;
  if (
    select count(*) from public.admin_audit_log
    where actor_id = 'd0222222-2222-4222-8222-222222222222'
      and action = 'confirm_session_attendance'
  ) <> 1 then
    raise exception 'repetir o comparecimento gravou outra auditoria';
  end if;
  if (
    select count(*) from public.scape_point_entries
    where user_id = 'd0111111-1111-4111-8111-111111111111'
      and program = 'passport' and kind = 'release'
  ) <> 1 then
    raise exception 'marco nao usou o programa passport';
  end if;
  perform private.passport_apply_charge('d0811111-1111-4111-8111-111111111111');
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'repetir a mesma cobranca duplicou o carimbo % %', v_count, v_points;
  end if;
end $$;

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  commission_bps, idempotency_key, paid_at
) values
  (
    'd0822222-2222-4222-8222-222222222222',
    'd0722222-2222-4222-8222-222222222222',
    'd0111111-1111-4111-8111-111111111111',
    'd0511111-1111-4111-8111-111111111111',
    10000, 'PIX', 'paid', 2500, 'pp-charge-alfa-2', '2026-10-01 12:00:00+00'
  ),
  (
    'd0844444-4444-4444-8444-444444444444',
    'd0744444-4444-4444-8444-444444444444',
    'd0111111-1111-4111-8111-111111111111',
    'd0511111-1111-4111-8111-111111111111',
    10000, 'PIX', 'paid', 2500, 'pp-charge-futura', '2026-11-01 12:00:00+00'
  );

do $$
declare
  v_count integer;
  v_points integer;
begin
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'pagamento sem comparecimento carimbou % %', v_count, v_points;
  end if;
  perform public.confirm_session_attendance(
    'd0722222-2222-4222-8222-222222222222',
    'd0111111-1111-4111-8111-111111111111'
  );
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 2 or v_points is distinct from 500 then
    raise exception 'segunda visita nao contou ou duplicou pontos % %', v_count, v_points;
  end if;
  if exists (
    select 1 from public.passport_plays
    where payment_charge_id = 'd0844444-4444-4444-8444-444444444444'
  ) then
    raise exception 'horario futuro ganhou carimbo';
  end if;
  begin
    perform public.confirm_session_attendance(
      'd0744444-4444-4444-8444-444444444444',
      'd0111111-1111-4111-8111-111111111111'
    );
    raise exception 'a casa confirmou antes da sessao';
  exception
    when others then
      if sqlerrm <> 'session not started' then
        raise exception 'antes da hora: %', sqlerrm;
      end if;
  end;
  if exists (
    select 1 from public.session_checkins
    where group_id = 'd0744444-4444-4444-8444-444444444444'
  ) then
    raise exception 'confirmacao antecipada gravou comparecimento';
  end if;
end $$;

update public.payment_charges
set status = 'refunded', refunded_at = '2026-10-09 12:00:00+00'
where id = 'd0822222-2222-4222-8222-222222222222';

update public.group_members
set refund_status = 'refunded'
where group_id = 'd0722222-2222-4222-8222-222222222222'
  and user_id = 'd0111111-1111-4111-8111-111111111111';

do $$
declare
  v_count integer;
  v_points integer;
begin
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'estorno de uma visita apagou o carimbo % %', v_count, v_points;
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', true);
set local role authenticated;
select public.save_passport_gift(
  'd0511111-1111-4111-8111-111111111111',
  'd0611111-1111-4111-8111-111111111111',
  'stamp',
  'Foto da sala',
  'Uma foto exclusiva depois do jogo.',
  true,
  null
);
select public.save_passport_gift(
  'd0511111-1111-4111-8111-111111111111',
  null,
  'house_complete',
  'Chaveiro da casa',
  'Quando fechar as salas.',
  true,
  null
);
rollback;

do $$
declare
  v_code text;
  v_status text;
begin
  perform set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', true);
  perform set_config('role', 'authenticated', true);
  -- set_config role nao troca o papel. O bloco acima ja gravou e desfez.
end $$;

-- O rollback desfez o mimo. Grava de novo como dono do banco, pela funcao,
-- com o jwt do dono e o papel authenticated dentro da transacao que fica.
begin;
select set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', true);
set local role authenticated;
select public.save_passport_gift(
  'd0511111-1111-4111-8111-111111111111',
  'd0611111-1111-4111-8111-111111111111',
  'stamp',
  'Foto da sala',
  'Uma foto exclusiva depois do jogo.',
  true,
  null
);
select public.save_passport_gift(
  'd0511111-1111-4111-8111-111111111111',
  null,
  'house_complete',
  'Chaveiro da casa',
  'Quando fechar as salas.',
  true,
  null
);
commit;

do $$
declare
  v_code text;
begin
  select c.code into v_code
  from public.passport_gift_claims c
  join public.passport_gifts g on g.id = c.gift_id
  where c.user_id = 'd0111111-1111-4111-8111-111111111111'
    and g.trigger_kind = 'stamp'
    and c.status = 'available';
  if v_code is null or v_code !~ '^[A-Z0-9]{8}$' then
    raise exception 'o jogador nao recebeu o codigo do mimo %', v_code;
  end if;
  if exists (
    select 1
    from public.passport_gift_claims c
    join public.passport_gifts g on g.id = c.gift_id
    where c.user_id = 'd0111111-1111-4111-8111-111111111111'
      and g.trigger_kind = 'house_complete'
  ) then
    raise exception 'chaveiro saiu antes de fechar a casa';
  end if;
end $$;

create temporary table pp_gift_code as
select c.code
from public.passport_gift_claims c
join public.passport_gifts g on g.id = c.gift_id
where c.user_id = 'd0111111-1111-4111-8111-111111111111'
  and g.trigger_kind = 'stamp';

grant select on pp_gift_code to authenticated;

begin;
select set_config('request.jwt.claim.sub', 'd0444444-4444-4444-8444-444444444444', true);
set local role authenticated;
do $$
begin
  begin
    perform public.deliver_passport_gift((select code from pp_gift_code));
    raise exception 'estranho entregou o mimo';
  exception
    when others then
      if sqlerrm <> 'codigo nao encontrado' then
        raise exception 'entrega alheia: %', sqlerrm;
      end if;
  end;
  begin
    perform public.deliver_passport_gift('NAOEXISTE');
    raise exception 'codigo inventado passou';
  exception
    when others then
      if sqlerrm <> 'codigo nao encontrado' then
        raise exception 'codigo inventado: %', sqlerrm;
      end if;
  end;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', true);
set local role authenticated;
select public.deliver_passport_gift((
  select c.code
  from public.passport_gift_claims c
  join public.passport_gifts g on g.id = c.gift_id
  where c.user_id = 'd0111111-1111-4111-8111-111111111111'
    and g.trigger_kind = 'stamp'
));
commit;

do $$
begin
  if (
    select status from public.passport_gift_claims c
    join public.passport_gifts g on g.id = c.gift_id
    where c.user_id = 'd0111111-1111-4111-8111-111111111111'
      and g.trigger_kind = 'stamp'
  ) is distinct from 'delivered' then
    raise exception 'a casa nao marcou o mimo como entregue';
  end if;
end $$;

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  commission_bps, idempotency_key, paid_at
) values (
  'd0833333-3333-4333-8333-333333333333',
  'd0733333-3333-4333-8333-333333333333',
  'd0111111-1111-4111-8111-111111111111',
  'd0511111-1111-4111-8111-111111111111',
  10000, 'PIX', 'paid', 2500, 'pp-charge-beta', '2026-10-10 12:00:00+00'
);

select public.confirm_session_attendance(
  'd0733333-3333-4333-8333-333333333333',
  'd0111111-1111-4111-8111-111111111111'
);

do $$
declare
  v_points integer;
  v_house integer;
begin
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  select count(*) into v_house
  from public.passport_milestones
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and milestone_key = 'house:d0511111-1111-4111-8111-111111111111'
    and reversed_at is null;
  if v_points is distinct from 1800 or v_house is distinct from 1 then
    raise exception 'fechar a casa nao pagou 500+1000+300, saldo %', v_points;
  end if;
  if (
    select count(*) from public.passport_gift_claims c
    join public.passport_gifts g on g.id = c.gift_id
    where c.user_id = 'd0111111-1111-4111-8111-111111111111'
      and g.trigger_kind = 'house_complete'
      and c.status = 'available'
  ) <> 1 then
    raise exception 'fechar a casa nao liberou o chaveiro';
  end if;
end $$;

insert into public.rooms (
  id, venue_id, name, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'd0644444-4444-4444-8444-444444444444',
  'd0511111-1111-4111-8111-111111111111',
  'Sala Nova', 6, 2, 60, 'hard', 10000
);

select private.passport_sync_user('d0111111-1111-4111-8111-111111111111');

do $$
declare
  v_points integer;
begin
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_points is distinct from 1800 then
    raise exception 'sala nova desfez o marco da casa, saldo %', v_points;
  end if;
end $$;

update public.payment_charges
set status = 'refunded', refunded_at = '2026-10-21 12:00:00+00'
where id = 'd0811111-1111-4111-8111-111111111111';

update public.group_members
set refund_status = 'refunded'
where group_id = 'd0711111-1111-4111-8111-111111111111'
  and user_id = 'd0111111-1111-4111-8111-111111111111';

do $$
declare
  v_points integer;
  v_alfa integer;
begin
  select count(*) into v_alfa
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  if v_alfa <> 0 or v_points is distinct from 500 then
    raise exception 'estorno da unica visita nao reverteu carimbo e marcos % %', v_alfa, v_points;
  end if;
  if (
    select status from public.passport_gift_claims c
    join public.passport_gifts g on g.id = c.gift_id
    where c.user_id = 'd0111111-1111-4111-8111-111111111111'
      and g.trigger_kind = 'stamp'
  ) is distinct from 'delivered' then
    raise exception 'mimo ja entregue foi desfeito';
  end if;
  if (
    select status from public.passport_gift_claims c
    join public.passport_gifts g on g.id = c.gift_id
    where c.user_id = 'd0111111-1111-4111-8111-111111111111'
      and g.trigger_kind = 'house_complete'
  ) is distinct from 'revoked' then
    raise exception 'chaveiro continuou disponivel depois do estorno';
  end if;
end $$;

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  commission_bps, idempotency_key, paid_at
) values (
  'd0855555-5555-4555-8555-555555555555',
  'd0755555-5555-4555-8555-555555555555',
  'd0111111-1111-4111-8111-111111111111',
  'd0522222-2222-4222-8222-222222222222',
  8000, 'PIX', 'paid', 2500, 'pp-charge-solo', '2026-10-18 12:00:00+00'
);

select public.confirm_session_attendance(
  'd0755555-5555-4555-8555-555555555555',
  'd0111111-1111-4111-8111-111111111111'
);

do $$
declare
  v_points integer;
  v_solo integer;
begin
  select available_points into v_points
  from private.scape_balances('d0111111-1111-4111-8111-111111111111');
  select count(*) into v_solo
  from public.passport_milestones
  where user_id = 'd0111111-1111-4111-8111-111111111111'
    and milestone_key = 'house:d0522222-2222-4222-8222-222222222222'
    and reversed_at is null;
  if v_solo <> 0 or v_points is distinct from 1500 then
    raise exception 'casa de uma sala pagou marco ou o saldo nao voltou a 1500: % %', v_solo, v_points;
  end if;
end $$;

select set_config('request.jwt.claim.sub', '', false);

insert into auth.users (id, email, raw_user_meta_data) values (
  'd0777777-7777-4777-8777-777777777777',
  'pp-antes@example.com',
  '{"display_name":"Pago Antes"}'
);

insert into public.groups (
  id, city_id, venue_id, room_id, starts_at, total_spots, minimum_spots,
  price_cents, created_by
) values (
  'd0766666-6666-4666-8666-666666666666',
  'curitiba',
  'd0511111-1111-4111-8111-111111111111',
  'd0611111-1111-4111-8111-111111111111',
  pg_catalog.now() + interval '2 days',
  4, 2, 10000,
  'd0777777-7777-4777-8777-777777777777'
);

insert into public.group_members (
  group_id, user_id, display_name, payment_status, attendance
) values (
  'd0766666-6666-4666-8666-666666666666',
  'd0777777-7777-4777-8777-777777777777',
  'Pago Antes', 'paid', 'confirmed'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  commission_bps, idempotency_key, paid_at
) values (
  'd0866666-6666-4666-8666-666666666666',
  'd0766666-6666-4666-8666-666666666666',
  'd0777777-7777-4777-8777-777777777777',
  'd0511111-1111-4111-8111-111111111111',
  10000, 'PIX', 'paid', 2500, 'pp-charge-antes', pg_catalog.now()
);

do $$
declare
  v_count integer;
  v_points integer;
begin
  if exists (
    select 1 from public.passport_plays
    where payment_charge_id = 'd0866666-6666-4666-8666-666666666666'
  ) then
    raise exception 'reserva paga antes da sessao ja carimbou';
  end if;
  begin
    perform set_config(
      'request.jwt.claim.sub',
      'd0222222-2222-4222-8222-222222222222',
      true
    );
    perform public.confirm_session_attendance(
      'd0766666-6666-4666-8666-666666666666',
      'd0777777-7777-4777-8777-777777777777'
    );
    raise exception 'confirmou a reserva antes da sessao';
  exception
    when others then
      if sqlerrm <> 'session not started' then
        raise exception 'paga antes da hora: %', sqlerrm;
      end if;
  end;
end $$;

update public.groups
set starts_at = pg_catalog.now() - interval '30 minutes'
where id = 'd0766666-6666-4666-8666-666666666666';

select private.passport_catch_up();

do $$
declare
  v_count integer;
  v_points integer;
begin
  if exists (
    select 1 from public.passport_plays
    where payment_charge_id = 'd0866666-6666-4666-8666-666666666666'
  ) then
    raise exception 'catch-up carimbou a sessao paga sem confirmacao';
  end if;
  begin
    perform set_config(
      'request.jwt.claim.sub',
      'd0777777-7777-4777-8777-777777777777',
      true
    );
    perform public.confirm_session_attendance(
      'd0766666-6666-4666-8666-666666666666',
      'd0777777-7777-4777-8777-777777777777'
    );
    raise exception 'o jogador confirmou o proprio comparecimento';
  exception
    when others then
      if sqlerrm <> 'not owner' then
        raise exception 'jogador no check-in: %', sqlerrm;
      end if;
  end;
  perform set_config(
    'request.jwt.claim.sub',
    'd0222222-2222-4222-8222-222222222222',
    true
  );
  insert into public.session_checkins (
    venue_id, group_id, user_id, room_id, marked_by
  ) values (
    'd0511111-1111-4111-8111-111111111111',
    'd0766666-6666-4666-8666-666666666666',
    'd0777777-7777-4777-8777-777777777777',
    'd0611111-1111-4111-8111-111111111111',
    'd0222222-2222-4222-8222-222222222222'
  );
  perform private.passport_catch_up();
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0777777-7777-4777-8777-777777777777'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  select available_points into v_points
  from private.scape_balances('d0777777-7777-4777-8777-777777777777');
  if v_count is distinct from 1 or v_points is distinct from 500 then
    raise exception 'catch-up da reserva paga antes ficou % visitas e % pontos', v_count, v_points;
  end if;
  perform public.confirm_session_attendance(
    'd0766666-6666-4666-8666-666666666666',
    'd0777777-7777-4777-8777-777777777777'
  );
  perform private.passport_catch_up();
  select play_count into v_count
  from public.passport_stamps
  where user_id = 'd0777777-7777-4777-8777-777777777777'
    and room_id = 'd0611111-1111-4111-8111-111111111111';
  if v_count is distinct from 1 then
    raise exception 'catch-up duplicou o carimbo ja confirmado %', v_count;
  end if;
end $$;

update public.payment_charges
set status = 'refunded', refunded_at = pg_catalog.now()
where id = 'd0866666-6666-4666-8666-666666666666';

update public.group_members
set refund_status = 'refunded'
where group_id = 'd0766666-6666-4666-8666-666666666666'
  and user_id = 'd0777777-7777-4777-8777-777777777777';

do $$
declare
  v_points integer;
begin
  if exists (
    select 1 from public.passport_stamps
    where user_id = 'd0777777-7777-4777-8777-777777777777'
  ) then
    raise exception 'estorno nao reverteu o carimbo da confirmacao';
  end if;
  select available_points into v_points
  from private.scape_balances('d0777777-7777-4777-8777-777777777777');
  if v_points is distinct from 0 then
    raise exception 'estorno deixou pontos do passaporte %', v_points;
  end if;
  if not exists (
    select 1 from public.session_checkins
    where group_id = 'd0766666-6666-4666-8666-666666666666'
      and user_id = 'd0777777-7777-4777-8777-777777777777'
      and marked_by = 'd0222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'o estorno apagou a auditoria do comparecimento';
  end if;
end $$;

insert into public.scape_point_entries (
  user_id, kind, points, amount_cents, program, funding,
  backed_points, unbacked_points, idempotency_key
) values
  ('d0555555-5555-4555-8555-555555555555', 'release', 9000, 9000, 'passport', 'unbacked', 0, 9000, 'pp-so-desconto'),
  ('d0666666-6666-4666-8666-666666666666', 'release', 9000, 9000, 'cashback', 'backed', 9000, 0, 'pp-so-vaga');

update public.referral_program_settings
set passport_enabled = true,
    backed_full_slot_enabled = false,
    redeem_min_points = 1,
    redeem_max_bps = 3000
where id = 1;

do $$
declare
  v_on jsonb;
  v_off jsonb;
  v_passport jsonb;
  v_cash jsonb;
begin
  v_on := private.subsidy_quote(
    'd0666666-6666-4666-8666-666666666666', 10000, 10000, 9000, false
  );
  update public.referral_program_settings
  set passport_enabled = false
  where id = 1;
  v_off := private.subsidy_quote(
    'd0666666-6666-4666-8666-666666666666', 10000, 10000, 9000, false
  );
  if v_on <> v_off then
    raise exception 'flag do passaporte desligada mudou a cotacao % vs %', v_on, v_off;
  end if;
  if (v_off ->> 'points')::integer is distinct from 3000 then
    raise exception 'sem a vaga gratis o cashback saiu do teto %', v_off;
  end if;
  update public.referral_program_settings
  set passport_enabled = true,
      backed_full_slot_enabled = true
  where id = 1;
  v_passport := private.subsidy_quote(
    'd0555555-5555-4555-8555-555555555555', 10000, 10000, 9000, false
  );
  v_cash := private.subsidy_quote(
    'd0666666-6666-4666-8666-666666666666', 10000, 10000, 9000, false
  );
  if (v_passport ->> 'points')::integer is distinct from 3000
    or (v_passport ->> 'unbacked_points')::integer is distinct from 3000
    or (v_passport ->> 'backed_points')::integer is distinct from 0
  then
    raise exception 'passaporte nao ficou sem lastro %', v_passport;
  end if;
  if (v_cash ->> 'points')::integer is distinct from 9000
    or (v_cash ->> 'backed_points')::integer is distinct from 9000
  then
    raise exception 'cashback com lastro nao pagou a vaga %', v_cash;
  end if;
  update public.referral_program_settings
  set backed_full_slot_enabled = false
  where id = 1;
end $$;

begin;
select set_config('request.jwt.claim.sub', 'd0111111-1111-4111-8111-111111111111', true);
set local role authenticated;
do $$
begin
  insert into public.passport_stamps (
    user_id, room_id, venue_id, play_count, first_completed_at, last_completed_at
  ) values (
    'd0111111-1111-4111-8111-111111111111',
    'd0633333-3333-4333-8333-333333333333',
    'd0522222-2222-4222-8222-222222222222',
    9, now(), now()
  );
  raise exception 'jogador gravou carimbo direto';
exception
  when insufficient_privilege then
    null;
end $$;
do $$
declare
  v_book jsonb;
begin
  v_book := public.my_passport();
  if (v_book ->> 'enabled')::boolean is not true
    or (v_book ->> 'distinct_rooms')::integer is distinct from 2
    or jsonb_array_length(v_book -> 'stamps') is distinct from 2
  then
    raise exception 'my_passport nao leu o caderno %', v_book;
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'd0444444-4444-4444-8444-444444444444', true);
set local role authenticated;
do $$
declare
  v_seen integer;
begin
  select count(*) into v_seen
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111';
  if v_seen <> 0 then
    raise exception 'outro jogador leu o passaporte';
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'd0222222-2222-4222-8222-222222222222', true);
set local role authenticated;
do $$
declare
  v_seen integer;
begin
  select count(*) into v_seen
  from public.passport_stamps
  where user_id = 'd0111111-1111-4111-8111-111111111111';
  if v_seen <> 2 then
    raise exception 'a casa nao leu os carimbos da propria sala %', v_seen;
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'd0333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_save_passport_settings('{"passport_enabled":false}'::jsonb);
  raise exception 'admin sem aal2 gravou o passaporte';
exception
  when others then
    if sqlerrm <> 'mfa obrigatorio' then
      raise exception 'aal1: %', sqlerrm;
    end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'd0333333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
select public.admin_save_passport_settings('{
  "passport_enabled": false,
  "passport_rooms_5": 5,
  "passport_points_5": 500,
  "passport_rooms_10": 10,
  "passport_points_10": 1000,
  "passport_rooms_25": 25,
  "passport_points_25": 3000,
  "passport_house_points": 300
}'::jsonb);
commit;

do $$
begin
  if public.passport_program_enabled() then
    raise exception 'o admin nao conseguiu desligar a flag';
  end if;
  if (
    select passport_rooms_5 from public.referral_program_settings where id = 1
  ) is distinct from 5 then
    raise exception 'os marcos padrao nao voltaram';
  end if;
end $$;
