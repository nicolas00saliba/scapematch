-- Auditoria de recompensas de 25/11/2026. Não aplicado no remoto.
-- Não publica função e não liga PAGBANK_CAC_TRANSFERS nem
-- backed_full_slot_enabled.
-- Indicador, casa que indica jogador, cashback e casa que indica casa
-- recebem a taxa cheia. O que não cabe na comissão fica em
-- platform_cac_transfers.assumed_cents. A transferência P2P continua
-- só quando free_slot_topup_cents pede dinheiro para a casa, e o worker
-- não envia enquanto a flag estiver desligada.
-- O B2B some só na reserva com o desconto de 20% (código). O de 10% paga.
-- Pontos cobrem até 100% do que o jogador pagaria depois do desconto.
-- A casa fica com a parte exata; a diferença entra no CAC.

alter table public.payment_charges
  add column if not exists first_booking_discount_kind text;

alter table public.payment_charges
  drop constraint if exists payment_charges_first_booking_discount_kind;

alter table public.payment_charges
  add constraint payment_charges_first_booking_discount_kind
  check (
    first_booking_discount_kind is null
    or first_booking_discount_kind in ('coded', 'organic')
  );

comment on column public.payment_charges.first_booking_discount_kind is
  'coded é o desconto de primeira sessão com código (20%). organic é o de 10% sem código.';

create or replace function private.booking_discount_kind(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_discount integer,
  p_subsidy integer
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_coded_bps integer;
  v_organic_bps integer;
  v_coded integer;
  v_organic integer;
  v_room integer;
  v_referred boolean := false;
begin
  if coalesce(p_discount, 0) <= 0 or p_gross is null or p_gross <= 0 then
    return null;
  end if;
  select s.first_booking_discount_bps, s.organic_first_booking_discount_bps
    into v_coded_bps, v_organic_bps
  from public.referral_program_settings s
  where s.id = 1;
  v_coded := private.reward_cents(p_gross, coalesce(v_coded_bps, 0));
  v_organic := private.reward_cents(p_gross, coalesce(v_organic_bps, 0));
  v_room := greatest(p_gross - coalesce(p_subsidy, 0), 0);
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
  if coalesce(v_referred, false) and p_discount = least(v_coded, v_room) then
    return 'coded';
  end if;
  if p_discount = least(v_coded, v_room)
    and p_discount is distinct from least(v_organic, v_room)
  then
    return 'coded';
  end if;
  if p_discount = least(v_organic, v_room) then
    return 'organic';
  end if;
  return 'coded';
end;
$$;

revoke all on function private.booking_discount_kind(uuid, uuid, integer, integer, integer)
  from public, anon, authenticated;

create or replace function private.discount_blocks_b2b(
  p_user_id uuid,
  p_gross integer,
  p_discount integer,
  p_kind text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_coded integer;
  v_organic integer;
begin
  if coalesce(p_discount, 0) <= 0 then
    return false;
  end if;
  if p_kind = 'organic' then
    return false;
  end if;
  if p_kind = 'coded' then
    return true;
  end if;
  select private.reward_cents(p_gross, s.first_booking_discount_bps),
         private.reward_cents(p_gross, s.organic_first_booking_discount_bps)
    into v_coded, v_organic
  from public.referral_program_settings s
  where s.id = 1;
  if p_discount = v_organic and p_discount is distinct from v_coded then
    return false;
  end if;
  return true;
end;
$$;

revoke all on function private.discount_blocks_b2b(uuid, integer, integer, text)
  from public, anon, authenticated;

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
  -- O saldo da comissão não corta o cashback. O que faltar vira CAC.
  v_base := private.reward_cents(v_charge.amount_cents, v_bps);
  -- Horário vazio não dobra cashback nem indicação. A faixa marcada
  -- não muda o ponto, o crédito da casa nem o repasse.
  v_cents := ((v_base + v_extra) / v_value) * v_value;
  v_points := v_cents / v_value;
  v_platform_cost := ((v_base + v_platform_extra) / v_value) * v_value;
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
          v_cents := private.reward_cents(v_gross, v_settings.b2c_bps);
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
          v_cents := private.reward_cents(
            v_gross,
            private.referrer_c2c_bps(v_player.referrer_user_id)
          );
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
    v_cents := private.reward_cents(
      v_gross,
      v_settings.c2b_bps
    );
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

  -- Só o desconto de 20% com código tira o B2B. O de 10% não.
  if private.discount_blocks_b2b(
    v_charge.user_id,
    v_gross,
    v_charge.first_booking_discount_cents,
    v_charge.first_booking_discount_kind
  ) then
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
  v_cents := private.reward_cents(v_gross, v_settings.b2b_bps);
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

create or replace function private.book_platform_cac(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_commission integer;
  v_referral integer;
  v_covered integer;
  v_assumed integer;
  v_amount integer;
  v_cashback integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;

  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_commission := private.reward_cents(v_gross, v_charge.commission_bps);

  select coalesce(sum(s.amount_cents), 0) into v_referral
  from (
    select e.amount_cents
    from public.scape_point_entries e
    where e.source_charge_id = p_charge_id
      and e.kind = 'accrual'
      and e.program in ('c2c', 'c2b')
    union all
    select r.amount_cents
    from public.venue_referral_entries r
    where r.source_charge_id = p_charge_id
      and r.kind = 'accrual'
      and r.program in ('b2c', 'b2b')
  ) s;

  select coalesce(sum(e.amount_cents), 0) into v_cashback
  from public.scape_point_entries e
  where e.source_charge_id = p_charge_id
    and e.kind = 'accrual'
    and e.program = 'cashback';

  select coalesce(sum(t.amount_cents), 0) into v_covered
  from public.free_slot_topups t
  where t.payment_charge_id = p_charge_id
    and t.redemption_id is not null
    and t.voided_at is null;

  v_amount := greatest(
    coalesce(v_charge.free_slot_topup_cents, 0) - v_covered,
    0
  );
  v_assumed := greatest(
    coalesce(v_charge.first_booking_discount_cents, 0)
      + coalesce(v_charge.subsidy_cents, 0)
      + v_referral
      + v_cashback
      - v_commission,
    0
  );
  v_assumed := greatest(v_assumed, v_amount);
  if v_assumed <= 0 then
    return;
  end if;

  insert into public.platform_cac_transfers (
    payment_charge_id, venue_id, amount_cents, assumed_cents, status, paid_at
  ) values (
    v_charge.id,
    v_charge.venue_id,
    v_amount,
    v_assumed,
    case when v_amount = 0 then 'paid' else 'pending' end,
    case when v_amount = 0 then pg_catalog.now() else null end
  )
  on conflict (payment_charge_id) do nothing;
end;
$$;

create or replace function private.subsidy_quote(
  p_user_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_points integer,
  p_lock boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point integer;
  v_available integer;
  v_fee integer;
  v_house integer;
  v_room integer;
  v_max_subsidy integer;
  v_cap_cents integer;
  v_max_points integer;
  v_min integer;
  v_max_bps integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
  v_enabled boolean;
  v_reserve integer;
  v_backed integer;
  v_unbacked integer;
  v_fraud boolean;
  v_reason text;
  v_backed_spend integer := 0;
  v_unbacked_spend integer := 0;
  v_topup integer := 0;
  v_only boolean := false;
  v_full integer;
  v_open_points integer;
  v_ceiling jsonb;
  v_applied jsonb;
begin
  if p_lock then
    perform 1 from public.profiles where id = p_user_id for update;
  end if;
  select
    point_value_cents, redeem_min_points, redeem_max_bps,
    backed_full_slot_enabled
  into v_point, v_min, v_max_bps, v_enabled
  from public.referral_program_settings where id = 1;
  v_point := greatest(coalesce(v_point, 1), 1);
  v_min := coalesce(v_min, 0);
  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := greatest(coalesce(v_available, 0), 0);
  select b.backed_points, b.unbacked_points
    into v_backed, v_unbacked
  from private.scape_funding_balances(p_user_id) b;
  v_backed := least(greatest(coalesce(v_backed, 0), 0), v_available);
  v_unbacked := v_available - v_backed;
  v_fee := private.reward_cents(p_gross, p_commission_bps);
  v_house := p_gross - v_fee;
  v_room := case when p_gross > 1 then p_gross - 1 else 0 end;
  v_cap_cents := private.reward_cents(p_gross, coalesce(v_max_bps, 10000));
  v_max_subsidy := least(greatest(v_fee, 0), v_room, greatest(v_cap_cents, 0));
  v_max_points := v_max_subsidy / v_point;
  if v_available < v_min or v_max_points < v_min then
    v_max_points := 0;
  end if;
  v_fraud := private.backed_extension_blocked(p_user_id);
  if not coalesce(v_enabled, false) or v_fraud then
    v_reason := case
      when not coalesce(v_enabled, false) then null
      else 'antifraud'
    end;
    -- Flag desligada: o teto é o valor da reserva (ou o teto configurado),
    -- não a comissão. Fraude continua no teto antigo.
    if not v_fraud then
      v_open_points := least(p_gross, greatest(v_cap_cents, 0)) / v_point;
    else
      v_open_points := v_max_points;
    end if;
    if v_available < v_min or v_open_points < v_min then
      v_open_points := 0;
    end if;
    v_max_points := v_open_points;
    v_points := least(greatest(coalesce(p_points, 0), 0), v_available, v_max_points);
    if v_points < v_min then
      v_points := 0;
    end if;
    v_unbacked_spend := least(v_points, v_unbacked);
    v_backed_spend := v_points - v_unbacked_spend;
    v_subsidy := v_points * v_point;
    v_charged := p_gross - v_subsidy;
    v_topup := greatest(v_house - v_charged, 0);
    v_only := v_charged = 0 and v_subsidy > 0;
    if v_subsidy = 0 or v_charged <= 0 or v_topup > 0 then
      v_split := null;
    else
      v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
    end if;
  else
    if v_enabled then
      perform pg_catalog.pg_advisory_xact_lock(814201);
      perform 1 from public.referral_program_settings where id = 1 for update;
    end if;
    v_reserve := private.point_reserve_cents();
    v_full := p_gross / v_point;
    v_ceiling := private.allocate_backed_slot(
      least(v_available, v_full), p_gross, v_fee, v_house, v_max_points,
      v_backed, v_unbacked, v_point,
      v_reserve, 0, 0
    );
    if v_available < v_min or coalesce((v_ceiling ->> 'points')::integer, 0) < v_min then
      v_max_points := 0;
    else
      v_max_points := (v_ceiling ->> 'points')::integer;
    end if;
    v_applied := private.allocate_backed_slot(
      least(greatest(coalesce(p_points, 0), 0), v_available),
      p_gross, v_fee, v_house, v_max_points,
      v_backed, v_unbacked, v_point,
      v_reserve, 0, 0
    );
    v_points := coalesce((v_applied ->> 'points')::integer, 0);
    v_backed_spend := coalesce((v_applied ->> 'backed_points')::integer, 0);
    v_unbacked_spend := coalesce((v_applied ->> 'unbacked_points')::integer, 0);
    v_topup := coalesce((v_applied ->> 'topup_cents')::integer, 0);
    if v_points > v_max_points or v_points < v_min then
      v_points := 0;
      v_backed_spend := 0;
      v_unbacked_spend := 0;
      v_topup := 0;
    end if;
    v_subsidy := v_points * v_point;
    v_charged := p_gross - v_subsidy;
    v_only := v_charged = 0 and v_subsidy > 0;
    if v_subsidy = 0 or v_charged <= 0 or v_topup > 0 then
      v_split := null;
    else
      v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
    end if;
    if coalesce((v_applied ->> 'reserve_cut')::boolean, false) then
      v_reason := 'reserve';
    end if;
  end if;
  return pg_catalog.jsonb_build_object(
    'gross_cents', p_gross,
    'charged_cents', v_charged,
    'subsidy_cents', v_subsidy,
    'points', v_points,
    'house_net_cents', v_house,
    'commission_cents', v_fee,
    'split_percent', v_split,
    'max_points', v_max_points,
    'available_points', v_available,
    'point_value_cents', v_point,
    'redeem_min_points', v_min,
    'redeem_max_bps', v_max_bps,
    'backed_points', v_backed_spend,
    'unbacked_points', v_unbacked_spend,
    'topup_cents', v_topup,
    'points_only', v_only,
    'limit_reason', v_reason
  );
end;
$$;

create or replace function private.quote_redemption(
  p_user_id uuid,
  p_venue_id uuid,
  p_gross integer,
  p_commission_bps integer,
  p_points integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote jsonb;
  v_discount integer;
  v_fee integer;
  v_value integer;
  v_min integer;
  v_house integer;
  v_room integer;
  v_cap_points integer;
  v_points integer;
  v_subsidy integer;
  v_charged integer;
  v_split numeric;
  v_cash_min integer;
  v_cash_max integer;
  v_enabled boolean;
  v_topup integer;
  v_only boolean;
  v_backed integer;
  v_unbacked integer;
begin
  v_discount := private.first_booking_discount_for(
    p_user_id, p_venue_id, p_gross, p_commission_bps, 0, null
  );
  v_quote := private.subsidy_quote(
    p_user_id, p_gross, p_commission_bps, p_points, false
  );
  select coalesce(backed_full_slot_enabled, false) into v_enabled
  from public.referral_program_settings where id = 1;
  -- A vaga com a flag ligada continua sem o desconto de primeira sessão.
  -- Com a flag desligada o desconto entra e os pontos cobrem o resto.
  if v_enabled and (
    coalesce((v_quote ->> 'topup_cents')::integer, 0) > 0
    or coalesce((v_quote ->> 'points_only')::boolean, false)
  ) then
    select cashback_min_bps, cashback_max_bps into v_cash_min, v_cash_max
    from public.referral_program_settings where id = 1;
    return v_quote || pg_catalog.jsonb_build_object(
      'first_booking_discount_cents', 0,
      'cashback_min_bps', v_cash_min,
      'cashback_max_bps', v_cash_max
    );
  end if;
  v_fee := (v_quote ->> 'commission_cents')::integer;
  v_value := greatest((v_quote ->> 'point_value_cents')::integer, 1);
  v_min := coalesce((v_quote ->> 'redeem_min_points')::integer, 0);
  v_house := (v_quote ->> 'house_net_cents')::integer;
  -- Pontos cobrem até o que o jogador pagaria depois do desconto.
  -- A taxa estimada da PagBank não entra nesse teto.
  v_room := greatest(p_gross - coalesce(v_discount, 0), 0);
  v_cap_points := least(
    coalesce((v_quote ->> 'max_points')::integer, 0),
    v_room / v_value
  );
  if v_cap_points < v_min then
    v_cap_points := 0;
  end if;
  v_points := least(coalesce((v_quote ->> 'points')::integer, 0), v_cap_points);
  if v_points < v_min then
    v_points := 0;
  end if;
  v_subsidy := v_points * v_value;
  v_charged := greatest(p_gross - v_subsidy - coalesce(v_discount, 0), 0);
  v_topup := greatest(v_house - v_charged, 0);
  v_only := v_charged = 0 and v_subsidy > 0;
  v_unbacked := least(
    v_points, coalesce((v_quote ->> 'unbacked_points')::integer, 0)
  );
  v_backed := v_points - v_unbacked;
  if v_charged <= 0 or v_topup > 0
    or (v_subsidy = 0 and coalesce(v_discount, 0) = 0)
  then
    v_split := null;
  else
    v_split := ceil((v_house::numeric * 1000000) / v_charged) / 10000;
  end if;
  select cashback_min_bps, cashback_max_bps into v_cash_min, v_cash_max
  from public.referral_program_settings where id = 1;
  return v_quote || pg_catalog.jsonb_build_object(
    'points', v_points,
    'subsidy_cents', v_subsidy,
    'charged_cents', v_charged,
    'split_percent', v_split,
    'max_points', v_cap_points,
    'first_booking_discount_cents', v_discount,
    'cashback_min_bps', v_cash_min,
    'cashback_max_bps', v_cash_max,
    'topup_cents', v_topup,
    'points_only', v_only,
    'backed_points', v_backed,
    'unbacked_points', v_unbacked
  );
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
  v_kind text;
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
  v_kind := private.booking_discount_kind(
    v_charge.user_id, v_charge.venue_id, v_gross, v_discount, v_charge.subsidy_cents
  );
  -- Desconto ou pontos que passam do caixa da casa: a casa fica com a
  -- parte exata. Com a flag ligada o crédito antigo em free_slot_topups
  -- continua. Com ela desligada o complemento fica só no CAC.
  if v_charged <= 0 or v_house > v_charged then
    if v_discount = 0
      and exists (
        select 1
        from public.referral_program_settings s
        where s.id = 1 and s.backed_full_slot_enabled
      )
      and private.note_free_slot_shortfall(v_charge.id)
    then
      if v_charge.subsidy_cents > 0 and v_charge.gross_amount_cents is null then
        update public.payment_charges
        set gross_amount_cents = v_gross
        where id = v_charge.id;
      end if;
      return;
    end if;
    update public.payment_charges
    set amount_cents = greatest(v_charged, 0),
        gross_amount_cents = v_gross,
        first_booking_discount_cents = v_discount,
        first_booking_discount_kind = v_kind,
        free_slot_topup_cents = greatest(v_house - greatest(v_charged, 0), 0),
        provider = case
          when greatest(v_charged, 0) = 0 and subsidy_cents > 0 then 'points'
          else provider
        end
    where id = v_charge.id;
    return;
  end if;
  if v_discount > 0 then
    update public.payment_charges
    set first_booking_discount_kind = v_kind
    where id = v_charge.id
      and first_booking_discount_kind is distinct from v_kind;
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
      first_booking_discount_kind = v_kind,
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

create or replace function public.confirm_points_booking(
  p_group_id uuid,
  p_user_id uuid,
  p_venue_id uuid,
  p_idempotency_key text,
  p_wallet_id text,
  p_commission_bps integer,
  p_billing_type text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_redeem public.scape_point_entries%rowtype;
  v_charge public.payment_charges%rowtype;
  v_house integer;
  v_id uuid;
  v_enabled boolean;
begin
  if p_idempotency_key is null or length(pg_catalog.btrim(p_idempotency_key)) < 8 then
    raise exception 'idempotency ausente' using errcode = '22023';
  end if;
  if p_billing_type not in ('PIX', 'CREDIT_CARD') then
    raise exception 'billing invalido' using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  select * into v_charge
  from public.payment_charges
  where group_id = p_group_id
    and user_id = p_user_id
  for update;
  if v_charge.id is not null then
    if v_charge.provider is distinct from 'points' then
      raise exception 'cobranca existente' using errcode = '23505';
    end if;
    return pg_catalog.jsonb_build_object(
      'id', v_charge.id,
      'status', v_charge.status,
      'amount_cents', v_charge.amount_cents,
      'points_only', true,
      'house_fixed_cents', v_charge.house_fixed_cents,
      'topup_cents', v_charge.free_slot_topup_cents
    );
  end if;
  select * into v_redeem
  from public.scape_point_entries e
  where e.user_id = p_user_id
    and e.client_key = p_idempotency_key
    and e.kind = 'redemption'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    );
  if v_redeem.id is null or v_redeem.amount_cents is distinct from v_redeem.gross_cents then
    raise exception 'hold ausente' using errcode = '42501';
  end if;
  v_house := v_redeem.gross_cents - private.reward_cents(
    v_redeem.gross_cents, p_commission_bps
  );
  insert into public.payment_charges (
    group_id, user_id, venue_id, amount_cents, billing_type, status,
    provider, idempotency_key, wallet_id, commission_bps,
    gross_amount_cents, subsidy_cents, points_redeemed,
    free_slot_topup_cents, house_fixed_cents
  ) values (
    p_group_id, p_user_id, p_venue_id, 0, p_billing_type, 'creating',
    'points', p_idempotency_key, p_wallet_id, p_commission_bps,
    v_redeem.gross_cents, v_redeem.amount_cents, v_redeem.points,
    greatest(v_house, 0), 0
  )
  returning id into v_id;
  perform private.attach_point_hold(p_idempotency_key, v_id);
  select coalesce(backed_full_slot_enabled, false) into v_enabled
  from public.referral_program_settings where id = 1;
  -- Com a flag desligada o complemento fica só no CAC. O crédito em
  -- free_slot_topups continua exclusivo da vaga com a flag ligada.
  if v_house > 0 and v_enabled then
    insert into public.free_slot_topups (
      venue_id, user_id, redemption_id, payment_charge_id, amount_cents
    ) values (
      p_venue_id, p_user_id, v_redeem.id, v_id, v_house
    );
  end if;
  perform private.sync_house_fixed(v_id);
  perform private.apply_payment_transition(v_id, 'paid', true);
  select * into v_charge from public.payment_charges where id = v_id;
  return pg_catalog.jsonb_build_object(
    'id', v_charge.id,
    'status', v_charge.status,
    'amount_cents', v_charge.amount_cents,
    'points_only', true,
    'house_fixed_cents', v_charge.house_fixed_cents,
    'topup_cents', v_charge.free_slot_topup_cents
  );
end;
$$;


create or replace function public.settle_points_covered_charge(p_charge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
begin
  if auth.uid() is not null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    raise exception 'charge_not_found' using errcode = 'P0002';
  end if;
  if v_charge.status = 'paid' and v_charge.provider = 'points' then
    return pg_catalog.jsonb_build_object(
      'id', v_charge.id,
      'status', v_charge.status,
      'amount_cents', v_charge.amount_cents,
      'points_only', true
    );
  end if;
  if v_charge.amount_cents <> 0 or v_charge.subsidy_cents <= 0 then
    raise exception 'pontos_incompletos' using errcode = '22023';
  end if;
  update public.payment_charges
  set provider = 'points'
  where id = v_charge.id;
  perform private.apply_payment_transition(v_charge.id, 'paid', true);
  select * into v_charge from public.payment_charges where id = p_charge_id;
  return pg_catalog.jsonb_build_object(
    'id', v_charge.id,
    'status', v_charge.status,
    'amount_cents', v_charge.amount_cents,
    'points_only', true,
    'topup_cents', v_charge.free_slot_topup_cents
  );
end;
$$;

revoke all on function public.settle_points_covered_charge(uuid)
  from public, anon, authenticated;
grant execute on function public.settle_points_covered_charge(uuid) to service_role;
