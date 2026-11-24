-- Regras de 24/11/2026. Não aplicado no remoto. Não publica função.
-- Tira o dobro do horário vazio. Indicação de pessoas vira taxa absoluta
-- por nível. Casa que indica jogador e jogador que indica casa ficam em 5%.
-- Casa que indica casa continua em 5%. 100 pontos = R$ 1.
-- O resgate não exige 1.000 pontos nem para em 30%. A vaga inteira em
-- pontos com lastro usa a reserva. O desconto de 20% não encolhe para
-- evitar prejuízo.

alter table public.referral_program_settings
  add column if not exists c2c_from_bps integer not null default 100
    check (c2c_from_bps between 0 and 10000),
  add column if not exists c2c_mid_active integer not null default 5
    check (c2c_mid_active >= 1),
  add column if not exists c2c_mid_bps integer not null default 250
    check (c2c_mid_bps between 0 and 10000),
  add column if not exists c2c_high_active integer not null default 8
    check (c2c_high_active >= 1),
  add column if not exists c2c_high_bps integer not null default 500
    check (c2c_high_bps between 0 and 10000);

alter table public.referral_program_settings
  drop constraint if exists referral_program_settings_c2c_tiers;

alter table public.referral_program_settings
  add constraint referral_program_settings_c2c_tiers
  check (
    c2c_mid_active < c2c_high_active
    and c2c_from_bps <= c2c_mid_bps
    and c2c_mid_bps <= c2c_high_bps
  );

comment on column public.referral_program_settings.c2c_from_bps is
  'Taxa absoluta da indicação de pessoas a partir do primeiro indicado ativo, em basis points.';
comment on column public.referral_program_settings.c2c_mid_bps is
  'Taxa absoluta da indicação de pessoas a partir de c2c_mid_active indicados ativos.';
comment on column public.referral_program_settings.c2c_high_bps is
  'Taxa absoluta da indicação de pessoas a partir de c2c_high_active indicados ativos.';

alter table public.free_slot_topups
  alter column redemption_id drop not null;

update public.referral_program_settings
set c2b_bps = 500,
    b2c_bps = 500,
    b2b_bps = 500,
    point_value_cents = 1,
    redeem_min_points = 0,
    redeem_max_bps = 10000,
    backed_full_slot_enabled = true,
    first_booking_discount_bps = 2000,
    c2c_from_bps = 100,
    c2c_mid_active = 5,
    c2c_mid_bps = 250,
    c2c_high_active = 8,
    c2c_high_bps = 500
where id = 1;

create or replace function private.referrer_c2c_bps(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_user_id is null then 0
    when private.referrer_active_count(p_user_id) >= s.c2c_high_active then s.c2c_high_bps
    when private.referrer_active_count(p_user_id) >= s.c2c_mid_active then s.c2c_mid_bps
    when private.referrer_active_count(p_user_id) >= 1 then s.c2c_from_bps
    else 0
  end
  from public.referral_program_settings s
  where s.id = 1;
$$;

revoke all on function private.referrer_c2c_bps(uuid) from public, anon, authenticated;

create or replace function private.referrer_tier_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case private.referrer_c2c_bps(p_user_id)
    when s.c2c_high_bps then 'nivel_5'
    when s.c2c_mid_bps then 'nivel_2_5'
    when s.c2c_from_bps then 'nivel_1'
    else 'nenhum'
  end
  from public.referral_program_settings s
  where s.id = 1;
$$;

revoke all on function private.referrer_tier_name(uuid) from public, anon, authenticated;

create or replace function private.post_player_cashback(
  p_charge_id uuid,
  p_pool integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_settings public.referral_program_settings%rowtype;
  v_existing integer;
  v_seed text;
  v_bytes bytea;
  v_total integer := 0;
  v_roll bigint;
  v_bps integer;
  v_row record;
  v_cursor integer := 0;
  v_paid timestamptz;
  v_value integer;
  v_base integer;
  v_extra integer := 0;
  v_house integer := 0;
  v_platform_extra integer := 0;
  v_cents integer;
  v_points integer;
  v_doubled boolean := false;
  v_platform_cost integer;
  v_inserted integer;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null then
    return 0;
  end if;
  select platform_cents into v_existing
  from public.cashback_draws
  where payment_charge_id = p_charge_id;
  -- Replay de webhook e reconciliação devolve o sorteio gravado.
  if found then
    return v_existing;
  end if;
  select * into v_settings from public.referral_program_settings where id = 1;
  v_paid := coalesce(v_charge.paid_at, pg_catalog.now());
  v_value := v_settings.point_value_cents;
  select coalesce(sum(weight), 0)::integer into v_total from private.cashback_distribution();
  if v_total <= 0 then
    return 0;
  end if;
  v_bytes := extensions.gen_random_bytes(16);
  v_seed := pg_catalog.encode(v_bytes, 'hex');
  v_roll := (
    pg_catalog.get_byte(v_bytes, 0)::bigint * 16777216
    + pg_catalog.get_byte(v_bytes, 1)::bigint * 65536
    + pg_catalog.get_byte(v_bytes, 2)::bigint * 256
    + pg_catalog.get_byte(v_bytes, 3)::bigint
  ) % v_total::bigint;
  v_bps := v_settings.cashback_min_bps;
  for v_row in select * from private.cashback_distribution() loop
    v_cursor := v_cursor + v_row.weight;
    if v_roll < v_cursor then
      v_bps := v_row.bps;
      exit;
    end if;
  end loop;
  v_base := least(private.reward_cents(v_charge.amount_cents, v_bps), greatest(p_pool, 0));
  -- Horário vazio não dobra cashback nem indicação. A faixa marcada
  -- não muda o ponto, o crédito da casa nem o repasse.
  v_cents := ((v_base + v_extra) / v_value) * v_value;
  v_points := v_cents / v_value;
  v_platform_cost := least(
    ((v_base + v_platform_extra) / v_value) * v_value,
    greatest(p_pool, 0)
  );
  insert into public.cashback_draws (
    payment_charge_id, user_id, drawn_bps, applied_bps, doubled,
    house_share_cents, platform_cents, seed, distribution
  ) values (
    p_charge_id, v_charge.user_id, v_bps,
    case when v_charge.amount_cents > 0 then (v_cents * 10000) / v_charge.amount_cents else 0 end,
    v_doubled, v_house, v_platform_cost, v_seed, v_settings.cashback_distribution
  )
  on conflict (payment_charge_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select platform_cents into v_platform_cost
    from public.cashback_draws
    where payment_charge_id = p_charge_id;
    return coalesce(v_platform_cost, 0);
  end if;
  if v_house > 0 then
    insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
    values (v_charge.venue_id, p_charge_id, v_house)
    on conflict (source_charge_id) do nothing;
  end if;
  if v_points > 0 then
    insert into public.scape_point_entries (
      user_id, kind, points, amount_cents, program,
      source_charge_id, payment_charge_id, idempotency_key, available_at
    ) values (
      v_charge.user_id, 'accrual', v_points, v_cents, 'cashback',
      p_charge_id, p_charge_id,
      'accrual:' || p_charge_id::text || ':cashback',
      v_paid + make_interval(days => v_settings.hold_days)
    )
    on conflict (idempotency_key) do nothing;
  end if;
  return v_platform_cost;
end;
$$;

create or replace function private.post_referral_rewards(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_settings public.referral_program_settings%rowtype;
  v_player public.referral_attributions%rowtype;
  v_venue public.referral_attributions%rowtype;
  v_gross integer;
  v_pool integer;
  v_paid timestamptz;
  v_reason text;
  v_cents integer;
  v_points integer;
  v_value integer;
  v_existing integer;
  v_referrer uuid;
  v_gate text;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  select * into v_settings from public.referral_program_settings where id = 1;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_pool := greatest(
    private.reward_cents(v_gross, v_charge.commission_bps)
      - v_charge.subsidy_cents
      - v_charge.first_booking_discount_cents,
    0
  );
  v_paid := coalesce(v_charge.paid_at, pg_catalog.now());
  v_value := v_settings.point_value_cents;

  -- Cashback sorteado. Sem as travas de indicação. A função devolve os centavos usados.
  v_cents := private.post_player_cashback(v_charge.id, v_pool);
  v_pool := greatest(v_pool - coalesce(v_cents, 0), 0);

  if private.identity_conflict(v_charge.user_id, null, v_charge.venue_id, null) is not null then
    return;
  end if;

  select * into v_player
  from public.referral_attributions
  where subject_user_id = v_charge.user_id;
  if v_player.id is not null
    and v_player.status = 'active'
    and v_paid >= v_player.starts_at
    and v_paid < v_player.ends_at
  then
    if v_player.referrer_kind = 'player' then
      v_reason := private.identity_conflict(
        v_charge.user_id, v_player.referrer_user_id, null, null
      );
    else
      v_reason := private.identity_conflict(
        v_charge.user_id, null, v_player.referrer_venue_id, null
      );
    end if;
    if v_reason is not null then
      update public.referral_attributions
      set status = 'blocked', block_reason = v_reason
      where id = v_player.id;
    elsif v_player.referrer_kind = 'venue' then
      if v_player.referrer_venue_id is distinct from v_charge.venue_id
        and exists (
          select 1 from public.profiles p
          where p.id = v_charge.user_id and p.cpf is not null
        )
      then
        select amount_cents into v_existing
        from public.venue_referral_entries
        where source_charge_id = v_charge.id
          and program = 'b2c'
          and kind = 'accrual';
        if found then
          v_pool := greatest(v_pool - v_existing, 0);
        else
          v_gate := private.referral_reward_gate(
            v_charge.id, 'b2c', null, v_player.referrer_venue_id,
            v_charge.user_id, null
          );
          v_cents := least(private.reward_cents(v_gross, v_settings.b2c_bps), v_pool);
          if v_gate is distinct from 'skip' and v_cents > 0 then
            insert into public.venue_referral_entries (
              venue_id, kind, amount_cents, program, source_charge_id,
              payment_charge_id, idempotency_key, review_status
            ) values (
              v_player.referrer_venue_id, 'accrual', v_cents, 'b2c',
              v_charge.id, v_charge.id,
              'accrual:' || v_charge.id::text || ':b2c',
              nullif(v_gate, 'post')
            )
            on conflict (idempotency_key) do nothing;
            perform private.note_payer_reward_subject(
              v_charge.id, v_charge.user_id, null
            );
            v_pool := v_pool - v_cents;
          end if;
        end if;
      end if;
    else
      if exists (
        select 1 from public.profiles p
        where p.id = v_charge.user_id and p.cpf is not null
      ) and exists (
        select 1 from public.profiles p
        where p.id = v_player.referrer_user_id and p.cpf is not null
      ) then
        select amount_cents into v_existing
        from public.scape_point_entries
        where source_charge_id = v_charge.id
          and program = 'c2c'
          and kind = 'accrual';
        if found then
          v_pool := greatest(v_pool - v_existing, 0);
        else
          v_gate := private.referral_reward_gate(
            v_charge.id, 'c2c', v_player.referrer_user_id, null,
            v_charge.user_id, null
          );
          v_cents := least(private.reward_cents(
            v_gross,
            private.referrer_c2c_bps(v_player.referrer_user_id)
          ), v_pool);
          v_points := v_cents / v_value;
          v_cents := v_points * v_value;
          if v_gate is distinct from 'skip' and v_points > 0 then
            insert into public.scape_point_entries (
              user_id, kind, points, amount_cents, program,
              source_charge_id, payment_charge_id, idempotency_key, available_at,
              review_status
            ) values (
              v_player.referrer_user_id, 'accrual', v_points, v_cents, 'c2c',
              v_charge.id, v_charge.id,
              'accrual:' || v_charge.id::text || ':c2c',
              v_paid + make_interval(days => v_settings.hold_days),
              nullif(v_gate, 'post')
            )
            on conflict (idempotency_key) do nothing;
            perform private.note_payer_reward_subject(
              v_charge.id, v_charge.user_id, null
            );
            v_pool := v_pool - v_cents;
          end if;
        end if;
      end if;
    end if;
  end if;

  select * into v_venue
  from public.referral_attributions
  where subject_venue_id = v_charge.venue_id;
  if v_venue.id is null
    or v_venue.status <> 'active'
    or v_paid < v_venue.starts_at
    or v_paid >= v_venue.ends_at
  then
    return;
  end if;

  if v_venue.referrer_kind = 'player' then
    v_reason := private.identity_conflict(
      v_venue.referrer_user_id, null, v_charge.venue_id, null
    );
    v_referrer := v_venue.referrer_user_id;
  else
    v_reason := private.identity_conflict(
      null, null, v_charge.venue_id, v_venue.referrer_venue_id
    );
    v_referrer := null;
  end if;
  if v_reason is not null then
    update public.referral_attributions
    set status = 'blocked', block_reason = v_reason
    where id = v_venue.id;
    return;
  end if;

  if v_venue.referrer_kind = 'player' then
    if not exists (
      select 1 from public.profiles p
      where p.id = v_referrer and p.cpf is not null
    ) then
      return;
    end if;
    select amount_cents into v_existing
    from public.scape_point_entries
    where source_charge_id = v_charge.id
      and program = 'c2b'
      and kind = 'accrual';
    if found then
      return;
    end if;
    v_gate := private.referral_reward_gate(
      v_charge.id, 'c2b', v_referrer, null, null, v_charge.venue_id
    );
    v_cents := least(private.reward_cents(
      v_gross,
      v_settings.c2b_bps
    ), v_pool);
    v_points := v_cents / v_value;
    v_cents := v_points * v_value;
    if v_gate = 'skip' or v_points <= 0 then
      return;
    end if;
    insert into public.scape_point_entries (
      user_id, kind, points, amount_cents, program,
      source_charge_id, payment_charge_id, idempotency_key, available_at,
      review_status
    ) values (
      v_referrer, 'accrual', v_points, v_cents, 'c2b',
      v_charge.id, v_charge.id,
      'accrual:' || v_charge.id::text || ':c2b',
      v_paid + make_interval(days => v_settings.hold_days),
      nullif(v_gate, 'post')
    )
    on conflict (idempotency_key) do nothing;
    perform private.note_payer_reward_subject(v_charge.id, null, v_charge.venue_id);
    return;
  end if;

  if v_charge.first_booking_discount_cents > 0 then
    return;
  end if;
  select amount_cents into v_existing
  from public.venue_referral_entries
  where source_charge_id = v_charge.id
    and program = 'b2b'
    and kind = 'accrual';
  if found then
    return;
  end if;
  v_gate := private.referral_reward_gate(
    v_charge.id, 'b2b', null, v_venue.referrer_venue_id, null, v_charge.venue_id
  );
  v_cents := least(private.reward_cents(v_gross, v_settings.b2b_bps), v_pool);
  if v_gate = 'skip' or v_cents <= 0 then
    return;
  end if;
  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program, source_charge_id,
    payment_charge_id, idempotency_key, review_status
  ) values (
    v_venue.referrer_venue_id, 'accrual', v_cents, 'b2b',
    v_charge.id, v_charge.id,
    'accrual:' || v_charge.id::text || ':b2b',
    nullif(v_gate, 'post')
  )
  on conflict (idempotency_key) do nothing;
  perform private.note_payer_reward_subject(v_charge.id, null, v_charge.venue_id);
end;
$$;

create or replace function public.points_reserve_split_cents(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_charged integer,
  p_house_fixed integer,
  p_billing_type text
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.referral_program_settings%rowtype;
  v_player public.referral_attributions%rowtype;
  v_venue public.referral_attributions%rowtype;
  v_now timestamptz := pg_catalog.now();
  v_point integer;
  v_cents integer := 0;
  v_raw integer;
  v_fee integer;
  v_net integer;
begin
  if p_gross is null or p_gross <= 0 or p_charged is null or p_charged <= 0 then
    return 0;
  end if;
  select * into v_settings
  from public.referral_program_settings
  where id = 1;
  if not coalesce(v_settings.backed_full_slot_enabled, false) then
    return 0;
  end if;
  v_point := greatest(coalesce(v_settings.point_value_cents, 1), 1);
  v_cents := public.cashback_reserve_split_cents(p_gross);

  select * into v_player
  from public.referral_attributions
  where subject_user_id = p_user_id;
  if v_player.id is not null
    and v_player.status = 'active'
    and v_player.referrer_kind = 'player'
    and v_now >= v_player.starts_at
    and v_now < v_player.ends_at
  then
    v_raw := private.reward_cents(
      p_gross,
      private.referrer_c2c_bps(v_player.referrer_user_id)
    );
    v_cents := v_cents + (v_raw / v_point) * v_point;
  end if;

  select * into v_venue
  from public.referral_attributions
  where subject_venue_id = p_venue_id;
  if v_venue.id is not null
    and v_venue.status = 'active'
    and v_venue.referrer_kind = 'player'
    and v_now >= v_venue.starts_at
    and v_now < v_venue.ends_at
  then
    v_raw := private.reward_cents(
      p_gross,
      v_settings.c2b_bps
    );
    v_cents := v_cents + (v_raw / v_point) * v_point;
  end if;

  if v_cents <= 0 then
    return 0;
  end if;
  v_fee := private.estimated_receipt_fee_cents(p_billing_type, p_charged);
  v_net := p_charged - greatest(coalesce(v_fee, 0), 0);
  if coalesce(p_house_fixed, 0) + v_cents > v_net then
    return 0;
  end if;
  return v_cents;
end;
$$;

create or replace function public.my_rewards_summary()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_active integer;
  v_bonus integer;
  v_min integer;
  v_pending integer;
  v_available integer;
  v_silver integer;
  v_gold integer;
  v_backed integer;
  v_unbacked integer;
  v_enabled boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points into v_pending, v_available
  from private.scape_balances(v_uid);
  v_active := private.referrer_active_count(v_uid);
  v_bonus := private.referrer_c2c_bps(v_uid);
  select redeem_min_points, c2c_mid_active, c2c_high_active,
         backed_full_slot_enabled
    into v_min, v_silver, v_gold, v_enabled
  from public.referral_program_settings where id = 1;
  select b.backed_points, b.unbacked_points into v_backed, v_unbacked
  from private.scape_funding_balances(v_uid) b;
  return pg_catalog.jsonb_build_object(
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'redeem_min_points', v_min,
    'tier', private.referrer_tier_name(v_uid),
    'tier_bps', v_bonus,
    'tier_bonus_bps', v_bonus,
    'active_referrals', v_active,
    'silver_at', v_silver,
    'gold_at', v_gold,
    'cashback_min_bps', (select cashback_min_bps from public.referral_program_settings where id = 1),
    'cashback_max_bps', (select cashback_max_bps from public.referral_program_settings where id = 1),
    'backed_points', coalesce(v_backed, 0),
    'unbacked_points', coalesce(v_unbacked, 0),
    'backed_full_slot_enabled', coalesce(v_enabled, false),
    'free_slots_used_this_month', private.free_slots_used_this_month(v_uid)
  );
end;
$$;

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
  v_fee integer;
  v_wanted integer;
  v_room integer;
  v_referrer_venue uuid;
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

  if exists (
    select 1
    from public.referral_attributions a
    where a.subject_user_id = p_user_id
      and a.status = 'active'
      and a.referrer_kind in ('player', 'venue')
  ) and not exists (
    select 1
    from public.payment_charges c
    where c.user_id = p_user_id
      and c.status in ('creating', 'pending', 'authorized', 'paid')
      and c.id is distinct from p_except_charge
  ) then
    v_qualifies := true;
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
    end if;
  end if;

  if not v_qualifies then
    return 0;
  end if;

  select first_booking_discount_bps into v_bps
  from public.referral_program_settings where id = 1;
  v_wanted := private.reward_cents(p_gross, coalesce(v_bps, 0));
  -- O desconto de 20% não encolhe para caber na comissão.
  -- O prejuízo inicial fica com a plataforma; a casa recebe o líquido cheio.
  v_room := greatest(p_gross - coalesce(p_subsidy_cents, 0), 0);
  return least(v_wanted, v_room);
end;
$$;

create or replace function private.apply_share_adjustments(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee integer;
  v_house integer;
  v_discount integer;
  v_charged integer;
  v_asaas integer;
  v_net integer;
  v_room integer;
  v_credit integer;
  v_debit integer;
  v_claw integer;
  v_refund integer;
  v_free integer := 0;
  v_free_claw integer := 0;
  v_for_house integer;
  v_split numeric;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return;
  end if;
  perform private.lock_venue_rewards(v_charge.venue_id);
  with pairs as (
    select d.id as debit_id, f.id as refund_id
    from public.venue_cashback_debits d
    join public.venue_cashback_refunds f on f.debit_id = d.id
    where d.venue_id = v_charge.venue_id
      and d.voided_at is null
      and d.applied_cents = 0
      and d.applied_charge_id is null
      and f.voided_at is null
      and f.applied_cents = 0
  ),
  void_refund as (
    update public.venue_cashback_refunds f
    set voided_at = pg_catalog.now()
    from pairs
    where f.id = pairs.refund_id
    returning pairs.debit_id
  )
  update public.venue_cashback_debits d
  set voided_at = pg_catalog.now()
  where d.id in (select debit_id from void_refund);
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  if v_charge.first_booking_discount_cents > 0
    or v_charge.venue_credit_applied_cents > 0
    or v_charge.empty_slot_offset_cents > 0
    or v_charge.free_slot_topup_cents > 0
    or v_charge.free_slot_applied_cents > 0
    or v_charge.free_slot_clawback_cents > 0
  then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_discount := private.first_booking_discount_for(
    v_charge.user_id, v_charge.venue_id, v_gross,
    v_charge.commission_bps, v_charge.subsidy_cents, v_charge.id
  );
  v_fee := private.reward_cents(v_gross, v_charge.commission_bps);
  v_house := v_gross - v_fee;
  v_charged := v_gross - v_charge.subsidy_cents - v_discount;
  if v_charged < 0 then
    v_discount := greatest(v_gross - v_charge.subsidy_cents, 0);
    v_charged := v_gross - v_charge.subsidy_cents - v_discount;
  end if;
  -- A taxa da PagBank não reduz o teto da casa. v_asaas fica só para o declare antigo.
  v_asaas := 0;
  v_net := v_charged;
  -- Desconto de primeira reserva permanece mesmo com prejuízo.
  -- O que a casa não recebe neste caixa vira complemento da reserva.
  if v_discount > 0 and (v_charged <= 0 or v_house > v_charged) then
    update public.payment_charges
    set amount_cents = greatest(v_charged, 0),
        gross_amount_cents = v_gross,
        first_booking_discount_cents = v_discount,
        free_slot_topup_cents = greatest(v_house - greatest(v_charged, 0), 0)
    where id = v_charge.id;
    if not private.note_free_slot_shortfall(v_charge.id)
      and v_house > greatest(v_charged, 0)
    then
      insert into public.free_slot_topups (
        venue_id, user_id, redemption_id, payment_charge_id, amount_cents
      )
      select
        v_charge.venue_id, v_charge.user_id, null, v_charge.id,
        v_house - greatest(v_charged, 0)
      where not exists (
        select 1
        from public.free_slot_topups t
        where t.payment_charge_id = v_charge.id
          and t.redemption_id is null
          and t.voided_at is null
      );
    end if;
    return;
  end if;
  if v_charged <= 0 or v_house > v_charged then
    if private.note_free_slot_shortfall(v_charge.id) then
      if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
        update public.payment_charges
        set gross_amount_cents = v_gross
        where id = v_charge.id;
      end if;
      return;
    end if;
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if v_house > v_net then
    if private.note_free_slot_shortfall(v_charge.id) then
      return;
    end if;
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  v_room := greatest(v_net - v_house, 0);
  v_credit := private.apply_venue_credit(
    v_charge.id, v_charge.venue_id, v_room, false
  );
  v_debit := private.apply_empty_slot_debit(
    v_charge.id, v_charge.venue_id, greatest(v_house, 0), false
  );
  v_for_house := greatest(v_house - v_debit, 0) + v_credit;
  if v_for_house > v_net then
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  v_claw := private.apply_venue_clawback(
    v_charge.id, v_charge.venue_id, greatest(v_house - v_debit, 0)
  );
  v_refund := private.apply_cashback_refund(
    v_charge.id, v_charge.venue_id, greatest(v_room - v_credit, 0)
  );
  v_free := private.apply_free_slot_credit(
    v_charge.id, v_charge.venue_id,
    greatest(v_room - v_credit - v_refund, 0), false
  );
  v_free_claw := private.apply_free_slot_clawback(
    v_charge.id, v_charge.venue_id,
    greatest(v_house - v_debit - v_claw, 0), false
  );
  v_for_house := greatest(v_house - v_debit - v_claw - v_free_claw, 0)
    + v_credit + v_refund + v_free;
  if v_discount = 0 and v_credit = 0 and v_debit = 0 and v_claw = 0
    and v_refund = 0 and v_free = 0 and v_free_claw = 0
  then
    if v_charge.gross_amount_cents is null and v_charge.subsidy_cents > 0 then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if v_for_house > v_net then
    if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
      update public.payment_charges
      set gross_amount_cents = v_gross
      where id = v_charge.id;
    end if;
    return;
  end if;
  if private.apply_venue_credit(v_charge.id, v_charge.venue_id, v_room, true)
    is distinct from v_credit
    or private.apply_empty_slot_debit(
      v_charge.id, v_charge.venue_id, greatest(v_house, 0), true
    ) is distinct from v_debit
    or private.apply_free_slot_credit(
      v_charge.id, v_charge.venue_id,
      greatest(v_room - v_credit - v_refund, 0), true
    ) is distinct from v_free
    or private.apply_free_slot_clawback(
      v_charge.id, v_charge.venue_id,
      greatest(v_house - v_debit - v_claw, 0), true
    ) is distinct from v_free_claw
  then
    raise exception 'ajuste mudou antes de gravar' using errcode = '40001';
  end if;
  v_split := ceil((v_for_house::numeric * 1000000) / v_charged) / 10000;
  update public.payment_charges
  set amount_cents = v_charged,
      gross_amount_cents = v_gross,
      first_booking_discount_cents = v_discount,
      venue_credit_applied_cents = v_credit,
      empty_slot_offset_cents = v_debit,
      venue_credit_clawback_cents = v_claw,
      cashback_refund_cents = v_refund,
      free_slot_applied_cents = v_free,
      free_slot_clawback_cents = v_free_claw,
      split_percent = v_split
  where id = v_charge.id;
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
