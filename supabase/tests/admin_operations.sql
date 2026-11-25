-- Admin de salas, sessões e grupos. Anon e sessão sem aal2 não passam.
-- Excluir sessão com jogador pago enfileira estorno integral
-- (organizer_cancelled_event) para quem tem cobrança viva.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('0a111111-1111-4111-8111-111111111111', 'op-admin@example.com', '{"display_name":"Admin Op"}'),
  ('0a222222-2222-4222-8222-222222222222', 'op-pago@example.com', '{"display_name":"Pago Op"}'),
  ('0a333333-3333-4333-8333-333333333333', 'op-aberto@example.com', '{"display_name":"Aberto Op"}'),
  ('0a444444-4444-4444-8444-444444444444', 'op-host@example.com', '{"display_name":"Host Op"}'),
  ('0a555555-5555-4555-8555-555555555555', 'op-solo@example.com', '{"display_name":"Solo Op"}');

insert into public.admins (user_id)
values ('0a111111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  '0b111111-1111-4111-8111-111111111111',
  '0a444444-4444-4444-8444-444444444444',
  'curitiba', 'Casa Operação', 'Centro', 'Rua da Grade', '12',
  '80010000', -25.43, -49.27, 4000, 'cnpj', '19000000000771', '4191000771',
  'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  '0c111111-1111-4111-8111-111111111111',
  '0b111111-1111-4111-8111-111111111111',
  'Sala da Grade', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values
  ('0d111111-1111-4111-8111-111111111111', '0c111111-1111-4111-8111-111111111111', '2027-12-01 18:00:00+00', 'partner_grid'),
  ('0d222222-2222-4222-8222-222222222222', '0c111111-1111-4111-8111-111111111111', '2027-12-02 18:00:00+00', 'partner_grid'),
  ('0d333333-3333-4333-8333-333333333333', '0c111111-1111-4111-8111-111111111111', '2027-12-03 18:00:00+00', 'partner_grid');

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values
  (
    '0e111111-1111-4111-8111-111111111111', 'curitiba',
    '0b111111-1111-4111-8111-111111111111',
    '0c111111-1111-4111-8111-111111111111',
    '0d111111-1111-4111-8111-111111111111',
    '2027-12-01 18:00:00+00', 4, 2, 10000,
    '0a444444-4444-4444-8444-444444444444'
  ),
  (
    '0e222222-2222-4222-8222-222222222222', 'curitiba',
    '0b111111-1111-4111-8111-111111111111',
    '0c111111-1111-4111-8111-111111111111',
    '0d222222-2222-4222-8222-222222222222',
    '2027-12-02 18:00:00+00', 4, 2, 10000,
    '0a444444-4444-4444-8444-444444444444'
  ),
  (
    '0e333333-3333-4333-8333-333333333333', 'curitiba',
    '0b111111-1111-4111-8111-111111111111',
    '0c111111-1111-4111-8111-111111111111',
    '0d333333-3333-4333-8333-333333333333',
    '2027-12-03 18:00:00+00', 4, 2, 10000,
    '0a555555-5555-4555-8555-555555555555'
  );

insert into public.group_members (
  id, group_id, user_id, display_name, is_creator, payment_status
) values
  ('0f111111-1111-4111-8111-111111111111', '0e111111-1111-4111-8111-111111111111', '0a444444-4444-4444-8444-444444444444', 'Host Op', true, 'paid'),
  ('0f222222-2222-4222-8222-222222222222', '0e111111-1111-4111-8111-111111111111', '0a222222-2222-4222-8222-222222222222', 'Pago Op', false, 'paid'),
  ('0f333333-3333-4333-8333-333333333333', '0e111111-1111-4111-8111-111111111111', '0a333333-3333-4333-8333-333333333333', 'Aberto Op', false, 'pending'),
  ('0f444444-4444-4444-8444-444444444444', '0e222222-2222-4222-8222-222222222222', '0a444444-4444-4444-8444-444444444444', 'Host Op', true, 'pending'),
  ('0f555555-5555-4555-8555-555555555555', '0e222222-2222-4222-8222-222222222222', '0a222222-2222-4222-8222-222222222222', 'Pago Op', false, 'paid'),
  ('0f666666-6666-4666-8666-666666666666', '0e333333-3333-4333-8333-333333333333', '0a555555-5555-4555-8555-555555555555', 'Solo Op', true, 'pending');

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, provider_ref, commission_bps
) values
  (
    '0c211111-1111-4111-8111-111111111111',
    '0e111111-1111-4111-8111-111111111111',
    '0a444444-4444-4444-8444-444444444444',
    '0b111111-1111-4111-8111-111111111111',
    10000, 'PIX', 'paid', 'idem-op-host', 'ch_op_host', 2500
  ),
  (
    '0c222222-2222-4222-8222-222222222222',
    '0e111111-1111-4111-8111-111111111111',
    '0a222222-2222-4222-8222-222222222222',
    '0b111111-1111-4111-8111-111111111111',
    10000, 'PIX', 'paid', 'idem-op-pago', 'ch_op_pago', 2500
  ),
  (
    '0c233333-3333-4333-8333-333333333333',
    '0e111111-1111-4111-8111-111111111111',
    '0a333333-3333-4333-8333-333333333333',
    '0b111111-1111-4111-8111-111111111111',
    10000, 'PIX', 'pending', 'idem-op-aberto', 'ch_op_aberto', 2500
  ),
  (
    '0c244444-4444-4444-8444-444444444444',
    '0e222222-2222-4222-8222-222222222222',
    '0a222222-2222-4222-8222-222222222222',
    '0b111111-1111-4111-8111-111111111111',
    10000, 'CREDIT_CARD', 'paid', 'idem-op-remover', 'ch_op_remover', 2500
  );

do $$
declare
  v_name text;
begin
  foreach v_name in array array[
    'admin_list_rooms(uuid,text,boolean,integer,integer)',
    'admin_list_sessions(uuid,timestamptz,timestamptz,text,text,boolean,integer,integer)',
    'admin_list_groups(uuid,timestamptz,timestamptz,text,text,boolean,integer,integer)',
    'admin_group(uuid)',
    'admin_delete_session(uuid,text)',
    'admin_cancel_group(uuid,text)',
    'admin_remove_group_member(uuid,uuid,text)'
  ]
  loop
    if to_regprocedure('public.' || v_name) is null then
      raise exception 'funcao admin ausente: %', v_name;
    end if;
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.oid = to_regprocedure('public.' || v_name)
        and p.prosecdef
        and 'search_path=""' = any (p.proconfig)
    ) then
      raise exception 'admin sem definer ou search_path vazio: %', v_name;
    end if;
    if has_function_privilege('anon', 'public.' || v_name, 'execute')
      or has_function_privilege('service_role', 'public.' || v_name, 'execute')
      or not has_function_privilege('authenticated', 'public.' || v_name, 'execute')
    then
      raise exception 'grant errado: %', v_name;
    end if;
  end loop;
end $$;

begin;
set local role anon;
do $$
begin
  perform public.admin_list_rooms(null, null, false, 10, 0);
  raise exception 'anon listou salas';
exception
  when insufficient_privilege then null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '0a222222-2222-4222-8222-222222222222', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
begin
  perform public.admin_delete_session(
    '0d111111-1111-4111-8111-111111111111', 'EXCLUIR'
  );
  raise exception 'jogador excluiu sessao';
exception
  when insufficient_privilege then null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '0a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_cancel_group(
    '0e222222-2222-4222-8222-222222222222', 'CANCELAR'
  );
  raise exception 'aal1 cancelou grupo';
exception
  when insufficient_privilege then null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '0a111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_rooms jsonb;
  v_groups jsonb;
  v_detail jsonb;
  v_gone jsonb;
begin
  perform public.admin_delete_session(
    '0d111111-1111-4111-8111-111111111111', 'NAO'
  );
  raise exception 'confirmacao fraca passou';
exception
  when sqlstate '22023' then
    if sqlerrm not like '%confirmacao invalida%' then
      raise;
    end if;
end $$;
do $$
declare
  v_rooms jsonb;
  v_groups jsonb;
  v_detail jsonb;
  v_gone jsonb;
  v_queued integer;
begin
  v_rooms := public.admin_list_rooms(
    '0b111111-1111-4111-8111-111111111111', 'Grade', false, 10, 0
  );
  if (v_rooms ->> 'total')::integer <> 1
    or v_rooms -> 'rows' -> 0 ->> 'name' <> 'Sala da Grade'
    or v_rooms -> 'rows' -> 0 ->> 'venue_name' <> 'Casa Operação'
  then
    raise exception 'lista de salas: %', v_rooms;
  end if;

  v_groups := public.admin_list_groups(
    '0b111111-1111-4111-8111-111111111111',
    '2027-12-01 00:00:00+00', '2027-12-02 00:00:00+00',
    'open', null, false, 10, 0
  );
  if (v_groups ->> 'total')::integer <> 1
    or v_groups -> 'rows' -> 0 ->> 'host_name' <> 'Host Op'
    or (v_groups -> 'rows' -> 0 ->> 'filled_spots')::integer <> 3
  then
    raise exception 'lista de grupos: %', v_groups;
  end if;

  v_detail := public.admin_group('0e111111-1111-4111-8111-111111111111');
  if v_detail ->> 'room_name' <> 'Sala da Grade'
    or v_detail ->> 'host_name' <> 'Host Op'
    or (v_detail ->> 'total_spots')::integer <> 4
    or (v_detail ->> 'filled_spots')::integer <> 3
    or jsonb_array_length(v_detail -> 'members') <> 3
    or not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_detail -> 'members') m
      where m ->> 'display_name' = 'Pago Op'
        and m ->> 'charge_status' = 'paid'
        and (m ->> 'amount_cents')::integer = 10000
    )
  then
    raise exception 'detalhe do grupo: %', v_detail;
  end if;

  v_gone := public.admin_delete_session(
    '0d111111-1111-4111-8111-111111111111', 'EXCLUIR'
  );
  if (v_gone ->> 'refunds_queued')::integer <> 3
    or (v_gone ->> 'groups')::integer <> 1
  then
    raise exception 'exclusao: %', v_gone;
  end if;

  perform public.admin_remove_group_member(
    '0e222222-2222-4222-8222-222222222222',
    '0f555555-5555-4555-8555-555555555555',
    'REMOVER'
  );
  perform public.admin_cancel_group(
    '0e333333-3333-4333-8333-333333333333', 'CANCELAR'
  );
end $$;
reset role;
do $$
declare
  v_queued integer;
begin
  if exists (
    select 1 from public.room_sessions
    where id = '0d111111-1111-4111-8111-111111111111'
      and cancelled_at is null
  ) or exists (
    select 1 from public.groups
    where id = '0e111111-1111-4111-8111-111111111111'
      and cancelled_at is null
  ) then
    raise exception 'sessao ou grupo continuou aberto';
  end if;
  select count(*)::integer into v_queued
  from public.member_refund_queue q
  join public.group_members m on m.id = q.member_id
  where q.group_id = '0e111111-1111-4111-8111-111111111111'
    and m.refund_reason = 'organizer_cancelled_event'
    and q.action in ('refund', 'void');
  if v_queued <> 3 then
    raise exception 'fila de estorno da sessao: %', v_queued;
  end if;
  if (
    select count(*) from public.group_members
    where group_id = '0e111111-1111-4111-8111-111111111111'
      and attendance = 'cancelled'
      and refund_reason = 'organizer_cancelled_event'
  ) <> 3 then
    raise exception 'motivo da sessao nao ficou organizer_cancelled_event';
  end if;
  if not exists (
    select 1
    from public.member_refund_queue q
    join public.group_members m on m.id = q.member_id
    where q.member_id = '0f555555-5555-4555-8555-555555555555'
      and m.refund_reason = 'organizer_removed_member'
      and q.action = 'refund'
  ) then
    raise exception 'remover membro nao enfileirou';
  end if;
  if exists (
    select 1 from public.room_sessions
    where id = '0d222222-2222-4222-8222-222222222222'
      and cancelled_at is not null
  ) then
    raise exception 'remover membro cancelou a sessao';
  end if;
  if exists (
    select 1 from public.groups
    where id = '0e333333-3333-4333-8333-333333333333'
      and cancelled_at is null
  ) or exists (
    select 1 from public.room_sessions
    where id = '0d333333-3333-4333-8333-333333333333'
      and cancelled_at is not null
  ) then
    raise exception 'cancelar grupo mexeu na sessao';
  end if;
  if exists (
    select 1 from public.member_refund_queue
    where group_id = '0e333333-3333-4333-8333-333333333333'
  ) then
    raise exception 'grupo sem cobranca entrou na fila';
  end if;
  if not exists (
    select 1 from public.admin_audit_log
    where actor_id = '0a111111-1111-4111-8111-111111111111'
      and action = 'delete_session'
  ) or not exists (
    select 1 from public.admin_audit_log
    where action = 'cancel_group'
  ) or not exists (
    select 1 from public.admin_audit_log
    where action = 'remove_group_member'
  ) then
    raise exception 'auditoria da operacao incompleta';
  end if;
end $$;
rollback;
