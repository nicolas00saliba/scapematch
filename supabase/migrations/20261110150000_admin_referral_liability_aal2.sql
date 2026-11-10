-- As três funções nasceram só com private.is_admin(). O console exige
-- admin e aal2, como as outras admin_* de 20261109160000. Quem chama daqui
-- é admin_earnings e admin_decide_referral_account: as duas já passaram
-- por private.admin_require() e o JWT da sessão continua o mesmo.
-- Nenhuma Edge Function nem job do pg_cron executa estas três. service_role
-- perde o EXECUTE.

create or replace function public.admin_scape_liability()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_point integer;
  v_unused integer;
  v_pending integer;
  v_available integer;
  v_venue integer;
begin
  perform private.admin_require();
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  select coalesce(sum(
    case kind
      when 'accrual' then points
      when 'reversal' then -points
      when 'redemption' then -points
      when 'redemption_reversal' then points
      else 0
    end
  ), 0)::integer
  into v_unused
  from public.scape_point_entries;
  select coalesce(sum(pending_points), 0)::integer,
         coalesce(sum(available_points), 0)::integer
    into v_pending, v_available
  from (
    select (private.scape_balances(user_id)).*
    from (
      select distinct user_id from public.scape_point_entries
    ) owners
  ) balances;
  select coalesce(sum(
    case kind when 'accrual' then amount_cents else -amount_cents end
  ), 0)::integer
  into v_venue
  from public.venue_referral_entries;
  return pg_catalog.jsonb_build_object(
    'unused_points', v_unused,
    'unused_cents', v_unused * v_point,
    'pending_points', v_pending,
    'available_points', v_available,
    'point_value_cents', v_point,
    'venue_credit_pending_cents', v_venue
  );
end;
$$;

create or replace function public.admin_referral_reviews()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.admin_require();
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at)
    from (
      select
        e.id,
        'points'::text as entry_kind,
        e.program,
        e.points,
        e.amount_cents,
        e.created_at
      from public.scape_point_entries e
      where e.kind = 'accrual' and e.review_status = 'em_revisao'
      union all
      select
        e.id,
        'venue'::text,
        e.program,
        null::integer,
        e.amount_cents,
        e.created_at
      from public.venue_referral_entries e
      where e.kind = 'accrual' and e.review_status = 'em_revisao'
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_decide_referral_review(
  p_entry_id uuid,
  p_entry_kind text,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_points integer;
  v_cents integer;
  v_user uuid;
  v_program text;
  v_charge uuid;
  v_available timestamptz;
  v_venue uuid;
begin
  perform private.admin_require();
  if p_decision not in ('approve', 'reject') or p_entry_kind not in ('points', 'venue') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  if p_entry_kind = 'points' then
    select user_id, points, amount_cents, program, source_charge_id, available_at
      into v_user, v_points, v_cents, v_program, v_charge, v_available
    from public.scape_point_entries
    where id = p_entry_id
      and kind = 'accrual'
      and review_status = 'em_revisao';
    if not found then
      raise exception 'revisao nao encontrada' using errcode = 'P0002';
    end if;
    if p_decision = 'reject' then
      update public.scape_point_entries
      set review_status = 'rejected'
      where id = p_entry_id;
      insert into public.scape_point_entries (
        user_id, kind, points, amount_cents, program,
        source_charge_id, payment_charge_id, relates_to, idempotency_key
      ) values (
        v_user, 'reversal', v_points, v_cents, v_program,
        v_charge, v_charge, p_entry_id, 'reversal:' || p_entry_id::text
      )
      on conflict (idempotency_key) do nothing;
      return;
    end if;
    update public.scape_point_entries
    set review_status = 'approved'
    where id = p_entry_id;
    if v_available <= pg_catalog.now() then
      insert into public.scape_point_entries (
        user_id, kind, points, amount_cents, program,
        source_charge_id, payment_charge_id, relates_to, idempotency_key
      ) values (
        v_user, 'release', v_points, v_cents, v_program,
        v_charge, v_charge, p_entry_id, 'release:' || p_entry_id::text
      )
      on conflict (idempotency_key) do nothing;
    end if;
    return;
  end if;
  select venue_id, amount_cents, program, source_charge_id
    into v_venue, v_cents, v_program, v_charge
  from public.venue_referral_entries
  where id = p_entry_id
    and kind = 'accrual'
    and review_status = 'em_revisao';
  if not found then
    raise exception 'revisao nao encontrada' using errcode = 'P0002';
  end if;
  if p_decision = 'reject' then
    update public.venue_referral_entries
    set review_status = 'rejected'
    where id = p_entry_id;
    insert into public.venue_referral_entries (
      venue_id, kind, amount_cents, program,
      source_charge_id, payment_charge_id, relates_to, idempotency_key
    ) values (
      v_venue, 'reversal', v_cents, v_program,
      v_charge, v_charge, p_entry_id, 'reversal:' || p_entry_id::text
    )
    on conflict (idempotency_key) do nothing;
    return;
  end if;
  update public.venue_referral_entries
  set review_status = 'approved'
  where id = p_entry_id;
end;
$$;

revoke all on function public.admin_scape_liability()
  from public, anon, service_role;
revoke all on function public.admin_referral_reviews()
  from public, anon, service_role;
revoke all on function public.admin_decide_referral_review(uuid, text, text)
  from public, anon, service_role;

grant execute on function public.admin_scape_liability() to authenticated;
grant execute on function public.admin_referral_reviews() to authenticated;
grant execute on function public.admin_decide_referral_review(uuid, text, text)
  to authenticated;
