-- Relatórios do Admin: teste fora por padrão, recompensa sem contar duas vezes,
-- histórico de regra (inclusive SQL direto) e parcelas sem juros configuráveis.
-- A função de cobrança continua com o limite no código. Este número fica
-- guardado para ela passar a lê-lo depois.

update public.venues
set is_test = true
where name = 'Casa Teste ScapeMatch'
  and is_test = false;

-- O _ da busca é caractere, não curinga. Sem isso, "save_checkout" não acha a ação.
create or replace function private.admin_like(p_query text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '%' || replace(
    replace(btrim(coalesce(p_query, '')), '%', '\%'),
    '_',
    '\_'
  ) || '%';
$$;

create table public.rule_change_log (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  row_id text not null,
  actor_id uuid,
  operation text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  before_state jsonb,
  after_state jsonb,
  created_at timestamptz not null default pg_catalog.now()
);

create index rule_change_log_by_time
  on public.rule_change_log (created_at desc);

alter table public.rule_change_log enable row level security;

revoke all on table public.rule_change_log
  from public, anon, authenticated, service_role;

comment on table public.rule_change_log is
  'Toda mudança de regra ou config, inclusive migration e SQL direto. actor_id fica nulo quando não há sessão.';

create table public.admin_checkout_config (
  id integer primary key default 1 check (id = 1),
  max_interest_free_installments integer not null default 3
    check (max_interest_free_installments between 1 and 12),
  updated_at timestamptz not null default pg_catalog.now()
);

alter table public.admin_checkout_config enable row level security;

revoke all on table public.admin_checkout_config
  from public, anon, authenticated, service_role;

comment on table public.admin_checkout_config is
  'Máximo de parcelas sem juros que o Admin grava. A cobrança ainda não lê esta tabela.';

create or replace function private.log_rule_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case
    when tg_op = 'DELETE' then pg_catalog.to_jsonb(old)
    else pg_catalog.to_jsonb(new)
  end;
begin
  insert into public.rule_change_log (
    table_name, row_id, actor_id, operation, before_state, after_state
  ) values (
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'venue_id', ''),
    auth.uid(),
    tg_op,
    case when tg_op = 'INSERT' then null else pg_catalog.to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else pg_catalog.to_jsonb(new) end
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.log_rule_change()
  from public, anon, authenticated, service_role;

create trigger platform_settings_rule_log
  after insert or update or delete on public.platform_settings
  for each row execute function private.log_rule_change();

create trigger referral_settings_rule_log
  after insert or update or delete on public.referral_program_settings
  for each row execute function private.log_rule_change();

create trigger venue_commissions_rule_log
  after insert or update or delete on public.venue_commissions
  for each row execute function private.log_rule_change();

create trigger checkout_config_rule_log
  after insert or update or delete on public.admin_checkout_config
  for each row execute function private.log_rule_change();

insert into public.admin_checkout_config (id, max_interest_free_installments)
values (1, 3);

create or replace function private.admin_hide_test(
  p_include boolean,
  p_venue uuid,
  p_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_include, false)
    or (
      not exists (
        select 1 from public.venues v
        where v.id = p_venue and v.is_test
      )
      and not exists (
        select 1 from public.profiles p
        where p.id = p_user and p.is_test
      )
    );
$$;

revoke all on function private.admin_hide_test(boolean, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.admin_earnings_report(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_venue_id uuid default null,
  p_include_test boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_point integer := 1;
  v_gross bigint := 0;
  v_redeemed bigint := 0;
  v_subsidy bigint := 0;
  v_points bigint := 0;
  v_cashback bigint := 0;
  v_cashback_platform bigint := 0;
  v_fee bigint := 0;
  v_fee_rows integer := 0;
  v_liability jsonb;
begin
  perform private.admin_require();
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;
  select coalesce(point_value_cents, 1) into v_point
  from public.referral_program_settings
  where id = 1;

  select coalesce(sum(
    case
      when account = 'platform' and kind = 'commission' and direction = 'credit'
        then amount_cents
      when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
        then -amount_cents
      else 0
    end
  ), 0)::bigint
  into v_gross
  from public.ledger_entries
  where (p_from is null or created_at >= p_from)
    and (p_to is null or created_at < p_to)
    and (p_venue_id is null or venue_id = p_venue_id)
    and private.admin_hide_test(p_include_test, venue_id, user_id);

  select
    coalesce(sum(greatest(c.subsidy_cents, c.points_redeemed * v_point)), 0)::bigint,
    coalesce(sum(c.subsidy_cents), 0)::bigint,
    coalesce(sum(c.points_redeemed * v_point), 0)::bigint
  into v_redeemed, v_subsidy, v_points
  from public.payment_charges c
  where c.status = 'paid'
    and (p_from is null or coalesce(c.paid_at, c.created_at) >= p_from)
    and (p_to is null or coalesce(c.paid_at, c.created_at) < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id)
    and private.admin_hide_test(p_include_test, c.venue_id, c.user_id);

  select coalesce(sum(e.amount_cents), 0)::bigint
  into v_cashback
  from public.scape_point_entries e
  left join public.payment_charges c on c.id = e.source_charge_id
  where e.kind = 'accrual'
    and e.program = 'cashback'
    and e.review_status is distinct from 'rejected'
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and (p_from is null or e.created_at >= p_from)
    and (p_to is null or e.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id)
    and private.admin_hide_test(p_include_test, c.venue_id, e.user_id);

  select coalesce(sum(d.platform_cents), 0)::bigint
  into v_cashback_platform
  from public.cashback_draws d
  left join public.payment_charges c on c.id = d.payment_charge_id
  where (p_from is null or d.created_at >= p_from)
    and (p_to is null or d.created_at < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id)
    and private.admin_hide_test(p_include_test, c.venue_id, c.user_id);

  select
    count(*) filter (where provider_fee_cents is not null)::integer,
    coalesce(sum(provider_fee_cents) filter (where provider_fee_cents is not null), 0)::bigint
  into v_fee_rows, v_fee
  from public.payment_charges c
  where (p_from is null or coalesce(c.paid_at, c.created_at) >= p_from)
    and (p_to is null or coalesce(c.paid_at, c.created_at) < p_to)
    and (p_venue_id is null or c.venue_id = p_venue_id)
    and private.admin_hide_test(p_include_test, c.venue_id, c.user_id);

  v_liability := public.admin_scape_liability();

  return pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'venue_id', p_venue_id,
    'include_test', coalesce(p_include_test, false),
    'gross_commission_cents', v_gross,
    'rewards_redeemed_cents', v_redeemed,
    'rewards_subsidy_cents', v_subsidy,
    'rewards_points_cents', v_points,
    'cashback_issued_cents', v_cashback,
    'cashback_platform_cents', v_cashback_platform,
    'open_points', coalesce((v_liability ->> 'available_points')::integer, 0),
    'open_points_cents', coalesce((v_liability ->> 'available_points')::integer, 0)
      * coalesce((v_liability ->> 'point_value_cents')::integer, 1),
    'pending_points', coalesce((v_liability ->> 'pending_points')::integer, 0),
    'provider_fee_cents', case when v_fee_rows = 0 then null else v_fee end,
    'pagbank_fee_rows', v_fee_rows,
    'by_venue', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.name)
      from (
        select
          v.id as venue_id,
          v.name,
          coalesce(c.gross_cents, 0) as gross_commission_cents,
          coalesce(r.redeemed_cents, 0) as rewards_redeemed_cents,
          coalesce(k.cashback_cents, 0) as cashback_issued_cents,
          coalesce(d.debt_cents, 0) as open_debt_cents
        from public.venues v
        left join (
          select venue_id, sum(
            case
              when account = 'platform' and kind = 'commission' and direction = 'credit'
                then amount_cents
              when account = 'platform' and kind = 'commission_refund' and direction = 'debit'
                then -amount_cents
              else 0
            end
          )::bigint as gross_cents
          from public.ledger_entries
          where (p_from is null or created_at >= p_from)
            and (p_to is null or created_at < p_to)
            and private.admin_hide_test(p_include_test, venue_id, user_id)
          group by venue_id
        ) c on c.venue_id = v.id
        left join (
          select venue_id, sum(greatest(subsidy_cents, points_redeemed * v_point))::bigint
            as redeemed_cents
          from public.payment_charges
          where status = 'paid'
            and (p_from is null or coalesce(paid_at, created_at) >= p_from)
            and (p_to is null or coalesce(paid_at, created_at) < p_to)
            and private.admin_hide_test(p_include_test, venue_id, user_id)
          group by venue_id
        ) r on r.venue_id = v.id
        left join (
          select ch.venue_id, sum(e.amount_cents)::bigint as cashback_cents
          from public.scape_point_entries e
          join public.payment_charges ch on ch.id = e.source_charge_id
          where e.kind = 'accrual'
            and e.program = 'cashback'
            and e.review_status is distinct from 'rejected'
            and not exists (
              select 1 from public.scape_point_entries rev
              where rev.relates_to = e.id and rev.kind = 'reversal'
            )
            and (p_from is null or e.created_at >= p_from)
            and (p_to is null or e.created_at < p_to)
            and private.admin_hide_test(p_include_test, ch.venue_id, e.user_id)
          group by ch.venue_id
        ) k on k.venue_id = v.id
        left join (
          select venue_id, sum(open_cents)::bigint as debt_cents
          from (
            select venue_id, (amount_cents - applied_cents) as open_cents
            from public.venue_credit_clawbacks
            where voided_at is null
              and neutralized_at is null
              and applied_cents < amount_cents
            union all
            select venue_id, (amount_cents - applied_cents)
            from public.venue_cashback_debits
            where voided_at is null
              and applied_cents < amount_cents
          ) open_debt
          group by venue_id
        ) d on d.venue_id = v.id
        where (p_venue_id is null or v.id = p_venue_id)
          and private.admin_hide_test(p_include_test, v.id, null)
          and (
            c.venue_id is not null
            or r.venue_id is not null
            or k.venue_id is not null
            or d.venue_id is not null
          )
      ) s
    ), '[]'::jsonb),
    'open_components', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(s) order by s.venue_name, s.kind)
      from (
        select
          v.id as venue_id,
          v.name as venue_name,
          'clawback'::text as kind,
          'debt'::text as direction,
          (c.amount_cents - c.applied_cents) as open_cents,
          true as all_or_nothing
        from public.venue_credit_clawbacks c
        join public.venues v on v.id = c.venue_id
        where c.voided_at is null
          and c.neutralized_at is null
          and c.applied_cents < c.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
          and private.admin_hide_test(p_include_test, v.id, null)
        union all
        select
          v.id,
          v.name,
          'cashback_debit',
          'debt',
          d.amount_cents - d.applied_cents,
          true
        from public.venue_cashback_debits d
        join public.venues v on v.id = d.venue_id
        where d.voided_at is null
          and d.applied_cents < d.amount_cents
          and (p_venue_id is null or v.id = p_venue_id)
          and private.admin_hide_test(p_include_test, v.id, null)
        union all
        select
          v.id,
          v.name,
          'venue_credit',
          'credit',
          e.amount_cents - e.applied_cents,
          true
        from public.venue_referral_entries e
        join public.venues v on v.id = e.venue_id
        where e.kind = 'accrual'
          and e.settlement = 'released'
          and e.review_status is distinct from 'em_revisao'
          and e.review_status is distinct from 'rejected'
          and e.applied_cents < e.amount_cents
          and not exists (
            select 1 from public.venue_referral_entries r
            where r.relates_to = e.id and r.kind = 'reversal'
          )
          and (p_venue_id is null or v.id = p_venue_id)
          and private.admin_hide_test(p_include_test, v.id, null)
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_earnings(
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_venue_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.admin_earnings_report(p_from, p_to, p_venue_id, false);
$$;

create or replace function public.admin_list_players(p_query text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
begin
  perform private.admin_require();
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at desc)
    from (
      select
        p.id,
        p.display_name,
        u.email,
        p.suspended_at is not null as suspended,
        p.is_test,
        p.created_at
      from public.profiles p
      join auth.users u on u.id = p.id
      where p.is_test = false
        and (
          v_blank
          or p.display_name ilike v_like
          or coalesce(u.email, '') ilike v_like
          or coalesce(p.username, '') ilike v_like
        )
      order by p.created_at desc
      limit 40
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_search_players(
  p_query text default null,
  p_include_test boolean default false,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text := private.admin_like(p_query);
  v_blank boolean := btrim(coalesce(p_query, '')) = '';
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  select count(*)::integer into v_total
  from public.profiles p
  join auth.users u on u.id = p.id
  where (p_include_test or p.is_test = false)
    and (
      v_blank
      or p.display_name ilike v_like
      or coalesce(u.email, '') ilike v_like
      or coalesce(p.username, '') ilike v_like
    );

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      p.id,
      p.display_name,
      u.email,
      p.suspended_at is not null as suspended,
      p.is_test,
      p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    where (p_include_test or p.is_test = false)
      and (
        v_blank
        or p.display_name ilike v_like
        or coalesce(u.email, '') ilike v_like
        or coalesce(p.username, '') ilike v_like
      )
    order by p.created_at desc
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;

create or replace function public.admin_search_audit(
  p_action text default null,
  p_actor text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_action text := private.admin_like(p_action);
  v_actor text := private.admin_like(p_actor);
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  if p_from is not null and p_to is not null and p_to <= p_from then
    raise exception 'periodo invalido' using errcode = '22023';
  end if;

  select count(*)::integer into v_total
  from public.admin_audit_log a
  left join public.profiles p on p.id = a.actor_id
  where (p_action is null or btrim(p_action) = '' or a.action ilike v_action)
    and (
      p_actor is null
      or btrim(p_actor) = ''
      or a.actor_id::text = btrim(p_actor)
      or coalesce(p.display_name, '') ilike v_actor
    )
    and (p_from is null or a.created_at >= p_from)
    and (p_to is null or a.created_at < p_to);

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      a.id,
      a.actor_id,
      coalesce(p.display_name, '') as actor_name,
      a.action,
      a.target_table,
      a.target_id,
      a.before_state,
      a.after_state,
      a.created_at
    from public.admin_audit_log a
    left join public.profiles p on p.id = a.actor_id
    where (p_action is null or btrim(p_action) = '' or a.action ilike v_action)
      and (
        p_actor is null
        or btrim(p_actor) = ''
        or a.actor_id::text = btrim(p_actor)
        or coalesce(p.display_name, '') ilike v_actor
      )
      and (p_from is null or a.created_at >= p_from)
      and (p_to is null or a.created_at < p_to)
    order by a.created_at desc
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;

create or replace function public.admin_commission_history(
  p_venue_id uuid default null,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  select count(*)::integer into v_total
  from public.commission_changes c
  where p_venue_id is null or c.venue_id is not distinct from p_venue_id;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      c.id,
      c.venue_id,
      case when c.venue_id is null then 'plataforma' else coalesce(v.name, '') end
        as venue_name,
      c.before_bps,
      c.after_bps,
      c.actor_id,
      coalesce(p.display_name, '') as actor_name,
      c.created_at
    from public.commission_changes c
    left join public.venues v on v.id = c.venue_id
    left join public.profiles p on p.id = c.actor_id
    where p_venue_id is null or c.venue_id is not distinct from p_venue_id
    order by c.created_at desc
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;

create or replace function public.admin_rule_history(
  p_table text default null,
  p_limit integer default 40,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer := private.admin_page_limit(p_limit);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
begin
  perform private.admin_require();
  select count(*)::integer into v_total
  from public.rule_change_log r
  where p_table is null or btrim(p_table) = '' or r.table_name = p_table;

  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      r.id,
      r.table_name,
      r.row_id,
      r.actor_id,
      coalesce(p.display_name, '') as actor_name,
      r.operation,
      r.before_state,
      r.after_state,
      r.created_at
    from public.rule_change_log r
    left join public.profiles p on p.id = r.actor_id
    where p_table is null or btrim(p_table) = '' or r.table_name = p_table
    order by r.created_at desc
    limit v_limit
    offset v_offset
  ) s;

  return pg_catalog.jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$$;

create or replace function public.admin_checkout_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_max integer;
  v_pix integer;
  v_card integer;
  v_bps integer;
begin
  perform private.admin_require();
  select max_interest_free_installments into v_max
  from public.admin_checkout_config
  where id = 1;
  select pix_receipt_fee_cents, card_receipt_fee_cents, card_receipt_fee_bps
    into v_pix, v_card, v_bps
  from public.platform_settings
  where id = 1;
  return pg_catalog.jsonb_build_object(
    'max_interest_free_installments', v_max,
    'pix_receipt_fee_cents', v_pix,
    'card_receipt_fee_cents', v_card,
    'card_receipt_fee_bps', v_bps,
    'charge_function_reads_config', false
  );
end;
$$;

create or replace function public.admin_save_checkout(
  p_confirm text,
  p_max_interest_free integer,
  p_pix_receipt_fee_cents integer,
  p_card_receipt_fee_cents integer,
  p_card_receipt_fee_bps integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.admin_require();
  v_before jsonb;
  v_after jsonb;
begin
  if p_confirm is distinct from 'CONFIG' then
    raise exception 'confirmacao' using errcode = '22023';
  end if;
  if p_max_interest_free is null
    or p_max_interest_free < 1
    or p_max_interest_free > 12
  then
    raise exception 'parcelas' using errcode = '22023';
  end if;
  if p_pix_receipt_fee_cents is null
    or p_pix_receipt_fee_cents < 0
    or p_card_receipt_fee_cents is null
    or p_card_receipt_fee_cents < 0
    or p_card_receipt_fee_bps is null
    or p_card_receipt_fee_bps < 0
    or p_card_receipt_fee_bps > 10000
  then
    raise exception 'taxa' using errcode = '22023';
  end if;

  select pg_catalog.jsonb_build_object(
    'max_interest_free_installments', c.max_interest_free_installments,
    'pix_receipt_fee_cents', s.pix_receipt_fee_cents,
    'card_receipt_fee_cents', s.card_receipt_fee_cents,
    'card_receipt_fee_bps', s.card_receipt_fee_bps
  ) into v_before
  from public.admin_checkout_config c
  cross join public.platform_settings s
  where c.id = 1 and s.id = 1;

  update public.admin_checkout_config
  set max_interest_free_installments = p_max_interest_free,
      updated_at = pg_catalog.now()
  where id = 1;

  update public.platform_settings
  set pix_receipt_fee_cents = p_pix_receipt_fee_cents,
      card_receipt_fee_cents = p_card_receipt_fee_cents,
      card_receipt_fee_bps = p_card_receipt_fee_bps,
      updated_by = v_uid,
      updated_at = pg_catalog.now()
  where id = 1;

  v_after := pg_catalog.jsonb_build_object(
    'max_interest_free_installments', p_max_interest_free,
    'pix_receipt_fee_cents', p_pix_receipt_fee_cents,
    'card_receipt_fee_cents', p_card_receipt_fee_cents,
    'card_receipt_fee_bps', p_card_receipt_fee_bps
  );
  perform private.admin_audit(
    v_uid, 'save_checkout', 'admin_checkout_config', '1', v_before, v_after
  );
  return v_after;
end;
$$;

do $$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public.admin_earnings_report(timestamptz, timestamptz, uuid, boolean)',
    'public.admin_search_players(text, boolean, integer, integer)',
    'public.admin_search_audit(text, text, timestamptz, timestamptz, integer, integer)',
    'public.admin_commission_history(uuid, integer, integer)',
    'public.admin_rule_history(text, integer, integer)',
    'public.admin_checkout_settings()',
    'public.admin_save_checkout(text, integer, integer, integer, integer)'
  ]
  loop
    execute format(
      'revoke all on function %s from public, anon, service_role',
      v_sig
    );
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;
