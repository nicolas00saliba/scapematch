-- Admin: casa (reabrir, teste, mescla, comissão oficial) e pontos manuais.
-- Não troca a taxa de indicação. admin_player fica como está.

alter table public.scape_point_entries
  add column if not exists note text;

alter table public.scape_point_entries
  drop constraint if exists scape_point_entries_kind_check;

alter table public.scape_point_entries
  add constraint scape_point_entries_kind_check
  check (kind in (
    'accrual',
    'release',
    'reversal',
    'redemption',
    'redemption_reversal',
    'admin_credit',
    'admin_debit'
  ));

create or replace function private.scape_balances(p_user_id uuid)
returns table (pending_points integer, available_points integer)
language sql
stable
security definer
set search_path = ''
as $$
  with entries as (
    select *
    from public.scape_point_entries
    where user_id = p_user_id
  )
  select
    coalesce((
      select sum(a.points)::integer
      from entries a
      where a.kind = 'accrual'
        and a.review_status is distinct from 'em_revisao'
        and a.review_status is distinct from 'rejected'
        and not exists (
          select 1 from entries r
          where r.relates_to = a.id and r.kind = 'release'
        )
        and not exists (
          select 1 from entries r
          where r.relates_to = a.id and r.kind = 'reversal'
        )
    ), 0),
    coalesce((
      select sum(r.points)::integer
      from entries r
      where r.kind = 'release'
    ), 0)
    - coalesce((
      select sum(v.points)::integer
      from entries v
      join entries a on a.id = v.relates_to
      where v.kind = 'reversal'
        and exists (
          select 1 from entries rel
          where rel.relates_to = a.id and rel.kind = 'release'
        )
    ), 0)
    - coalesce((
      select sum(s.points)::integer
      from entries s
      where s.kind = 'redemption'
        and not exists (
          select 1 from entries back
          where back.relates_to = s.id and back.kind = 'redemption_reversal'
        )
    ), 0)
    + coalesce((
      select sum(c.points)::integer
      from entries c
      where c.kind = 'admin_credit'
    ), 0)
    - coalesce((
      select sum(d.points)::integer
      from entries d
      where d.kind = 'admin_debit'
    ), 0);
$$;

revoke all on function private.scape_balances(uuid)
  from public, anon, authenticated;

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
      when 'admin_credit' then points
      when 'admin_debit' then -points
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

create or replace function public.admin_reopen_venue(p_venue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_status text;
begin
  select status into v_status
  from public.venues
  where id = p_venue_id
  for update;
  if not found then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  if v_status is distinct from 'rejected' then
    raise exception 'casa nao esta reprovada' using errcode = 'P0001';
  end if;
  update public.venues
  set status = 'pending',
      reviewed_by = null,
      reviewed_at = null
  where id = p_venue_id;
  perform private.admin_audit(
    v_actor, 'reopen_venue', 'venues', p_venue_id::text,
    pg_catalog.jsonb_build_object('status', 'rejected'),
    pg_catalog.jsonb_build_object('status', 'pending')
  );
  return pg_catalog.jsonb_build_object('venue_id', p_venue_id, 'status', 'pending');
end;
$$;

create or replace function public.admin_set_account_test(
  p_kind text,
  p_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
begin
  if p_kind not in ('venue', 'player') or p_enabled is null then
    raise exception 'alvo invalido' using errcode = '22023';
  end if;
  if p_kind = 'venue' then
    update public.venues set is_test = p_enabled where id = p_id;
    if not found then
      raise exception 'casa nao encontrada' using errcode = 'P0002';
    end if;
  else
    update public.profiles set is_test = p_enabled where id = p_id;
    if not found then
      raise exception 'jogador nao encontrado' using errcode = 'P0002';
    end if;
  end if;
  perform private.admin_audit(
    v_actor, 'set_account_test', p_kind, p_id::text,
    '{}'::jsonb,
    pg_catalog.jsonb_build_object('is_test', p_enabled)
  );
  return pg_catalog.jsonb_build_object(
    'kind', p_kind, 'id', p_id, 'is_test', p_enabled
  );
end;
$$;

create or replace function public.admin_clear_venue_commission(
  p_venue_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_before integer;
  v_official integer;
begin
  if p_confirm is distinct from 'OFICIAL' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  if not exists (select 1 from public.venues where id = p_venue_id) then
    raise exception 'casa nao encontrada' using errcode = 'P0002';
  end if;
  select commission_bps into v_before
  from public.venue_commissions where venue_id = p_venue_id;
  delete from public.venue_commissions where venue_id = p_venue_id;
  select commission_bps into v_official
  from public.platform_settings where id = 1;
  perform private.admin_audit(
    v_actor, 'clear_venue_commission', 'venue_commissions', p_venue_id::text,
    pg_catalog.jsonb_build_object('commission_bps', v_before),
    pg_catalog.jsonb_build_object('commission_bps', v_official)
  );
  return pg_catalog.jsonb_build_object(
    'venue_id', p_venue_id,
    'commission_bps', v_official
  );
end;
$$;

create or replace function public.admin_merge_venues(
  p_source_id uuid,
  p_target_id uuid,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_source text;
  v_target text;
  v_table text;
  v_moved integer := 0;
begin
  if p_confirm is distinct from 'MESCLAR' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  if p_source_id is null or p_target_id is null or p_source_id = p_target_id then
    raise exception 'casas invalidas' using errcode = '22023';
  end if;
  select status into v_source from public.venues where id = p_source_id for update;
  if not found then
    raise exception 'casa de origem nao encontrada' using errcode = 'P0002';
  end if;
  select status into v_target from public.venues where id = p_target_id for update;
  if not found then
    raise exception 'casa de destino nao encontrada' using errcode = 'P0002';
  end if;
  if v_source = 'merged' or v_target in ('merged', 'rejected') then
    raise exception 'casa nao pode ser mesclada' using errcode = 'P0001';
  end if;
  for v_table in
    select c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    join pg_catalog.pg_attribute a on a.attrelid = c.oid
    where n.nspname = 'public'
      and c.relkind = 'r'
      and a.attname = 'venue_id'
      and a.attnum > 0
      and not a.attisdropped
      and c.relname <> 'venues'
    order by c.relname
  loop
    begin
      execute format(
        'update public.%I set venue_id = $1 where venue_id = $2',
        v_table
      ) using p_target_id, p_source_id;
      get diagnostics v_moved = row_count;
    exception
      when unique_violation then
        raise exception 'mescla conflitante em %', v_table using errcode = 'P0001';
    end;
  end loop;
  update public.venues
  set status = 'merged',
      merged_into = p_target_id
  where id = p_source_id;
  perform private.admin_audit(
    v_actor, 'merge_venues', 'venues', p_source_id::text,
    pg_catalog.jsonb_build_object('status', v_source),
    pg_catalog.jsonb_build_object('status', 'merged', 'merged_into', p_target_id)
  );
  return pg_catalog.jsonb_build_object(
    'source_id', p_source_id,
    'target_id', p_target_id,
    'status', 'merged'
  );
end;
$$;

create or replace function public.admin_adjust_points(
  p_user_id uuid,
  p_points integer,
  p_direction text,
  p_reason text,
  p_confirm text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.admin_require();
  v_value integer;
  v_available integer;
  v_kind text;
  v_id uuid;
begin
  if p_confirm is distinct from 'PONTOS' then
    raise exception 'confirmacao invalida' using errcode = '22023';
  end if;
  if p_direction not in ('credit', 'debit')
    or p_points is null
    or p_points < 1
    or p_points > 100000
    or char_length(btrim(coalesce(p_reason, ''))) not between 3 and 200
  then
    raise exception 'ajuste invalido' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'jogador nao encontrado' using errcode = 'P0002';
  end if;
  select point_value_cents into v_value
  from public.referral_program_settings where id = 1;
  select available_points into v_available
  from private.scape_balances(p_user_id);
  v_available := coalesce(v_available, 0);
  if p_direction = 'debit' and p_points > v_available then
    raise exception 'saldo insuficiente' using errcode = 'P0001';
  end if;
  v_kind := case when p_direction = 'credit' then 'admin_credit' else 'admin_debit' end;
  insert into public.scape_point_entries (
    user_id, kind, points, amount_cents, note, idempotency_key, available_at
  ) values (
    p_user_id, v_kind, p_points, p_points * v_value, btrim(p_reason),
    'admin-points-' || gen_random_uuid()::text, pg_catalog.now()
  )
  returning id into v_id;
  perform private.admin_audit(
    v_actor, 'adjust_points', 'scape_point_entries', v_id::text,
    pg_catalog.jsonb_build_object('available_points', v_available),
    pg_catalog.jsonb_build_object(
      'direction', p_direction,
      'points', p_points,
      'reason', btrim(p_reason)
    )
  );
  return pg_catalog.jsonb_build_object(
    'entry_id', v_id,
    'available_points', (private.scape_balances(p_user_id)).available_points
  );
end;
$$;

create or replace function public.admin_player_ledger(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_test boolean;
  v_entries jsonb;
begin
  perform private.admin_require();
  select is_test into v_test from public.profiles where id = p_user_id;
  if not found then
    raise exception 'jogador nao encontrado' using errcode = 'P0002';
  end if;
  select coalesce(pg_catalog.jsonb_agg(to_jsonb(s) order by s.created_at desc), '[]'::jsonb)
    into v_entries
  from (
    select
      e.kind,
      e.points,
      e.amount_cents,
      coalesce(e.program, '') as program,
      coalesce(e.note, '') as note,
      coalesce(e.review_status, '') as review_status,
      e.created_at,
      coalesce(v.name, '') as venue_name,
      coalesce(r.name, '') as room_name,
      g.starts_at
    from public.scape_point_entries e
    left join public.payment_charges c
      on c.id = coalesce(e.payment_charge_id, e.source_charge_id)
    left join public.groups g on g.id = c.group_id
    left join public.rooms r on r.id = g.room_id
    left join public.venues v on v.id = coalesce(g.venue_id, c.venue_id)
    where e.user_id = p_user_id
    order by e.created_at desc
    limit 40
  ) s;
  return pg_catalog.jsonb_build_object(
    'is_test', v_test,
    'entries', v_entries
  );
end;
$$;

do $$
declare
  v_sig text;
begin
  foreach v_sig in array array[
    'public.admin_reopen_venue(uuid)',
    'public.admin_set_account_test(text, uuid, boolean)',
    'public.admin_clear_venue_commission(uuid, text)',
    'public.admin_merge_venues(uuid, uuid, text)',
    'public.admin_adjust_points(uuid, integer, text, text, text)',
    'public.admin_player_ledger(uuid)'
  ]
  loop
    execute format(
      'revoke all on function %s from public, anon, service_role',
      v_sig
    );
    execute format('grant execute on function %s to authenticated', v_sig);
  end loop;
end $$;
