-- Admin: só o administrador lê e grava. Jogador, dono e anônimo não.
-- A comissão nova não reescreve o snapshot da cobrança.
-- A taxa do Asaas fica nula até existir o dado.

\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data)
values
  ('ad111111-1111-4111-8111-111111111111', 'admin-painel@example.com', '{"display_name":"Admin Painel"}'),
  ('ad222222-2222-4222-8222-222222222222', 'jogador-painel@example.com', '{"display_name":"Jogador Painel"}'),
  ('ad333333-3333-4333-8333-333333333333', 'dono-painel@example.com', '{"display_name":"Dono Painel"}');

insert into public.admins (user_id)
values ('ad111111-1111-4111-8111-111111111111');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ad311111-1111-4111-8111-111111111111',
  'ad333333-3333-4333-8333-333333333333',
  'curitiba', 'Casa Painel Admin', 'Centro', 'Rua do Painel', '10',
  '80010000', -25.43, -49.27, 4000, 'cnpj', '19191919000181', '4191000001',
  'approved'
), (
  'ad322222-2222-4222-8222-222222222222',
  'ad333333-3333-4333-8333-333333333333',
  'curitiba', 'Casa Pendente Admin', 'Centro', 'Rua da Fila', '11',
  '80010000', -25.43, -49.27, 4000, 'cnpj', '19191919000199', '4191000002',
  'pending'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ad411111-1111-4111-8111-111111111111',
  'ad311111-1111-4111-8111-111111111111',
  'Sala do Painel', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ad421111-1111-4111-8111-111111111111',
  'ad411111-1111-4111-8111-111111111111',
  '2027-10-02 18:00:00+00', 'partner_grid'
);

insert into public.groups (
  id, city_id, venue_id, room_id, session_id, starts_at,
  total_spots, minimum_spots, price_cents, created_by
) values (
  'ad511111-1111-4111-8111-111111111111',
  'curitiba',
  'ad311111-1111-4111-8111-111111111111',
  'ad411111-1111-4111-8111-111111111111',
  'ad421111-1111-4111-8111-111111111111',
  '2027-10-02 18:00:00+00', 4, 2, 10000,
  'ad333333-3333-4333-8333-333333333333'
);

insert into public.payment_charges (
  id, group_id, user_id, venue_id, amount_cents, billing_type, status,
  idempotency_key, wallet_id, commission_bps
) values (
  'ad611111-1111-4111-8111-111111111111',
  'ad511111-1111-4111-8111-111111111111',
  'ad222222-2222-4222-8222-222222222222',
  'ad311111-1111-4111-8111-111111111111',
  10000, 'PIX', 'paid', 'idem-admin-charge', 'wal', 1000
);

do $$
declare
  v_name text;
begin
  foreach v_name in array array[
    'admin_whoami()',
    'admin_list_venues(text,text)',
    'admin_venue(uuid)',
    'admin_review_venue(uuid,text)',
    'admin_suspend_venue(uuid,boolean)',
    'admin_update_venue(uuid,jsonb)',
    'admin_set_commission(uuid,integer)',
    'admin_list_players(text)',
    'admin_player(uuid)',
    'admin_suspend_player(uuid,boolean)',
    'admin_referral_queue()',
    'admin_decide_referral_account(uuid,uuid,text)',
    'admin_reward_settings()',
    'admin_save_reward_settings(jsonb)',
    'admin_reward_history()',
    'admin_earnings(timestamptz,timestamptz,uuid)',
    'admin_highlights()',
    'admin_set_highlight(text,uuid,integer)',
    'admin_audit(integer)'
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
      raise exception 'grant admin fora do combinado: %', v_name;
    end if;
  end loop;

  if has_table_privilege('anon', 'public.admin_audit_log', 'select')
    or has_table_privilege('authenticated', 'public.admin_audit_log', 'select')
    or has_table_privilege('service_role', 'public.admin_audit_log', 'select')
    or has_table_privilege('anon', 'public.reward_settings_changes', 'select')
    or has_table_privilege('authenticated', 'public.reward_settings_changes', 'select')
  then
    raise exception 'tabela de auditoria ainda e legivel pela API';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname = 'profiles_guard'
      and p.prosecdef
  ) then
    raise exception 'profiles_guard virou security definer';
  end if;
end $$;

begin;
set local role anon;
do $$
begin
  perform public.admin_whoami();
  raise exception 'anon entrou no admin';
exception
  when insufficient_privilege then
    null;
end $$;
do $$
begin
  perform public.admin_list_venues(null, null);
  raise exception 'anon listou casas';
exception
  when insufficient_privilege then
    null;
end $$;
do $$
begin
  perform public.admin_earnings(null, null, null);
  raise exception 'anon leu ganhos';
exception
  when insufficient_privilege then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'ad222222-2222-4222-8222-222222222222', true);
set local role authenticated;
do $$
begin
  begin
    perform public.admin_whoami();
    raise exception 'jogador leu whoami';
  exception
    when sqlstate '42501' then
      if sqlerrm not ilike '%not admin%' then
        raise exception 'jogador recebeu outro erro: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_list_venues(null, null);
    raise exception 'jogador listou casas';
  exception
    when sqlstate '42501' then
      if sqlerrm not ilike '%not admin%' then
        raise exception 'list venues: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_earnings(null, null, null);
    raise exception 'jogador leu ganhos';
  exception
    when sqlstate '42501' then
      if sqlerrm not ilike '%not admin%' then
        raise exception 'earnings: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_save_reward_settings('{"welcome_points":1}'::jsonb);
    raise exception 'jogador gravou regra';
  exception
    when sqlstate '42501' then
      if sqlerrm not ilike '%not admin%' then
        raise exception 'settings: %', sqlerrm;
      end if;
  end;
  begin
    perform 1 from public.admin_audit_log;
    raise exception 'jogador leu auditoria';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'ad333333-3333-4333-8333-333333333333', true);
set local role authenticated;
do $$
begin
  perform public.admin_venue('ad311111-1111-4111-8111-111111111111');
  raise exception 'dono abriu a casa no admin';
exception
  when sqlstate '42501' then
    if sqlerrm not ilike '%not admin%' then
      raise exception 'dono recebeu outro erro: %', sqlerrm;
    end if;
end $$;
do $$
begin
  perform public.admin_set_commission(
    'ad311111-1111-4111-8111-111111111111', 2000
  );
  raise exception 'dono mudou a comissao';
exception
  when sqlstate '42501' then
    null;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'ad111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
begin
  perform public.admin_whoami();
  raise exception 'aal1 abriu o console';
exception
  when sqlstate '42501' then
    if sqlerrm not ilike '%mfa%' then
      raise exception 'aal1 recebeu outro erro: %', sqlerrm;
    end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'ad111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_who jsonb;
begin
  v_who := public.admin_whoami();
  if v_who ->> 'user_id' is distinct from 'ad111111-1111-4111-8111-111111111111' then
    raise exception 'aal2 nao entrou: %', v_who;
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', 'ad111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_board jsonb;
  v_snap integer;
  v_after integer;
  v_fee jsonb;
  v_welcome integer;
  v_history jsonb;
  v_review jsonb;
begin
  perform public.admin_set_commission(
    'ad311111-1111-4111-8111-111111111111', 2000
  );
  select commission_bps into v_snap
  from public.payment_charges
  where id = 'ad611111-1111-4111-8111-111111111111';
  if v_snap <> 1000 then
    raise exception 'snapshot da reserva mudou para %', v_snap;
  end if;
  perform public.admin_set_commission(null, 2500);
  select commission_bps into v_after from public.platform_settings where id = 1;
  if v_after <> 2500 then
    raise exception 'oficial nao gravou: %', v_after;
  end if;
  select commission_bps into v_snap
  from public.payment_charges
  where id = 'ad611111-1111-4111-8111-111111111111';
  if v_snap <> 1000 then
    raise exception 'oficial reescreveu a reserva: %', v_snap;
  end if;
  perform public.admin_set_commission(null, 1000);
  begin
    perform public.admin_set_commission(
      'ad311111-1111-4111-8111-111111111111', 3001
    );
    raise exception 'comissao acima de 30 gravou';
  exception
    when sqlstate '22023' then
      if sqlerrm not ilike '%0% e 30%' then
        raise exception 'mensagem da faixa: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_set_commission(
      'ad311111-1111-4111-8111-111111111111', null
    );
    raise exception 'comissao nula gravou';
  exception
    when sqlstate '22023' then
      null;
  end;
  perform public.admin_set_commission(
    'ad311111-1111-4111-8111-111111111111', 2250
  );
  v_review := public.admin_venue('ad311111-1111-4111-8111-111111111111');
  if (v_review ->> 'commission_bps')::integer <> 2250
    or (v_review ->> 'commission_override')::boolean is not true
  then
    raise exception '22,5%% nao gravou: %', v_review -> 'commission_bps';
  end if;
  select commission_bps into v_snap
  from public.payment_charges
  where id = 'ad611111-1111-4111-8111-111111111111';
  if v_snap <> 1000 then
    raise exception '22,5%% reescreveu a reserva: %', v_snap;
  end if;
  perform public.admin_set_commission(
    'ad311111-1111-4111-8111-111111111111', 2000
  );
  perform public.admin_update_venue(
    'ad311111-1111-4111-8111-111111111111',
    '{"neighborhood":"Batel"}'::jsonb
  );
  perform public.admin_suspend_venue(
    'ad311111-1111-4111-8111-111111111111', true
  );
  v_board := public.admin_list_venues('suspended', null);
  if jsonb_array_length(v_board -> 'houses') < 1 then
    raise exception 'fila de suspensas vazia';
  end if;
  v_review := public.admin_review_venue(
    'ad322222-2222-4222-8222-222222222222', 'rejected'
  );
  if v_review ->> 'status' <> 'rejected' then
    raise exception 'reprovacao nao gravou: %', v_review;
  end if;
  v_welcome := (public.admin_reward_settings() ->> 'welcome_points')::integer;
  perform public.admin_save_reward_settings(
    jsonb_build_object('welcome_points', v_welcome + 1)
  );
  v_history := public.admin_reward_history();
  if jsonb_array_length(v_history) < 1 then
    raise exception 'historico de regras vazio';
  end if;
  perform public.admin_save_reward_settings(
    jsonb_build_object('welcome_points', v_welcome)
  );
  -- (a) Média acima do teto. As faixas cabem em [mínimo, máximo],
  -- mas o sorteio jogaria tudo fora e usaria 0,5% fixo.
  begin
    perform public.admin_save_reward_settings(
      jsonb_build_object(
        'cashback_distribution',
        '[{"bps":200,"weight":1},{"bps":400,"weight":1}]'::jsonb
      )
    );
    raise exception 'media acima do teto gravou';
  exception
    when sqlstate '22023' then
      if sqlerrm not ilike '%média ponderada%' then
        raise exception 'mensagem da media: %', sqlerrm;
      end if;
  end;
  -- (b) Min, máx ou teto mudam sem reenviar a distribuição.
  begin
    perform public.admin_save_reward_settings(
      jsonb_build_object('cashback_min_bps', 100)
    );
    raise exception 'minimo novo deixou a faixa antiga';
  exception
    when sqlstate '22023' then
      if sqlerrm not ilike '%média ponderada%' then
        raise exception 'mensagem do minimo: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_save_reward_settings(
      jsonb_build_object('cashback_max_bps', 100)
    );
    raise exception 'maximo novo deixou a faixa antiga';
  exception
    when sqlstate '22023' then
      if sqlerrm not ilike '%média ponderada%' then
        raise exception 'mensagem do maximo: %', sqlerrm;
      end if;
  end;
  begin
    perform public.admin_save_reward_settings(
      jsonb_build_object('cashback_ev_cap_bps', 80)
    );
    raise exception 'teto novo ignoraria a media';
  exception
    when sqlstate '22023' then
      if sqlerrm not ilike '%média ponderada%' then
        raise exception 'mensagem do teto: %', sqlerrm;
      end if;
  end;
  if (public.admin_reward_settings() ->> 'cashback_min_bps')::integer <> 50
    or (public.admin_reward_settings() ->> 'cashback_max_bps')::integer <> 500
    or (public.admin_reward_settings() ->> 'cashback_ev_cap_bps')::integer <> 100
    or (public.admin_reward_settings() -> 'cashback_distribution')
      <> '[{"bps":50,"weight":700},{"bps":100,"weight":170},{"bps":200,"weight":90},{"bps":500,"weight":40}]'::jsonb
  then
    raise exception 'cashback rejeitado alterou o que estava gravado';
  end if;
  begin
    perform public.admin_update_venue(
      'ad311111-1111-4111-8111-111111111111',
      jsonb_build_object('street_address', repeat('R', 201))
    );
    raise exception 'rua longa gravou';
  exception
    when sqlstate '22023' then
      null;
  end;
  begin
    perform public.admin_update_venue(
      'ad311111-1111-4111-8111-111111111111',
      jsonb_build_object('address_number', repeat('9', 31))
    );
    raise exception 'numero longo gravou';
  exception
    when sqlstate '22023' then
      null;
  end;
  v_fee := public.admin_earnings(
    null, null, 'ad311111-1111-4111-8111-111111111111'
  );
  if v_fee -> 'asaas_fee_cents' <> 'null'::jsonb
    or (v_fee ->> 'asaas_fee_rows')::integer <> 0
  then
    raise exception 'taxa inventada: %', v_fee -> 'asaas_fee_cents';
  end if;
end $$;
reset role;

update public.payment_charges
set asaas_fee_cents = 321
where id = 'ad611111-1111-4111-8111-111111111111';
insert into public.venue_referral_entries (
  id, venue_id, kind, amount_cents, program, settlement,
  idempotency_key, review_status
) values (
  'ad711111-1111-4111-8111-111111111111',
  'ad311111-1111-4111-8111-111111111111',
  'accrual', 5000, 'b2c', 'released', 'idem-admin-debt', 'approved'
);
insert into public.venue_credit_clawbacks (
  venue_id, entry_id, amount_cents
) values (
  'ad311111-1111-4111-8111-111111111111',
  'ad711111-1111-4111-8111-111111111111',
  5000
);
insert into public.scape_point_entries (
  id, user_id, kind, points, amount_cents, program,
  idempotency_key, review_status
) values (
  'ad811111-1111-4111-8111-111111111111',
  'ad222222-2222-4222-8222-222222222222',
  'accrual', 10, 10, 'c2c', 'idem-admin-review', 'em_revisao'
);
insert into public.news_items (
  id, venue_id, title, summary, category
) values (
  'ad911111-1111-4111-8111-111111111111',
  'ad311111-1111-4111-8111-111111111111',
  'Novidade do admin', 'Entra no carrossel da home.', 'event'
);

set local role anon;
do $$
begin
  if exists (
    select 1
    from public.venues_vitrine
    where id = 'ad311111-1111-4111-8111-111111111111'
  ) then
    raise exception 'casa suspensa continuou visivel';
  end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'ad111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_fee jsonb;
  v_debt integer;
  v_queue jsonb;
  v_decision jsonb;
begin
  v_fee := public.admin_earnings(
    null, null, 'ad311111-1111-4111-8111-111111111111'
  );
  if (v_fee ->> 'asaas_fee_cents')::integer <> 321 then
    raise exception 'taxa gravada sumiu: %', v_fee -> 'asaas_fee_cents';
  end if;
  select coalesce(sum((item ->> 'open_cents')::integer), 0)
    into v_debt
  from jsonb_array_elements(v_fee -> 'open_components') item
  where item ->> 'kind' = 'clawback'
    and (item ->> 'all_or_nothing')::boolean;
  if v_debt <> 5000 then
    raise exception 'divida tudo-ou-nada: %', v_fee -> 'open_components';
  end if;
  v_queue := public.admin_referral_queue();
  if not exists (
    select 1
    from jsonb_array_elements(v_queue) item
    where item ->> 'subject_user_id' = 'ad222222-2222-4222-8222-222222222222'
  ) then
    raise exception 'fila de revisao sem a conta: %', v_queue;
  end if;
  v_decision := public.admin_decide_referral_account(
    'ad222222-2222-4222-8222-222222222222', null, 'reject'
  );
  if (v_decision ->> 'entries')::integer < 1 then
    raise exception 'rejeicao nao contou';
  end if;
  perform public.admin_set_highlight(
    'room', 'ad411111-1111-4111-8111-111111111111', 1
  );
  perform public.admin_set_highlight(
    'news', 'ad911111-1111-4111-8111-111111111111', 0
  );
  perform public.admin_suspend_player(
    'ad222222-2222-4222-8222-222222222222', true
  );
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ad333333-3333-4333-8333-333333333333', true);
update public.rooms
set featured_rank = 9
where id = 'ad411111-1111-4111-8111-111111111111';
update public.news_items
set title = 'Titulo do dono', carousel_rank = 7
where id = 'ad911111-1111-4111-8111-111111111111';
reset role;

do $$
begin
  if exists (
    select 1 from public.rooms
    where id = 'ad411111-1111-4111-8111-111111111111'
      and featured_rank is distinct from 1
  ) then
    raise exception 'dono mudou o destaque da sala';
  end if;
  if exists (
    select 1 from public.news_items
    where id = 'ad911111-1111-4111-8111-111111111111'
      and (carousel_rank is distinct from 0 or title <> 'Titulo do dono')
  ) then
    raise exception 'carrossel do dono ou titulo travado';
  end if;
end $$;

do $$
begin
  insert into public.group_members (
    group_id, user_id, display_name
  ) values (
    'ad511111-1111-4111-8111-111111111111',
    'ad222222-2222-4222-8222-222222222222',
    'Jogador Painel'
  );
  raise exception 'conta suspensa entrou no grupo';
exception
  when sqlstate '42501' then
    if sqlerrm not ilike '%conta suspensa%' then
      raise exception 'suspensao: %', sqlerrm;
    end if;
end $$;

do $$
begin
  if not exists (
    select 1 from public.admin_audit_log
    where actor_id = 'ad111111-1111-4111-8111-111111111111'
      and action = 'set_commission'
  ) then
    raise exception 'auditoria sem a comissao';
  end if;
end $$;

rollback;
