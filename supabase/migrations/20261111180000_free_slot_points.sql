-- Vaga grátis com pontos de indicação. Não aplicar no projeto remoto.
-- Não cria transferência no Asaas e não mexe em subconta de produção.
-- A flag nasce desligada. Pontos sem lastro continuam no teto antigo.
-- O impacto final no caixa é zero: os 2,5% da indicação já entraram na
-- comissão. Esse valor fica no saldo reservado e paga a casa depois.

alter table public.referral_program_settings
  add column if not exists backed_full_slot_enabled boolean not null default false,
  add column if not exists free_slot_monthly_limit integer not null default 1
    check (free_slot_monthly_limit >= 0);

comment on column public.referral_program_settings.backed_full_slot_enabled is
  'Desligada por padrão. Ligada, pontos de indicação já liberados podem cobrir a vaga inteira, até o saldo reservado. O que passar da comissão vira crédito da casa no próximo repasse.';

comment on column public.referral_program_settings.free_slot_monthly_limit is
  'Vagas em que a plataforma completa o líquido da casa, por jogador e por mês. Zero desliga a extensão.';

alter table public.scape_point_entries
  add column if not exists backed_points integer not null default 0
    check (backed_points >= 0),
  add column if not exists unbacked_points integer not null default 0
    check (unbacked_points >= 0),
  add column if not exists topup_cents integer not null default 0
    check (topup_cents >= 0),
  add column if not exists funding text;

alter table public.scape_point_entries
  drop constraint if exists scape_point_entries_funding_check;

alter table public.scape_point_entries
  add constraint scape_point_entries_funding_check
  check (funding is null or funding in ('backed', 'unbacked', 'mixed'));

alter table public.scape_point_entries
  drop constraint if exists scape_point_entries_funding_split;

alter table public.scape_point_entries
  add constraint scape_point_entries_funding_split
  check (
    kind not in ('redemption', 'redemption_reversal')
    or (backed_points = 0 and unbacked_points = 0)
    or (backed_points + unbacked_points = points)
  );

comment on column public.scape_point_entries.funding is
  'backed: indicação c2c ou c2b, já entrou como comissão. unbacked: boas-vindas, cashback e promoção. mixed: um resgate dos dois.';

alter table public.payment_charges
  add column if not exists free_slot_topup_cents integer not null default 0
    check (free_slot_topup_cents >= 0),
  add column if not exists free_slot_applied_cents integer not null default 0
    check (free_slot_applied_cents >= 0),
  add column if not exists free_slot_clawback_cents integer not null default 0
    check (free_slot_clawback_cents >= 0);

do $$
declare
  v_name text;
begin
  for v_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'payment_charges'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) like '%amount_cents > 0%'
      and pg_get_constraintdef(con.oid) not like '%subsidy%'
      and pg_get_constraintdef(con.oid) not like '%gross%'
  loop
    execute format('alter table public.payment_charges drop constraint %I', v_name);
  end loop;
end $$;

alter table public.payment_charges
  drop constraint if exists payment_charges_amount_cents_check;

alter table public.payment_charges
  add constraint payment_charges_amount_cents_check
  check (
    amount_cents > 0
    or (
      amount_cents = 0
      and provider = 'points'
      and subsidy_cents > 0
    )
  );

alter table public.ledger_entries
  drop constraint if exists ledger_entries_kind_check;

alter table public.ledger_entries
  add constraint ledger_entries_kind_check
  check (
    kind in (
      'house_net', 'commission', 'house_refund', 'commission_refund',
      'venue_credit_applied', 'venue_credit_refund',
      'venue_credit_clawback', 'venue_credit_clawback_refund',
      'venue_credit_clawback_offset',
      'empty_slot_offset', 'empty_slot_offset_refund',
      'empty_slot_offset_undo', 'empty_slot_refund_reversal',
      'free_slot_topup', 'free_slot_clawback',
      'point_reserve'
    )
  );

alter table public.ledger_entries
  drop constraint if exists ledger_entries_account_check;

alter table public.ledger_entries
  add constraint ledger_entries_account_check
  check (account in ('house', 'platform', 'platform_reserve'));

alter table public.ledger_entries
  alter column venue_id drop not null;

alter table public.ledger_entries
  drop constraint if exists ledger_entries_venue_reserve_check;

alter table public.ledger_entries
  add constraint ledger_entries_venue_reserve_check
  check (venue_id is not null or account = 'platform_reserve');

create unique index if not exists ledger_point_reserve_component
  on public.ledger_entries (direction, component_key)
  where account = 'platform_reserve';

create table if not exists public.free_slot_topups (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  redemption_id uuid not null references public.scape_point_entries (id),
  payment_charge_id uuid references public.payment_charges (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  voided_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (redemption_id)
);

create index if not exists free_slot_topups_open
  on public.free_slot_topups (venue_id, created_at)
  where voided_at is null and applied_cents < amount_cents;

create index if not exists free_slot_topups_by_user
  on public.free_slot_topups (user_id, created_at desc);

create table if not exists public.free_slot_applications (
  id uuid primary key default gen_random_uuid(),
  topup_id uuid not null references public.free_slot_topups (id),
  payment_charge_id uuid not null references public.payment_charges (id),
  amount_cents integer not null check (amount_cents > 0),
  reversed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (topup_id, payment_charge_id)
);

create table if not exists public.free_slot_clawbacks (
  id uuid primary key default gen_random_uuid(),
  topup_id uuid not null references public.free_slot_topups (id),
  venue_id uuid not null references public.venues (id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  applied_cents integer not null default 0 check (
    applied_cents >= 0 and applied_cents <= amount_cents
  ),
  applied_charge_id uuid references public.payment_charges (id),
  voided_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  unique (topup_id)
);

create table if not exists public.free_slot_audits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  idempotency_key text,
  payment_charge_id uuid,
  gross_cents integer not null,
  subsidy_cents integer not null,
  backed_points integer not null,
  unbacked_points integer not null,
  topup_cents integer not null,
  points_only boolean not null,
  platform_cash_cents integer not null,
  reserve_cents integer not null,
  monthly_count integer not null,
  monthly_limit integer not null,
  decision text not null check (
    decision in (
      'points_only', 'topup', 'capped', 'reserve',
      'monthly_limit', 'antifraud', 'reversed'
    )
  ),
  created_at timestamptz not null default pg_catalog.now()
);

create index if not exists free_slot_audits_by_user
  on public.free_slot_audits (user_id, created_at desc);

alter table public.free_slot_topups enable row level security;
alter table public.free_slot_applications enable row level security;
alter table public.free_slot_clawbacks enable row level security;
alter table public.free_slot_audits enable row level security;

revoke all on table public.free_slot_topups from public, anon, authenticated, service_role;
revoke all on table public.free_slot_applications from public, anon, authenticated, service_role;
revoke all on table public.free_slot_clawbacks from public, anon, authenticated, service_role;
revoke all on table public.free_slot_audits from public, anon, authenticated, service_role;

grant select on table public.free_slot_topups to authenticated;
grant select on table public.free_slot_audits to authenticated;

create policy free_slot_topups_select on public.free_slot_topups
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.owns_venue(venue_id)
    or private.is_admin_aal2()
  );

create policy free_slot_audits_select on public.free_slot_audits
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_admin_aal2());

create or replace function private.stamp_point_funding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent public.scape_point_entries%rowtype;
begin
  if new.kind = 'redemption_reversal'
    and new.relates_to is not null
    and new.backed_points = 0
    and new.unbacked_points = 0
  then
    select * into v_parent
    from public.scape_point_entries
    where id = new.relates_to;
    if v_parent.id is not null
      and (v_parent.backed_points > 0 or v_parent.unbacked_points > 0)
    then
      new.backed_points := v_parent.backed_points;
      new.unbacked_points := v_parent.unbacked_points;
      new.topup_cents := v_parent.topup_cents;
    end if;
  end if;
  if new.funding is null then
    if new.kind in ('release', 'reversal') and new.relates_to is not null then
      select funding into new.funding
      from public.scape_point_entries
      where id = new.relates_to;
    elsif new.program in ('c2c', 'c2b') then
      new.funding := 'backed';
    elsif new.kind in ('redemption', 'redemption_reversal') then
      if new.backed_points > 0 and new.unbacked_points > 0 then
        new.funding := 'mixed';
      elsif new.backed_points > 0 then
        new.funding := 'backed';
      elsif new.unbacked_points > 0 then
        new.funding := 'unbacked';
      end if;
    else
      new.funding := 'unbacked';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists scape_point_entries_stamp_funding on public.scape_point_entries;
create trigger scape_point_entries_stamp_funding
  before insert on public.scape_point_entries
  for each row execute function private.stamp_point_funding();

create or replace function private.void_free_slot_topup(p_redemption_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.free_slot_topups%rowtype;
begin
  if p_redemption_id is null then
    return;
  end if;
  select * into v_row
  from public.free_slot_topups
  where redemption_id = p_redemption_id
  for update;
  if v_row.id is null or v_row.voided_at is not null then
    return;
  end if;
  if v_row.applied_cents = 0 then
    update public.free_slot_topups
    set voided_at = pg_catalog.now()
    where id = v_row.id;
  else
    insert into public.free_slot_clawbacks (topup_id, venue_id, amount_cents)
    values (v_row.id, v_row.venue_id, v_row.applied_cents)
    on conflict (topup_id) do nothing;
    update public.free_slot_topups
    set amount_cents = applied_cents
    where id = v_row.id
      and applied_cents > 0;
  end if;
  insert into public.free_slot_audits (
    user_id, idempotency_key, payment_charge_id, gross_cents, subsidy_cents,
    backed_points, unbacked_points, topup_cents, points_only,
    platform_cash_cents, reserve_cents, monthly_count, monthly_limit, decision
  )
  select
    v_row.user_id, null, v_row.payment_charge_id, v_row.amount_cents, v_row.amount_cents,
    0, 0, v_row.applied_cents, false,
    0, 0, 0, 0, 'reversed';
end;
$$;

create or replace function private.void_free_slot_on_reversal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'redemption_reversal' and new.relates_to is not null then
    perform private.void_free_slot_topup(new.relates_to);
  end if;
  return new;
end;
$$;

drop trigger if exists scape_point_entries_void_free_slot on public.scape_point_entries;
create trigger scape_point_entries_void_free_slot
  after insert on public.scape_point_entries
  for each row execute function private.void_free_slot_on_reversal();

create or replace function private.scape_funding_balances(p_user_id uuid)
returns table (backed_points integer, unbacked_points integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_backed integer := 0;
  v_unbacked integer := 0;
  v_available integer := 0;
  v_spent_backed integer := 0;
  v_spent_unbacked integer := 0;
  v_legacy integer := 0;
begin
  select coalesce(sum(r.points), 0)::integer into v_backed
  from public.scape_point_entries r
  left join public.scape_point_entries a on a.id = r.relates_to
  where r.user_id = p_user_id
    and r.kind = 'release'
    and coalesce(a.program, r.program) in ('c2c', 'c2b')
    and coalesce(a.review_status, r.review_status) is distinct from 'rejected'
    and coalesce(a.review_status, r.review_status) is distinct from 'em_revisao';

  v_backed := v_backed - coalesce((
    select sum(v.points)::integer
    from public.scape_point_entries v
    left join public.scape_point_entries a on a.id = v.relates_to
    where v.user_id = p_user_id
      and v.kind = 'reversal'
      and coalesce(a.program, v.program) in ('c2c', 'c2b')
      and exists (
        select 1 from public.scape_point_entries rel
        where rel.relates_to = coalesce(a.id, v.relates_to)
          and rel.kind = 'release'
      )
  ), 0);

  select coalesce(sum(r.points), 0)::integer into v_unbacked
  from public.scape_point_entries r
  left join public.scape_point_entries a on a.id = r.relates_to
  where r.user_id = p_user_id
    and r.kind = 'release'
    and coalesce(a.program, r.program) is distinct from 'c2c'
    and coalesce(a.program, r.program) is distinct from 'c2b';

  v_unbacked := v_unbacked - coalesce((
    select sum(v.points)::integer
    from public.scape_point_entries v
    left join public.scape_point_entries a on a.id = v.relates_to
    where v.user_id = p_user_id
      and v.kind = 'reversal'
      and coalesce(a.program, v.program) is distinct from 'c2c'
      and coalesce(a.program, v.program) is distinct from 'c2b'
      and exists (
        select 1 from public.scape_point_entries rel
        where rel.relates_to = coalesce(a.id, v.relates_to)
          and rel.kind = 'release'
      )
  ), 0);

  select
    coalesce(sum(s.backed_points), 0)::integer,
    coalesce(sum(s.unbacked_points), 0)::integer
  into v_spent_backed, v_spent_unbacked
  from public.scape_point_entries s
  where s.user_id = p_user_id
    and s.kind = 'redemption'
    and (s.backed_points > 0 or s.unbacked_points > 0)
    and not exists (
      select 1 from public.scape_point_entries back
      where back.relates_to = s.id and back.kind = 'redemption_reversal'
    );

  v_backed := v_backed - v_spent_backed;
  v_unbacked := v_unbacked - v_spent_unbacked;

  select coalesce(sum(s.points), 0)::integer into v_legacy
  from public.scape_point_entries s
  where s.user_id = p_user_id
    and s.kind = 'redemption'
    and s.backed_points = 0
    and s.unbacked_points = 0
    and not exists (
      select 1 from public.scape_point_entries back
      where back.relates_to = s.id and back.kind = 'redemption_reversal'
    );

  if v_legacy > 0 then
    if v_unbacked >= v_legacy then
      v_unbacked := v_unbacked - v_legacy;
    else
      v_legacy := v_legacy - greatest(v_unbacked, 0);
      v_unbacked := 0;
      v_backed := v_backed - v_legacy;
    end if;
  end if;

  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := greatest(coalesce(v_available, 0), 0);
  if v_backed < 0 then
    v_backed := 0;
  end if;
  if v_backed > v_available then
    v_backed := v_available;
  end if;
  v_unbacked := v_available - v_backed;
  return query select v_backed, v_unbacked;
end;
$$;

create or replace function private.backed_extension_blocked(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.scape_point_entries e
    where e.user_id = p_user_id
      and e.kind = 'accrual'
      and e.program in ('c2c', 'c2b')
      and e.review_status = 'em_revisao'
      and not exists (
        select 1 from public.scape_point_entries r
        where r.relates_to = e.id and r.kind = 'reversal'
      )
  );
$$;

create or replace function private.free_slots_used_this_month(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.free_slot_topups t
  where t.user_id = p_user_id
    and t.voided_at is null
    and t.created_at >= (
      date_trunc(
        'month',
        pg_catalog.now() at time zone 'America/Sao_Paulo'
      ) at time zone 'America/Sao_Paulo'
    );
$$;

create or replace function private.platform_backed_cents()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_points bigint := 0;
  v_value integer := 1;
  v_user uuid;
  v_backed integer;
begin
  select point_value_cents into v_value
  from public.referral_program_settings
  where id = 1;
  v_value := greatest(coalesce(v_value, 1), 1);
  for v_user in select id from auth.users
  loop
    select backed_points into v_backed
    from private.scape_funding_balances(v_user);
    v_points := v_points + greatest(coalesce(v_backed, 0), 0);
  end loop;
  return (v_points * v_value)::integer;
end;
$$;

create or replace function private.open_free_slot_cents()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(amount_cents - applied_cents), 0)::integer
  from public.free_slot_topups
  where voided_at is null
    and applied_cents < amount_cents;
$$;

revoke all on function private.stamp_point_funding() from public, anon, authenticated;
revoke all on function private.void_free_slot_topup(uuid) from public, anon, authenticated;
revoke all on function private.void_free_slot_on_reversal() from public, anon, authenticated;
revoke all on function private.scape_funding_balances(uuid) from public, anon, authenticated;
revoke all on function private.backed_extension_blocked(uuid) from public, anon, authenticated;
revoke all on function private.free_slots_used_this_month(uuid) from public, anon, authenticated;
revoke all on function private.platform_backed_cents() from public, anon, authenticated;
revoke all on function private.open_free_slot_cents() from public, anon, authenticated;

-- Cotação. Com a flag desligada a conta antiga permanece, e o resgate
-- passa a registrar quanto veio de indicação e quanto veio de promoção.

create or replace function private.allocate_backed_slot(
  p_want integer,
  p_gross integer,
  p_commission integer,
  p_house integer,
  p_classic integer,
  p_backed integer,
  p_unbacked integer,
  p_point integer,
  p_cash integer,
  p_open integer,
  p_reserve integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_want integer := greatest(coalesce(p_want, 0), 0);
  v_point integer := greatest(coalesce(p_point, 1), 1);
  v_unbacked integer;
  v_backed integer;
  v_cap integer;
  v_subsidy integer;
  v_charged integer;
  v_fee integer;
  v_net integer;
  v_topup integer;
  v_room integer;
  v_cut boolean := false;
begin
  if v_want > p_backed + p_unbacked then
    v_want := p_backed + p_unbacked;
  end if;
  v_cap := least(greatest(p_classic, 0), greatest(p_unbacked, 0));
  v_unbacked := least(v_want, v_cap);
  v_backed := least(greatest(v_want - v_unbacked, 0), greatest(p_backed, 0));
  v_room := p_cash - p_open - p_reserve;
  loop
    exit when v_backed < 0;
    v_subsidy := (v_unbacked + v_backed) * v_point;
    v_charged := p_gross - v_subsidy;
    if v_charged < 0 then
      v_backed := v_backed - 1;
      continue;
    end if;
    if v_charged = 0 then
      v_fee := 0;
    else
      v_fee := greatest(
        private.estimated_receipt_fee_cents('PIX', v_charged),
        private.estimated_receipt_fee_cents('CREDIT_CARD', v_charged)
      );
    end if;
    v_net := v_charged - v_fee;
    if v_charged > 0 and v_net <= 0 then
      exit when v_backed = 0;
      v_backed := v_backed - 1;
      continue;
    end if;
    if v_charged = 0 then
      v_topup := p_house;
    elsif p_house > v_net then
      v_topup := p_house - v_net;
    else
      v_topup := 0;
    end if;
    if v_backed = 0 then
      return pg_catalog.jsonb_build_object(
        'points', v_unbacked,
        'backed_points', 0,
        'unbacked_points', v_unbacked,
        'topup_cents', 0,
        'reserve_cut', v_cut
      );
    end if;
    if v_topup > v_backed * v_point
      or v_backed * v_point > v_room
      or (v_topup > 0 and v_topup > v_room)
    then
      v_cut := true;
      exit when v_backed = 0;
      v_backed := v_backed - 1;
      continue;
    end if;
    return pg_catalog.jsonb_build_object(
      'points', v_unbacked + v_backed,
      'backed_points', v_backed,
      'unbacked_points', v_unbacked,
      'topup_cents', v_topup,
      'reserve_cut', v_cut
    );
  end loop;
  return pg_catalog.jsonb_build_object(
    'points', v_unbacked,
    'backed_points', 0,
    'unbacked_points', v_unbacked,
    'topup_cents', 0,
    'reserve_cut', v_cut
  );
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
  v_limit integer;
  v_reserve integer;
  v_backed integer;
  v_unbacked integer;
  v_used integer;
  v_fraud boolean;
  v_reason text;
  v_backed_spend integer := 0;
  v_unbacked_spend integer := 0;
  v_topup integer := 0;
  v_only boolean := false;
  v_full integer;
  v_ceiling jsonb;
  v_applied jsonb;
begin
  if p_lock then
    perform 1 from public.profiles where id = p_user_id for update;
  end if;
  select
    point_value_cents, redeem_min_points, redeem_max_bps,
    backed_full_slot_enabled, free_slot_monthly_limit
  into v_point, v_min, v_max_bps, v_enabled, v_limit
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
  v_used := private.free_slots_used_this_month(p_user_id);
  v_fraud := private.backed_extension_blocked(p_user_id);
  if not coalesce(v_enabled, false)
    or v_fraud
    or coalesce(v_limit, 0) <= 0
    or v_used >= v_limit
  then
    v_reason := case
      when not coalesce(v_enabled, false) then null
      when v_fraud then 'antifraud'
      else 'monthly_limit'
    end;
    v_points := least(greatest(coalesce(p_points, 0), 0), v_available, v_max_points);
    if v_points < v_min then
      v_points := 0;
    end if;
    v_unbacked_spend := least(v_points, v_unbacked);
    v_backed_spend := v_points - v_unbacked_spend;
    v_subsidy := v_points * v_point;
    v_charged := p_gross - v_subsidy;
    if v_subsidy = 0 then
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
begin
  v_discount := private.first_booking_discount_for(
    p_user_id, p_venue_id, p_gross, p_commission_bps, 0, null
  );
  v_quote := private.subsidy_quote(
    p_user_id, p_gross, p_commission_bps, p_points, false
  );
  if coalesce((v_quote ->> 'topup_cents')::integer, 0) > 0
    or coalesce((v_quote ->> 'points_only')::boolean, false)
  then
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
  v_room := greatest(least(
    v_fee - v_discount - greatest(
      private.estimated_receipt_fee_cents('PIX', p_gross),
      private.estimated_receipt_fee_cents('CREDIT_CARD', p_gross)
    ),
    p_gross - v_discount - 1
  ), 0);
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
  if v_charged <= 0 or (v_subsidy = 0 and coalesce(v_discount, 0) = 0) then
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
    'cashback_max_bps', v_cash_max
  );
end;
$$;

create or replace function private.hold_point_redemption(
  p_user_id uuid,
  p_idempotency_key text,
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
  v_existing public.scape_point_entries%rowtype;
  v_quote jsonb;
  v_points integer;
  v_subsidy integer;
  v_split numeric;
  v_gross integer;
  v_enabled boolean;
  v_backed integer;
  v_unbacked integer;
  v_topup integer;
  v_funding text;
  v_decision text;
begin
  if p_idempotency_key is null or length(pg_catalog.btrim(p_idempotency_key)) < 8 then
    raise exception 'idempotency ausente' using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = p_user_id for update;
  select backed_full_slot_enabled into v_enabled
  from public.referral_program_settings where id = 1;
  if v_enabled then
    perform 1 from public.referral_program_settings where id = 1 for update;
  end if;
  select e.* into v_existing
  from public.scape_point_entries e
  where e.user_id = p_user_id
    and e.client_key = p_idempotency_key
    and e.kind = 'redemption'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    )
  order by e.created_at desc
  limit 1;
  if v_existing.id is not null then
    return pg_catalog.jsonb_build_object(
      'gross_cents', v_existing.gross_cents,
      'charged_cents', v_existing.gross_cents - v_existing.amount_cents,
      'subsidy_cents', v_existing.amount_cents,
      'points', v_existing.points,
      'house_net_cents', null,
      'split_percent', v_existing.split_percent,
      'backed_points', v_existing.backed_points,
      'unbacked_points', v_existing.unbacked_points,
      'topup_cents', v_existing.topup_cents,
      'points_only', v_existing.gross_cents = v_existing.amount_cents
        and v_existing.amount_cents > 0,
      'held', true
    );
  end if;

  v_quote := private.subsidy_quote(
    p_user_id, p_gross, p_commission_bps, p_points, false
  );
  v_points := (v_quote ->> 'points')::integer;
  v_subsidy := (v_quote ->> 'subsidy_cents')::integer;
  if v_points <= 0 or v_subsidy <= 0 then
    return v_quote || pg_catalog.jsonb_build_object('held', false);
  end if;
  v_split := (v_quote ->> 'split_percent')::numeric;
  v_gross := (v_quote ->> 'gross_cents')::integer;
  v_backed := coalesce((v_quote ->> 'backed_points')::integer, 0);
  v_unbacked := coalesce((v_quote ->> 'unbacked_points')::integer, 0);
  v_topup := coalesce((v_quote ->> 'topup_cents')::integer, 0);
  v_funding := case
    when v_backed > 0 and v_unbacked > 0 then 'mixed'
    when v_backed > 0 then 'backed'
    when v_unbacked > 0 then 'unbacked'
    else null
  end;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, program,
    client_key, gross_cents, split_percent, idempotency_key,
    backed_points, unbacked_points, topup_cents, funding
  ) values (
    p_user_id,
    'redemption',
    v_points,
    v_subsidy,
    'redeem',
    p_idempotency_key,
    v_gross,
    v_split,
    'redeem:' || p_idempotency_key || ':' || gen_random_uuid()::text,
    v_backed,
    v_unbacked,
    v_topup,
    v_funding
  );
  if v_enabled then
    v_decision := case
      when v_quote ->> 'limit_reason' = 'antifraud' then 'antifraud'
      when v_quote ->> 'limit_reason' = 'monthly_limit' then 'monthly_limit'
      when v_quote ->> 'limit_reason' = 'reserve' then 'reserve'
      when coalesce((v_quote ->> 'points_only')::boolean, false) then 'points_only'
      when v_topup > 0 then 'topup'
      else 'capped'
    end;
    insert into public.free_slot_audits (
      user_id, idempotency_key, gross_cents, subsidy_cents,
      backed_points, unbacked_points, topup_cents, points_only,
      platform_cash_cents, reserve_cents, monthly_count, monthly_limit, decision
    )
    select
      p_user_id, p_idempotency_key, v_gross, v_subsidy,
      v_backed, v_unbacked, v_topup,
      coalesce((v_quote ->> 'points_only')::boolean, false),
      private.point_reserve_cents(),
      private.point_reserve_cents(),
      private.free_slots_used_this_month(p_user_id),
      s.free_slot_monthly_limit,
      v_decision
    from public.referral_program_settings s
    where s.id = 1;
  end if;
  return v_quote || pg_catalog.jsonb_build_object('held', true);
end;
$$;

revoke all on function private.allocate_backed_slot(
  integer, integer, integer, integer, integer, integer, integer, integer, integer, integer, integer
) from public, anon, authenticated;

create or replace function private.note_free_slot_shortfall(p_charge_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_redeem public.scape_point_entries%rowtype;
  v_gross integer;
  v_house integer;
  v_net integer;
  v_topup integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return false;
  end if;
  select * into v_redeem
  from public.scape_point_entries e
  where e.payment_charge_id = p_charge_id
    and e.kind = 'redemption'
    and e.topup_cents > 0
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    )
  limit 1;
  if v_redeem.id is null then
    return false;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_house := v_gross - private.reward_cents(v_gross, v_charge.commission_bps);
  v_net := v_charge.amount_cents - private.estimated_receipt_fee_cents(
    v_charge.billing_type, v_charge.amount_cents
  );
  if v_net < 0 then
    v_net := 0;
  end if;
  v_topup := greatest(v_house - v_net, 0);
  if v_topup <= 0 then
    return false;
  end if;
  update public.payment_charges
  set free_slot_topup_cents = v_topup
  where id = p_charge_id;
  insert into public.free_slot_topups (
    venue_id, user_id, redemption_id, payment_charge_id, amount_cents
  ) values (
    v_charge.venue_id, v_charge.user_id, v_redeem.id, v_charge.id, v_topup
  )
  on conflict (redemption_id) do update
  set amount_cents = excluded.amount_cents,
      payment_charge_id = excluded.payment_charge_id
  where public.free_slot_topups.applied_cents = 0
    and public.free_slot_topups.voided_at is null;
  return true;
end;
$$;

create or replace function private.apply_free_slot_credit(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer,
  p_commit boolean
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.free_slot_topups%rowtype;
  v_open integer;
  v_take integer;
begin
  perform private.lock_venue_rewards(p_venue_id);
  if exists (
    select 1 from public.free_slot_applications
    where payment_charge_id = p_charge_id
      and reversed_at is null
  ) then
    select coalesce(sum(amount_cents), 0)::integer into v_taken
    from public.free_slot_applications
    where payment_charge_id = p_charge_id
      and reversed_at is null;
    return v_taken;
  end if;
  if v_left <= 0 then
    return 0;
  end if;
  for v_row in
    select *
    from public.free_slot_topups
    where venue_id = p_venue_id
      and voided_at is null
      and applied_cents < amount_cents
      and payment_charge_id is distinct from p_charge_id
    order by created_at
    for update
  loop
    exit when v_left <= 0;
    v_open := v_row.amount_cents - v_row.applied_cents;
    v_take := least(v_open, v_left);
    if v_take <= 0 then
      continue;
    end if;
    if p_commit then
      update public.free_slot_topups
      set applied_cents = applied_cents + v_take
      where id = v_row.id
        and applied_cents + v_take <= amount_cents
        and voided_at is null;
      if not found then
        continue;
      end if;
      insert into public.free_slot_applications (
        topup_id, payment_charge_id, amount_cents
      ) values (v_row.id, p_charge_id, v_take);
    end if;
    v_left := v_left - v_take;
    v_taken := v_taken + v_take;
  end loop;
  return v_taken;
end;
$$;

create or replace function private.apply_free_slot_clawback(
  p_charge_id uuid,
  p_venue_id uuid,
  p_room integer,
  p_commit boolean
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := greatest(coalesce(p_room, 0), 0);
  v_taken integer := 0;
  v_row public.free_slot_clawbacks%rowtype;
  v_open integer;
  v_take integer;
begin
  perform private.lock_venue_rewards(p_venue_id);
  if exists (
    select 1 from public.free_slot_clawbacks
    where applied_charge_id = p_charge_id
      and voided_at is null
      and applied_cents > 0
  ) then
    select coalesce(sum(applied_cents), 0)::integer into v_taken
    from public.free_slot_clawbacks
    where applied_charge_id = p_charge_id
      and voided_at is null;
    return v_taken;
  end if;
  if v_left <= 0 then
    return 0;
  end if;
  for v_row in
    select *
    from public.free_slot_clawbacks
    where venue_id = p_venue_id
      and voided_at is null
      and applied_cents < amount_cents
      and applied_charge_id is null
    order by created_at
    for update
  loop
    exit when v_left <= 0;
    v_open := v_row.amount_cents - v_row.applied_cents;
    if v_open <= 0 or v_open > v_left then
      continue;
    end if;
    v_take := v_open;
    if p_commit then
      update public.free_slot_clawbacks
      set applied_cents = amount_cents,
          applied_charge_id = p_charge_id
      where id = v_row.id
        and applied_charge_id is null
        and applied_cents = 0;
      if not found then
        continue;
      end if;
    end if;
    v_left := v_left - v_take;
    v_taken := v_taken + v_take;
  end loop;
  return v_taken;
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
  if v_charged <= 0 or v_house > v_charged then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
  end if;
  v_asaas := private.estimated_receipt_fee_cents(
    v_charge.billing_type, v_charged
  );
  v_net := v_charged - v_asaas;
  if v_discount > 0 and v_house > v_net then
    v_discount := 0;
    v_charged := v_gross - v_charge.subsidy_cents;
    v_asaas := private.estimated_receipt_fee_cents(
      v_charge.billing_type, v_charged
    );
    v_net := v_charged - v_asaas;
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

create or replace function private.sync_house_fixed(p_charge_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fixed integer;
  v_net integer;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null then
    return 0;
  end if;
  v_gross := coalesce(
    v_charge.gross_amount_cents,
    v_charge.amount_cents + v_charge.subsidy_cents
  );
  v_fixed := v_gross
    - private.reward_cents(v_gross, v_charge.commission_bps)
    + v_charge.venue_credit_applied_cents
    + v_charge.free_slot_applied_cents
    - v_charge.empty_slot_offset_cents
    - v_charge.venue_credit_clawback_cents
    - v_charge.free_slot_clawback_cents
    - v_charge.free_slot_topup_cents
    + v_charge.cashback_refund_cents;
  if v_fixed < 0 then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  v_net := v_charge.amount_cents
    - private.estimated_receipt_fee_cents(
      v_charge.billing_type, v_charge.amount_cents
    );
  if v_fixed > v_net then
    raise exception 'split_excede_liquido' using errcode = '23514';
  end if;
  update public.payment_charges
  set house_fixed_cents = v_fixed
  where id = p_charge_id;
  return v_fixed;
end;
$$;

create or replace function private.ledger_credit_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_gross integer;
  v_fee_gross integer;
  v_fee integer;
  v_net integer;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if v_charge.id is null or v_charge.status <> 'paid' then
    return;
  end if;
  if v_charge.provider = 'points' then
    return;
  end if;
  v_gross := coalesce(v_charge.gross_amount_cents, v_charge.amount_cents);
  v_fee_gross := ((v_gross::bigint * v_charge.commission_bps + 5000) / 10000)::integer;
  v_fee := v_fee_gross
    - v_charge.subsidy_cents
    - v_charge.first_booking_discount_cents
    - v_charge.venue_credit_applied_cents
    - v_charge.free_slot_applied_cents
    + v_charge.empty_slot_offset_cents
    + v_charge.venue_credit_clawback_cents
    + v_charge.free_slot_clawback_cents
    + v_charge.free_slot_topup_cents
    - v_charge.cashback_refund_cents;
  v_net := v_gross - v_fee_gross;
  if v_charge.free_slot_topup_cents > 0 then
    v_net := greatest(
      v_charge.amount_cents - private.estimated_receipt_fee_cents(
        v_charge.billing_type, v_charge.amount_cents
      ),
      0
    );
  end if;
  if v_net < 0 or v_fee < 0 then
    raise exception 'comissao negativa' using errcode = '23514';
  end if;
  if v_net > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'house', 'credit', 'house_net', v_net, v_charge.id, ''
    ) on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  end if;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'venue_credit_applied',
    a.amount_cents, v_charge.id, a.entry_id::text
  from public.venue_credit_applications a
  where a.payment_charge_id = v_charge.id
    and a.reversed_at is null
    and a.amount_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'venue_credit_clawback',
    c.applied_cents, v_charge.id, c.id::text
  from public.venue_credit_clawbacks c
  where c.applied_charge_id = v_charge.id
    and c.voided_at is null
    and c.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'free_slot_topup',
    a.amount_cents, v_charge.id, a.id::text
  from public.free_slot_applications a
  where a.payment_charge_id = v_charge.id
    and a.reversed_at is null
    and a.amount_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'free_slot_clawback',
    c.applied_cents, v_charge.id, c.id::text
  from public.free_slot_clawbacks c
  where c.applied_charge_id = v_charge.id
    and c.voided_at is null
    and c.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'credit', 'empty_slot_offset_refund',
    f.applied_cents, v_charge.id, f.id::text
  from public.venue_cashback_refunds f
  where f.applied_charge_id = v_charge.id
    and f.voided_at is null
    and f.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    v_charge.venue_id, v_charge.group_id, v_charge.user_id,
    'house', 'debit', 'empty_slot_offset',
    d.applied_cents, v_charge.id, d.id::text
  from public.venue_cashback_debits d
  where d.applied_charge_id = v_charge.id
    and d.voided_at is null
    and d.applied_cents > 0
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  if v_fee > 0 then
    insert into public.ledger_entries (
      venue_id, group_id, user_id, account, direction, kind,
      amount_cents, payment_charge_id, component_key
    ) values (
      v_charge.venue_id, v_charge.group_id, v_charge.user_id,
      'platform', 'credit', 'commission', v_fee, v_charge.id, ''
    ) on conflict (payment_charge_id, kind, direction, component_key) do nothing;
  end if;
end;
$$;

revoke all on function private.note_free_slot_shortfall(uuid) from public, anon, authenticated;
revoke all on function private.apply_free_slot_credit(uuid, uuid, integer, boolean) from public, anon, authenticated;
revoke all on function private.apply_free_slot_clawback(uuid, uuid, integer, boolean) from public, anon, authenticated;

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
  if v_house > 0 then
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

revoke all on function public.confirm_points_booking(uuid, uuid, uuid, text, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.confirm_points_booking(uuid, uuid, uuid, text, text, integer, text)
  to service_role;

create or replace function private.release_unpaid_components(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_status is null or v_status in ('paid', 'refunded', 'authorized') then
    return;
  end if;

  perform private.lock_venue_rewards(ch.venue_id)
  from public.payment_charges ch
  where ch.id = p_charge_id;

  update public.venue_credit_clawbacks c
  set voided_at = pg_catalog.now()
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.entry_id = c.entry_id
    and c.voided_at is null
    and c.neutralized_at is null
    and (c.applied_charge_id is null or c.applied_charge_id = p_charge_id);

  update public.venue_credit_clawbacks
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null
    and neutralized_at is null;

  update public.venue_referral_entries e
  set applied_cents = greatest(e.applied_cents - a.amount_cents, 0),
      settlement = case
        when e.applied_cents - a.amount_cents <= 0 then 'released'
        else e.settlement
      end
  from public.venue_credit_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and a.entry_id = e.id
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    );

  delete from public.venue_credit_applications
  where payment_charge_id = p_charge_id;

  update public.venue_cashback_refunds f
  set voided_at = pg_catalog.now()
  from public.venue_cashback_debits d
  where d.applied_charge_id = p_charge_id
    and f.debit_id = d.id
    and f.voided_at is null
    and f.applied_cents = 0;

  update public.venue_cashback_debits
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null;

  update public.venue_cashback_refunds
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null;

  update public.free_slot_topups t
  set applied_cents = greatest(t.applied_cents - a.amount_cents, 0)
  from public.free_slot_applications a
  where a.payment_charge_id = p_charge_id
    and a.reversed_at is null
    and a.topup_id = t.id;

  update public.free_slot_applications
  set reversed_at = pg_catalog.now()
  where payment_charge_id = p_charge_id
    and reversed_at is null;

  update public.free_slot_clawbacks
  set applied_cents = 0,
      applied_charge_id = null
  where applied_charge_id = p_charge_id
    and voided_at is null;

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
  where e.payment_charge_id = p_charge_id
    and e.kind = 'redemption'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'redemption_reversal'
    );

  update public.payment_charges
  set venue_credit_applied_cents = 0,
      venue_credit_clawback_cents = 0,
      empty_slot_offset_cents = 0,
      cashback_refund_cents = 0,
      free_slot_applied_cents = 0,
      free_slot_clawback_cents = 0
  where id = p_charge_id;
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
  v_limit integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points into v_pending, v_available
  from private.scape_balances(v_uid);
  v_active := private.referrer_active_count(v_uid);
  v_bonus := private.referrer_tier_bonus(v_uid);
  select redeem_min_points, tier_silver_active, tier_gold_active,
         backed_full_slot_enabled, free_slot_monthly_limit
    into v_min, v_silver, v_gold, v_enabled, v_limit
  from public.referral_program_settings where id = 1;
  select b.backed_points, b.unbacked_points into v_backed, v_unbacked
  from private.scape_funding_balances(v_uid) b;
  return pg_catalog.jsonb_build_object(
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'redeem_min_points', v_min,
    'tier', private.referrer_tier_name(v_uid),
    'tier_bonus_bps', v_bonus,
    'active_referrals', v_active,
    'silver_at', v_silver,
    'gold_at', v_gold,
    'cashback_min_bps', (select cashback_min_bps from public.referral_program_settings where id = 1),
    'cashback_max_bps', (select cashback_max_bps from public.referral_program_settings where id = 1),
    'backed_points', coalesce(v_backed, 0),
    'unbacked_points', coalesce(v_unbacked, 0),
    'backed_full_slot_enabled', coalesce(v_enabled, false),
    'free_slot_monthly_limit', coalesce(v_limit, 1),
    'free_slots_used_this_month', private.free_slots_used_this_month(v_uid)
  );
end;
$$;

create or replace function public.my_scape_wallet()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_pending integer;
  v_available integer;
  v_point integer;
  v_created timestamptz;
  v_summary jsonb;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select pending_points, available_points into v_pending, v_available
  from private.scape_balances(v_uid);
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select created_at into v_created from public.profiles where id = v_uid;
  v_summary := public.my_rewards_summary();
  return pg_catalog.jsonb_build_object(
    'referral_code', (select code from public.referral_codes where owner_user_id = v_uid),
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'point_value_cents', v_point,
    'redeem_min_points', v_summary -> 'redeem_min_points',
    'tier', v_summary -> 'tier',
    'tier_bonus_bps', v_summary -> 'tier_bonus_bps',
    'active_referrals', v_summary -> 'active_referrals',
    'silver_at', v_summary -> 'silver_at',
    'gold_at', v_summary -> 'gold_at',
    'backed_points', v_summary -> 'backed_points',
    'unbacked_points', v_summary -> 'unbacked_points',
    'backed_full_slot_enabled', v_summary -> 'backed_full_slot_enabled',
    'free_slot_monthly_limit', v_summary -> 'free_slot_monthly_limit',
    'free_slots_used_this_month', v_summary -> 'free_slots_used_this_month',
    'attributed', exists (
      select 1 from public.referral_attributions where subject_user_id = v_uid
    ),
    'can_claim', v_created >= pg_catalog.now() - interval '24 hours'
      and not exists (
        select 1 from public.referral_attributions where subject_user_id = v_uid
      ),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s))
      from (
        select e.kind, e.program, e.points, e.amount_cents, e.available_at,
               e.created_at, e.review_status, d.drawn_bps, d.doubled
        from public.scape_point_entries e
        left join public.cashback_draws d
          on d.payment_charge_id = e.source_charge_id
         and e.program = 'cashback'
        where e.user_id = v_uid
        order by e.created_at desc
        limit 50
      ) s
    ), '[]'::jsonb)
  );
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
      'block_self_payer', 'payer_referred_account_cap',
      'same_device_review_threshold',
      'backed_full_slot_enabled', 'free_slot_monthly_limit'
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
  v_row.free_slot_monthly_limit := private.admin_int(
    p_patch, 'free_slot_monthly_limit', v_row.free_slot_monthly_limit, 0, 100
  );
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
      block_self_payer = v_row.block_self_payer,
      payer_referred_account_cap = v_row.payer_referred_account_cap,
      same_device_review_threshold = v_row.same_device_review_threshold,
      backed_full_slot_enabled = v_row.backed_full_slot_enabled,
      free_slot_monthly_limit = v_row.free_slot_monthly_limit,
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

-- Saldo reservado da plataforma. Cresce quando a indicação é creditada
-- e diminui quando esses pontos pagam a casa ou são desfeitos. Os pontos
-- não vencem hoje; o estorno da reserva é o mesmo lançamento que um
-- vencimento futuro usa. A trava é não deixar o saldo negativo.

create or replace function private.point_reserve_cents()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    case direction
      when 'credit' then amount_cents
      else -amount_cents
    end
  ), 0)::integer
  from public.ledger_entries
  where account = 'platform_reserve'
    and kind = 'point_reserve';
$$;

create or replace function private.post_point_reserve(
  p_direction text,
  p_component text,
  p_cents integer,
  p_user uuid,
  p_strict boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance integer;
  v_cents integer;
begin
  v_cents := coalesce(p_cents, 0);
  if v_cents <= 0 or p_component is null then
    return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(814201);
  v_balance := private.point_reserve_cents();
  if p_direction = 'debit' then
    if p_strict and v_balance < v_cents then
      raise exception 'saldo reservado insuficiente'
        using errcode = '23514';
    end if;
    v_cents := least(v_cents, greatest(v_balance, 0));
  end if;
  if v_cents <= 0 then
    return;
  end if;
  insert into public.ledger_entries (
    user_id, account, direction, kind, amount_cents, component_key
  ) values (
    p_user, 'platform_reserve', p_direction, 'point_reserve',
    v_cents, p_component
  )
  on conflict (direction, component_key)
    where account = 'platform_reserve'
  do nothing;
end;
$$;

create or replace function private.sync_point_reserve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cents integer;
  v_point integer;
  v_parent_key text;
begin
  if new.kind = 'accrual' and new.program in ('c2c', 'c2b')
    and new.review_status is distinct from 'rejected'
  then
    v_cents := new.amount_cents;
    if v_cents is null or v_cents <= 0 then
      select point_value_cents into v_point
      from public.referral_program_settings
      where id = 1;
      v_cents := new.points * greatest(coalesce(v_point, 1), 1);
    end if;
    perform private.post_point_reserve(
      'credit', new.id::text, v_cents, new.user_id, false
    );
    return new;
  end if;

  if new.kind = 'release' and new.program in ('c2c', 'c2b') then
    v_parent_key := new.relates_to::text;
    if v_parent_key is not null and exists (
      select 1 from public.ledger_entries
      where account = 'platform_reserve'
        and direction = 'credit'
        and component_key = v_parent_key
    ) then
      return new;
    end if;
    v_cents := new.amount_cents;
    if v_cents is null or v_cents <= 0 then
      select point_value_cents into v_point
      from public.referral_program_settings
      where id = 1;
      v_cents := new.points * greatest(coalesce(v_point, 1), 1);
    end if;
    perform private.post_point_reserve(
      'credit', new.id::text, v_cents, new.user_id, false
    );
    return new;
  end if;

  if new.kind = 'reversal' and new.program in ('c2c', 'c2b') then
    v_parent_key := new.relates_to::text;
    if v_parent_key is null or not exists (
      select 1 from public.ledger_entries
      where account = 'platform_reserve'
        and direction = 'credit'
        and component_key = v_parent_key
    ) then
      return new;
    end if;
    v_cents := new.amount_cents;
    perform private.post_point_reserve(
      'debit', new.id::text, v_cents, new.user_id, false
    );
    return new;
  end if;

  if new.kind = 'redemption' and coalesce(new.backed_points, 0) > 0
    and coalesce(new.points, 0) > 0
  then
    v_cents := (
      new.backed_points::bigint * coalesce(new.amount_cents, 0) / new.points
    )::integer;
    perform private.post_point_reserve(
      'debit', new.id::text, v_cents, new.user_id, true
    );
    return new;
  end if;

  if new.kind = 'redemption_reversal' and coalesce(new.backed_points, 0) > 0
    and coalesce(new.points, 0) > 0
  then
    v_cents := (
      new.backed_points::bigint * coalesce(new.amount_cents, 0) / new.points
    )::integer;
    perform private.post_point_reserve(
      'credit', new.id::text, v_cents, new.user_id, false
    );
  end if;
  return new;
end;
$$;

drop trigger if exists sync_point_reserve on public.scape_point_entries;

create trigger sync_point_reserve
  after insert on public.scape_point_entries
  for each row
  execute function private.sync_point_reserve();

revoke all on function private.point_reserve_cents() from public, anon, authenticated;
revoke all on function private.post_point_reserve(text, text, integer, uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.sync_point_reserve() from public, anon, authenticated;

create or replace function private.ledger_reverse_charge(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
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
      when 'empty_slot_offset_undo' then 'empty_slot_refund_reversal'
      else 'house_refund'
    end,
    credit.amount_cents,
    credit.payment_charge_id,
    credit.component_key
  from public.ledger_entries as credit
  where credit.payment_charge_id = p_charge_id
    and credit.direction = 'credit'
    and credit.account is distinct from 'platform_reserve'
    and credit.kind not in (
      'venue_credit_clawback_offset',
      'venue_credit_clawback_refund',
      'empty_slot_offset_undo',
      'point_reserve'
    )
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;

  insert into public.ledger_entries (
    venue_id, group_id, user_id, account, direction, kind,
    amount_cents, payment_charge_id, component_key
  )
  select
    debit.venue_id,
    debit.group_id,
    debit.user_id,
    debit.account,
    'credit',
    'venue_credit_clawback_refund',
    debit.amount_cents,
    debit.payment_charge_id,
    debit.component_key
  from public.ledger_entries as debit
  join public.venue_credit_clawbacks c
    on c.id::text = debit.component_key
  where debit.payment_charge_id = p_charge_id
    and debit.direction = 'debit'
    and debit.kind = 'venue_credit_clawback'
    and c.neutralized_at is null
    and c.voided_at is null
  on conflict (payment_charge_id, kind, direction, component_key) do nothing;

  perform private.restore_applied_venue_credits(p_charge_id);
end;
$$;

