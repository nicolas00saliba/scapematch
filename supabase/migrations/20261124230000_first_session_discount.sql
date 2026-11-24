-- Desconto da primeira sessão. Não aplicado no remoto. Não publica função.
-- Com código de jogador ou de casa: first_booking_discount_bps (2000).
-- Sem código: organic_first_booking_discount_bps (1000).
-- O flag profiles.signup_referred é o snapshot do cadastro.
-- create-charge (reserve_pix_charge / reserve_card_charge), a cotação
-- (quote_redemption, chamada por quote_my_point_subsidy) e o CAC
-- (book_platform_cac, a partir do centavo já gravado na cobrança)
-- usam private.first_booking_discount_for.

alter table public.profiles
  add column if not exists signup_referred boolean not null default false;

comment on column public.profiles.signup_referred is
  'Snapshot do cadastro. True quando um código de jogador ou de casa entrou. Não volta para false.';

update public.profiles p
set signup_referred = true
where signup_referred is not true
  and exists (
    select 1
    from public.referral_attributions a
    where a.subject_user_id = p.id
      and a.referrer_kind in ('player', 'venue')
      and a.status = 'active'
  );

alter table public.referral_program_settings
  add column if not exists organic_first_booking_discount_bps integer
    not null default 1000;

alter table public.referral_program_settings
  drop constraint if exists referral_program_settings_organic_discount;

alter table public.referral_program_settings
  add constraint referral_program_settings_organic_discount
  check (organic_first_booking_discount_bps between 0 and 10000);


create or replace function private.first_booking_discount_for(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_subsidy_cents integer,
  p_except_charge uuid
)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_bps integer;
  v_wanted integer;
  v_room integer;
  v_referrer_venue uuid;
  v_referred boolean := false;
  v_first boolean := false;
  v_qualifies boolean := false;
begin
  if p_gross is null or p_gross <= 1 then
    return 0;
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  if exists (
    select 1
    from public.payment_charges c
    where c.user_id = p_user_id
      and c.first_booking_discount_cents > 0
      and c.status in ('creating', 'pending', 'authorized', 'paid')
      and c.id is distinct from p_except_charge
  ) then
    return 0;
  end if;

  -- Snapshot do cadastro. O flag não volta atrás se a atribuição for
  -- bloqueada depois. A atribuição ativa cobre quem entrou antes da coluna.
  select coalesce(p.signup_referred, false) into v_referred
  from public.profiles p
  where p.id = p_user_id;
  if not coalesce(v_referred, false) and exists (
    select 1
    from public.referral_attributions a
    where a.subject_user_id = p_user_id
      and a.status = 'active'
      and a.referrer_kind in ('player', 'venue')
  ) then
    v_referred := true;
  end if;

  v_first := not exists (
    select 1
    from public.payment_charges c
    where c.user_id = p_user_id
      and c.status in ('creating', 'pending', 'authorized', 'paid')
      and c.id is distinct from p_except_charge
  );

  if v_referred and v_first then
    v_qualifies := true;
    select s.first_booking_discount_bps into v_bps
    from public.referral_program_settings s
    where s.id = 1;
  end if;

  if not v_qualifies then
    select a.referrer_venue_id into v_referrer_venue
    from public.referral_attributions a
    where a.subject_venue_id = p_venue_id
      and a.status = 'active'
      and a.referrer_kind = 'venue'
      and a.referrer_venue_id is not null;
    if v_referrer_venue is not null
      and exists (
        select 1
        from public.payment_charges c
        where c.user_id = p_user_id
          and c.venue_id = v_referrer_venue
          and c.status = 'paid'
      )
      and not exists (
        select 1
        from public.payment_charges c
        where c.user_id = p_user_id
          and c.venue_id = p_venue_id
          and c.status in ('creating', 'pending', 'authorized', 'paid')
          and c.id is distinct from p_except_charge
      )
    then
      v_qualifies := true;
      select s.first_booking_discount_bps into v_bps
      from public.referral_program_settings s
      where s.id = 1;
    end if;
  end if;

  if not v_qualifies and v_first then
    v_qualifies := true;
    select s.organic_first_booking_discount_bps into v_bps
    from public.referral_program_settings s
    where s.id = 1;
  end if;

  if not v_qualifies then
    return 0;
  end if;

  v_wanted := private.reward_cents(p_gross, coalesce(v_bps, 0));
  -- O desconto não encolhe para caber na comissão.
  -- O prejuízo inicial fica com a plataforma; a casa recebe o líquido cheio.
  v_room := greatest(p_gross - coalesce(p_subsidy_cents, 0), 0);
  return least(v_wanted, v_room);
end;
$$;

create or replace function private.attach_referral(
  p_subject_kind text,
  p_subject_user uuid,
  p_subject_venue uuid,
  p_code text,
  p_enforce_window boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_owner_kind text;
  v_owner_user uuid;
  v_owner_venue uuid;
  v_started timestamptz;
  v_days integer;
  v_reason text;
begin
  if p_subject_kind = 'player' then
    if exists (
      select 1 from public.referral_attributions
      where subject_user_id = p_subject_user
    ) then
      return 'exists';
    end if;
    select created_at into v_started
    from public.profiles where id = p_subject_user;
  else
    if exists (
      select 1 from public.referral_attributions
      where subject_venue_id = p_subject_venue
    ) then
      return 'exists';
    end if;
    select created_at into v_started
    from public.venues where id = p_subject_venue;
  end if;
  if v_started is null then
    return 'invalid';
  end if;
  if p_enforce_window
    and v_started < pg_catalog.now() - interval '24 hours'
  then
    return 'late';
  end if;

  v_code := pg_catalog.upper(pg_catalog.regexp_replace(
    coalesce(p_code, ''),
    '[^A-Za-z0-9]',
    '',
    'g'
  ));
  if v_code !~ '^[A-Z0-9]{8}$' then
    return 'invalid';
  end if;
  select owner_kind, owner_user_id, owner_venue_id
    into v_owner_kind, v_owner_user, v_owner_venue
  from public.referral_codes
  where code = v_code;
  if v_owner_kind is null then
    return 'invalid';
  end if;
  if p_subject_user is not null and v_owner_user = p_subject_user then
    return 'self';
  end if;
  if p_subject_venue is not null and v_owner_venue = p_subject_venue then
    return 'self';
  end if;

  select attribution_days into v_days
  from public.referral_program_settings
  where id = 1;

  if p_subject_kind = 'player' and v_owner_kind = 'player' then
    v_reason := private.identity_conflict(p_subject_user, v_owner_user, null, null);
  elsif p_subject_kind = 'player' and v_owner_kind = 'venue' then
    v_reason := private.identity_conflict(p_subject_user, null, v_owner_venue, null);
  elsif p_subject_kind = 'venue' and v_owner_kind = 'player' then
    v_reason := private.identity_conflict(v_owner_user, null, p_subject_venue, null);
  else
    v_reason := private.identity_conflict(null, null, p_subject_venue, v_owner_venue);
  end if;

  insert into public.referral_attributions (
    subject_kind, subject_user_id, subject_venue_id,
    referrer_kind, referrer_user_id, referrer_venue_id,
    code, starts_at, ends_at, status, block_reason
  ) values (
    p_subject_kind,
    p_subject_user,
    p_subject_venue,
    v_owner_kind,
    v_owner_user,
    v_owner_venue,
    v_code,
    v_started,
    v_started + make_interval(days => v_days),
    case when v_reason is null then 'active' else 'blocked' end,
    v_reason
  );

  if p_subject_kind = 'venue'
    and v_owner_kind = 'venue'
    and v_reason is null
  then
    perform set_config('scapematch.referral_link', 'on', true);
    update public.venues
    set referred_by = v_owner_venue
    where id = p_subject_venue
      and referred_by is null;
  end if;

  if p_subject_kind = 'player' and v_reason is null then
    update public.profiles
    set signup_referred = true
    where id = p_subject_user
      and signup_referred is not true;
  end if;

  if v_reason is null then
    perform private.flag_same_device_rewards(p_subject_user, p_subject_venue);
    return 'ok';
  end if;
  return 'blocked';
end;
$$;


create or replace function public.admin_save_reward_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_row public.referral_program_settings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_key text;
  v_item jsonb;
  v_bps integer;
  v_weight integer;
  v_weights integer := 0;
  v_ev numeric := 0;
  v_dist_msg text := 'A distribuição de cashback não vale: cada faixa tem de ficar entre o mínimo e o máximo, o peso tem de ser um inteiro maior que zero, e a média ponderada não pode passar do teto.';
begin
  if p_patch is null
    or pg_catalog.jsonb_typeof(p_patch) <> 'object'
    or p_patch = '{}'::jsonb
  then
    raise exception 'patch invalido' using errcode = '22023';
  end if;
  for v_key in select pg_catalog.jsonb_object_keys(p_patch)
  loop
    if v_key not in (
      'c2c_bps', 'b2c_bps', 'c2b_bps', 'b2b_bps',
      'point_value_cents', 'attribution_days', 'hold_days',
      'cashback_bps', 'first_booking_discount_bps',
      'organic_first_booking_discount_bps',
      'redeem_min_points', 'redeem_max_bps', 'welcome_points',
      'cashback_min_bps', 'cashback_max_bps', 'cashback_ev_cap_bps',
      'cashback_distribution', 'empty_slot_house_share_bps',
      'tier_silver_active', 'tier_silver_bonus_bps',
      'tier_gold_active', 'tier_gold_bonus_bps', 'tier_active_days',
      'c2c_from_bps', 'c2c_mid_active', 'c2c_mid_bps',
      'c2c_high_active', 'c2c_high_bps',
      'block_self_payer', 'payer_referred_account_cap',
      'same_device_review_threshold',
      'backed_full_slot_enabled'
    ) then
      raise exception 'campo % nao editavel', v_key using errcode = '22023';
    end if;
  end loop;
  select * into v_row
  from public.referral_program_settings
  where id = 1
  for update;
  v_before := pg_catalog.to_jsonb(v_row);
  v_row.c2c_bps := private.admin_int(p_patch, 'c2c_bps', v_row.c2c_bps, 0, 10000);
  v_row.b2c_bps := private.admin_int(p_patch, 'b2c_bps', v_row.b2c_bps, 0, 10000);
  v_row.c2b_bps := private.admin_int(p_patch, 'c2b_bps', v_row.c2b_bps, 0, 10000);
  v_row.b2b_bps := private.admin_int(p_patch, 'b2b_bps', v_row.b2b_bps, 0, 10000);
  v_row.point_value_cents := private.admin_int(
    p_patch, 'point_value_cents', v_row.point_value_cents, 1, 100
  );
  v_row.attribution_days := private.admin_int(
    p_patch, 'attribution_days', v_row.attribution_days, 1, 3650
  );
  v_row.hold_days := private.admin_int(p_patch, 'hold_days', v_row.hold_days, 0, 3650);
  v_row.cashback_bps := private.admin_int(
    p_patch, 'cashback_bps', v_row.cashback_bps, 0, 10000
  );
  v_row.first_booking_discount_bps := private.admin_int(
    p_patch, 'first_booking_discount_bps', v_row.first_booking_discount_bps, 0, 10000
  );
  v_row.organic_first_booking_discount_bps := private.admin_int(
    p_patch, 'organic_first_booking_discount_bps',
    v_row.organic_first_booking_discount_bps, 0, 10000
  );
  v_row.redeem_min_points := private.admin_int(
    p_patch, 'redeem_min_points', v_row.redeem_min_points, 0, 100000000
  );
  v_row.redeem_max_bps := private.admin_int(
    p_patch, 'redeem_max_bps', v_row.redeem_max_bps, 0, 10000
  );
  v_row.welcome_points := private.admin_int(
    p_patch, 'welcome_points', v_row.welcome_points, 0, 100000000
  );
  v_row.cashback_min_bps := private.admin_int(
    p_patch, 'cashback_min_bps', v_row.cashback_min_bps, 0, 10000
  );
  v_row.cashback_max_bps := private.admin_int(
    p_patch, 'cashback_max_bps', v_row.cashback_max_bps, 0, 10000
  );
  v_row.cashback_ev_cap_bps := private.admin_int(
    p_patch, 'cashback_ev_cap_bps', v_row.cashback_ev_cap_bps, 0, 10000
  );
  v_row.empty_slot_house_share_bps := private.admin_int(
    p_patch, 'empty_slot_house_share_bps', v_row.empty_slot_house_share_bps, 0, 10000
  );
  v_row.tier_silver_active := private.admin_int(
    p_patch, 'tier_silver_active', v_row.tier_silver_active, 0, 1000000
  );
  v_row.tier_silver_bonus_bps := private.admin_int(
    p_patch, 'tier_silver_bonus_bps', v_row.tier_silver_bonus_bps, 0, 10000
  );
  v_row.tier_gold_active := private.admin_int(
    p_patch, 'tier_gold_active', v_row.tier_gold_active, 0, 1000000
  );
  v_row.tier_gold_bonus_bps := private.admin_int(
    p_patch, 'tier_gold_bonus_bps', v_row.tier_gold_bonus_bps, 0, 10000
  );
  v_row.tier_active_days := private.admin_int(
    p_patch, 'tier_active_days', v_row.tier_active_days, 1, 3650
  );
  v_row.c2c_from_bps := private.admin_int(
    p_patch, 'c2c_from_bps', v_row.c2c_from_bps, 0, 10000
  );
  v_row.c2c_mid_active := private.admin_int(
    p_patch, 'c2c_mid_active', v_row.c2c_mid_active, 1, 1000000
  );
  v_row.c2c_mid_bps := private.admin_int(
    p_patch, 'c2c_mid_bps', v_row.c2c_mid_bps, 0, 10000
  );
  v_row.c2c_high_active := private.admin_int(
    p_patch, 'c2c_high_active', v_row.c2c_high_active, 1, 1000000
  );
  v_row.c2c_high_bps := private.admin_int(
    p_patch, 'c2c_high_bps', v_row.c2c_high_bps, 0, 10000
  );
  v_row.payer_referred_account_cap := private.admin_int(
    p_patch, 'payer_referred_account_cap', v_row.payer_referred_account_cap, 0, 1000
  );
  v_row.same_device_review_threshold := private.admin_int(
    p_patch, 'same_device_review_threshold', v_row.same_device_review_threshold, 0, 1000
  );
  if p_patch ? 'block_self_payer' then
    if pg_catalog.jsonb_typeof(p_patch -> 'block_self_payer') <> 'boolean' then
      raise exception 'trava invalida' using errcode = '22023';
    end if;
    v_row.block_self_payer := (p_patch ->> 'block_self_payer')::boolean;
  end if;
  if p_patch ? 'backed_full_slot_enabled' then
    if pg_catalog.jsonb_typeof(p_patch -> 'backed_full_slot_enabled') <> 'boolean' then
      raise exception 'trava invalida' using errcode = '22023';
    end if;
    v_row.backed_full_slot_enabled := (p_patch ->> 'backed_full_slot_enabled')::boolean;
  end if;
  if v_row.cashback_min_bps > v_row.cashback_max_bps then
    raise exception 'faixa de cashback invalida' using errcode = '22023';
  end if;
  if p_patch ? 'cashback_distribution' then
    v_row.cashback_distribution := p_patch -> 'cashback_distribution';
  end if;
  -- O sorteio descarta faixa fora de [mínimo, máximo] e, se a média
  -- passa do teto, volta para o mínimo fixo. O painel não pode gravar
  -- uma configuração que esse sorteio ignoraria.
  v_weights := 0;
  v_ev := 0;
  if pg_catalog.jsonb_typeof(v_row.cashback_distribution) <> 'array'
    or pg_catalog.jsonb_array_length(v_row.cashback_distribution) < 1
  then
    raise exception '%', v_dist_msg using errcode = '22023';
  end if;
  for v_item in
    select value from pg_catalog.jsonb_array_elements(v_row.cashback_distribution)
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
      or (v_item ->> 'bps') is null
      or (v_item ->> 'weight') is null
      or (v_item ->> 'bps') !~ '^[0-9]+$'
      or (v_item ->> 'weight') !~ '^[0-9]+$'
    then
      raise exception '%', v_dist_msg using errcode = '22023';
    end if;
    v_bps := (v_item ->> 'bps')::integer;
    v_weight := (v_item ->> 'weight')::integer;
    if v_weight <= 0
      or v_bps < v_row.cashback_min_bps
      or v_bps > v_row.cashback_max_bps
    then
      raise exception '%', v_dist_msg using errcode = '22023';
    end if;
    v_weights := v_weights + v_weight;
    v_ev := v_ev + (v_bps::numeric * v_weight);
  end loop;
  if v_weights <= 0
    or v_ev / v_weights > v_row.cashback_ev_cap_bps
  then
    raise exception '%', v_dist_msg using errcode = '22023';
  end if;
  update public.referral_program_settings
  set c2c_bps = v_row.c2c_bps,
      b2c_bps = v_row.b2c_bps,
      c2b_bps = v_row.c2b_bps,
      b2b_bps = v_row.b2b_bps,
      point_value_cents = v_row.point_value_cents,
      attribution_days = v_row.attribution_days,
      hold_days = v_row.hold_days,
      cashback_bps = v_row.cashback_bps,
      first_booking_discount_bps = v_row.first_booking_discount_bps,
      organic_first_booking_discount_bps = v_row.organic_first_booking_discount_bps,
      redeem_min_points = v_row.redeem_min_points,
      redeem_max_bps = v_row.redeem_max_bps,
      welcome_points = v_row.welcome_points,
      cashback_min_bps = v_row.cashback_min_bps,
      cashback_max_bps = v_row.cashback_max_bps,
      cashback_ev_cap_bps = v_row.cashback_ev_cap_bps,
      cashback_distribution = v_row.cashback_distribution,
      empty_slot_house_share_bps = v_row.empty_slot_house_share_bps,
      tier_silver_active = v_row.tier_silver_active,
      tier_silver_bonus_bps = v_row.tier_silver_bonus_bps,
      tier_gold_active = v_row.tier_gold_active,
      tier_gold_bonus_bps = v_row.tier_gold_bonus_bps,
      tier_active_days = v_row.tier_active_days,
      c2c_from_bps = v_row.c2c_from_bps,
      c2c_mid_active = v_row.c2c_mid_active,
      c2c_mid_bps = v_row.c2c_mid_bps,
      c2c_high_active = v_row.c2c_high_active,
      c2c_high_bps = v_row.c2c_high_bps,
      block_self_payer = v_row.block_self_payer,
      payer_referred_account_cap = v_row.payer_referred_account_cap,
      same_device_review_threshold = v_row.same_device_review_threshold,
      backed_full_slot_enabled = v_row.backed_full_slot_enabled,
      updated_at = pg_catalog.now()
  where id = 1;
  select pg_catalog.to_jsonb(s) into v_after
  from public.referral_program_settings s where s.id = 1;
  insert into public.reward_settings_changes (actor_id, before_state, after_state)
  values (v_uid, v_before, v_after);
  perform private.admin_audit(
    v_uid, 'save_reward_settings', 'referral_program_settings', '1', v_before, v_after
  );
  return v_after - 'id';
end;
$$;


create or replace function public.reward_rules_public()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'updated_at', s.updated_at,
    'c2c_from_bps', s.c2c_from_bps,
    'c2c_mid_active', s.c2c_mid_active,
    'c2c_mid_bps', s.c2c_mid_bps,
    'c2c_high_active', s.c2c_high_active,
    'c2c_high_bps', s.c2c_high_bps,
    'c2b_bps', s.c2b_bps,
    'b2c_bps', s.b2c_bps,
    'b2b_bps', s.b2b_bps,
    'point_value_cents', s.point_value_cents,
    'first_booking_discount_bps', s.first_booking_discount_bps,
    'organic_first_booking_discount_bps', s.organic_first_booking_discount_bps,
    'redeem_max_bps', s.redeem_max_bps,
    'cashback_min_bps', s.cashback_min_bps,
    'cashback_max_bps', s.cashback_max_bps
  )
  from public.referral_program_settings s
  where s.id = 1;
$$;

comment on function public.reward_rules_public() is
  'Regras vigentes para o app. first_booking_discount_bps é o desconto com código. organic_first_booking_discount_bps é o desconto sem código.';

revoke all on function public.reward_rules_public() from public;
grant execute on function public.reward_rules_public() to anon, authenticated, service_role;
