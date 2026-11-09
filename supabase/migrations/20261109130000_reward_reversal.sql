-- Corrige o upgrade de quem já aplicou o #84 antigo.
-- Recria o lançamento com cashback sorteado e nível, estorna crédito e
-- débito de horário vazio, e não reexecuta migration já registrada.

alter table public.venue_referral_entries
  drop constraint if exists venue_referral_entries_settlement_check;
alter table public.venue_referral_entries
  add constraint venue_referral_entries_settlement_check
  check (settlement in ('pending', 'released', 'applied', 'reversed'));

alter table public.payment_charges
  add column if not exists venue_credit_clawback_cents integer not null default 0;
alter table public.payment_charges
  add column if not exists cashback_refund_cents integer not null default 0;

alter table public.venue_credit_applications
  add column if not exists reversed_at timestamptz;

alter table public.venue_cashback_debits
  add column if not exists voided_at timestamptz;

create table if not exists public.venue_credit_clawbacks (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  entry_id uuid not null references public.venue_referral_entries (id),
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  applied_charge_id uuid references public.payment_charges (id),
  voided_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (entry_id)
);
alter table public.venue_credit_clawbacks enable row level security;
revoke all on table public.venue_credit_clawbacks from public, anon, authenticated, service_role;

create table if not exists public.venue_cashback_refunds (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  debit_id uuid not null references public.venue_cashback_debits (id),
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  applied_charge_id uuid references public.payment_charges (id),
  created_at timestamptz not null default pg_catalog.now(),
  unique (debit_id)
);
alter table public.venue_cashback_refunds enable row level security;
revoke all on table public.venue_cashback_refunds from public, anon, authenticated, service_role;

alter table public.ledger_entries
  drop constraint if exists ledger_entries_kind_check;
alter table public.ledger_entries
  add constraint ledger_entries_kind_check
  check (
    kind in (
      'house_net', 'commission', 'house_refund', 'commission_refund',
      'venue_credit_applied', 'venue_credit_refund',
      'venue_credit_clawback', 'venue_credit_clawback_refund',
      'empty_slot_offset', 'empty_slot_offset_refund', 'empty_slot_refund_reversal'
    )
  );


create or replace function private.referral_reward_gate(
  p_charge_id uuid,
  p_program text,
  p_referrer_user uuid,
  p_referrer_venue uuid,
  p_subject_user uuid,
  p_subject_venue uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_cap integer;
  v_review text;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if private.payer_is_referrer(p_charge_id, p_referrer_user, p_referrer_venue) then
    perform private.withhold_referral(
      p_charge_id, v_charge.user_id, 'payer_is_referrer', p_program
    );
    return 'skip';
  end if;
  select payer_referred_account_cap into v_cap
  from public.referral_program_settings where id = 1;
  if v_charge.payer_document_hash is null
    and v_charge.payer_card_key is null
  then
    return 'em_revisao';
  end if;
  if coalesce(v_cap, 0) > 0
    and not private.payer_subject_known(
      v_charge.payer_document_hash,
      v_charge.payer_card_key,
      p_subject_user,
      p_subject_venue
    )
    and private.payer_rewarded_accounts(
      v_charge.payer_document_hash,
      v_charge.payer_card_key
    ) >= v_cap
  then
    perform private.withhold_referral(
      p_charge_id, v_charge.user_id, 'payer_account_cap', p_program
    );
    return 'skip';
  end if;
  v_review := private.referral_review_status(p_subject_user, p_subject_venue);
  if v_review = 'em_revisao' then
    return 'em_revisao';
  end if;
  return 'post';
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
            v_settings.c2c_bps + private.referrer_tier_bonus(v_player.referrer_user_id)
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
      v_settings.c2b_bps + private.referrer_tier_bonus(v_referrer)
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

create or replace function private.reverse_referral_rewards(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, idempotency_key
  )
  select
    e.user_id,
    'reversal',
    e.points,
    e.amount_cents,
    e.program,
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    'reversal:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  insert into public.venue_referral_entries (
    venue_id, kind, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, idempotency_key
  )
  select
    e.venue_id,
    'reversal',
    e.amount_cents,
    e.program,
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    'reversal:' || e.id::text
  from public.venue_referral_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  update public.venue_referral_entries e
  set settlement = 'reversed'
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and e.settlement in ('pending', 'released')
    and e.applied_cents = 0
    and exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  insert into public.venue_credit_clawbacks (venue_id, entry_id, amount_cents)
  select e.venue_id, e.id, e.applied_cents
  from public.venue_referral_entries e
  where e.kind = 'accrual'
    and e.source_charge_id = p_charge_id
    and e.applied_cents > 0
    and exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and not exists (
      select 1 from public.venue_credit_clawbacks c
      where c.entry_id = e.id and c.voided_at is null
    );


  update public.venue_cashback_debits
  set voided_at = pg_catalog.now()
  where source_charge_id = p_charge_id
    and voided_at is null
    and applied_cents = 0;

  insert into public.venue_cashback_refunds (venue_id, debit_id, amount_cents)
  select d.venue_id, d.id, d.applied_cents
  from public.venue_cashback_debits d
  where d.source_charge_id = p_charge_id
    and d.applied_cents > 0
    and not exists (
      select 1 from public.venue_cashback_refunds f where f.debit_id = d.id
    );

  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    source_charge_id, payment_charge_id, relates_to, client_key, idempotency_key
  )
  select
    e.user_id,
    'redemption_reversal',
    e.points,
    e.amount_cents,
    'redeem',
    e.source_charge_id,
    e.payment_charge_id,
    e.id,
    e.client_key,
    'redemption_reversal:' || e.id::text
  from public.scape_point_entries e
  where e.kind = 'redemption'
    and (
      e.payment_charge_id = p_charge_id
      or e.source_charge_id = p_charge_id
    )
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    );
end;
$$;

create or replace function private.ledger_reverse_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    credit.venue_id,
    credit.group_id,
    credit.user_id,
    credit.account,
    'debit',
    case credit.kind
      when 'commission' then 'commission_refund'
      when 'venue_credit_applied' then 'venue_credit_refund'
      when 'empty_slot_offset_refund' then 'empty_slot_refund_reversal'
      else 'house_refund'
    end,
    credit.amount_cents,
    credit.payment_charge_id
  from public.ledger_entries as credit
  where credit.payment_charge_id = p_charge_id
    and credit.direction = 'credit'
  on conflict (payment_charge_id, kind, direction) do nothing;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id
  )
  select
    debit.venue_id,
    debit.group_id,
    debit.user_id,
    debit.account,
    'credit',
    'venue_credit_clawback_refund',
    debit.amount_cents,
    debit.payment_charge_id
  from public.ledger_entries as debit
  where debit.payment_charge_id = p_charge_id
    and debit.direction = 'debit'
    and debit.kind = 'venue_credit_clawback'
  on conflict (payment_charge_id, kind, direction) do nothing;

  perform private.restore_applied_venue_credits(p_charge_id);
end;
$$;

-- O membro acompanha o status que ficou, não o que o evento pediu.
-- refunded terminal continua released/refunded.
