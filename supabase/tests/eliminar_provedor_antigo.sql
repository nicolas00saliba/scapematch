-- Depois da migration, nenhuma função viva lê objeto removido.
-- admin_merge_venues mantém as recusas e a lista fechada, sem as duas tabelas.

\set ON_ERROR_STOP on

do $$
declare
  v_src text;
  v_table text;
  v_hit text;
  v_name text;
begin
  if to_regclass('public.venue_asaas_keys') is not null
    or to_regclass('public.asaas_customers') is not null
  then
    raise exception 'tabela antiga ainda existe';
  end if;

  select p.prosrc into v_src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'admin_merge_venues';
  if v_src is null then
    raise exception 'admin_merge_venues ausente';
  end if;
  if v_src like '%venue_asaas_keys%' or v_src like '%asaas_customers%' then
    raise exception 'mescla ainda lê tabela removida';
  end if;
  if v_src not like '%casa com equipe%'
    or v_src not like '%casa com acesso%'
    or v_src not like '%casa com saldo%'
    or v_src not like '%casa com cobranca%'
    or v_src not like '%casa com repasse%'
  then
    raise exception 'mescla perdeu uma recusa';
  end if;
  foreach v_table in array array[
    'absences',
    'commission_changes',
    'groups',
    'news_items',
    'passport_gifts',
    'passport_plays',
    'passport_stamps',
    'promotions',
    'review_replies',
    'room_rating_rollups',
    'room_reviews',
    'room_time_audit',
    'room_time_entries',
    'rooms',
    'session_checkins',
    'terms_acceptances',
    'venue_commissions',
    'venue_time_ranking'
  ]
  loop
    if position(v_table in v_src) = 0 then
      raise exception 'lista fechada sem %', v_table;
    end if;
  end loop;

  select string_agg(n.nspname || '.' || p.proname, ', ' order by 1)
    into v_hit
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosrc ~ 'venue_asaas_keys|asaas_customers|asaas_wallet_id|asaas_customer_id|asaas_fee_cents|asaas_transfer_id|asaas_subaccount_key|store_venue_asaas_key|read_venue_asaas_key';
  if v_hit is not null then
    raise exception 'função ainda lê objeto removido: %', v_hit;
  end if;

  for v_name in
    select n.nspname || '.' || p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosrc ilike '%asaas%'
  loop
    if v_name is distinct from 'private.apply_share_adjustments' then
      raise exception 'função inesperada com asaas: %', v_name;
    end if;
  end loop;
end $$;
