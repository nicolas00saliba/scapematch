-- O perfil do jogador no Admin mostra a taxa da regra de 24/11/2026.
-- Antes, tier_bonus_bps vinha de private.referrer_tier_bonus (bônus antigo
-- de prata/ouro: 0,5% com 5 ativos e 1% com 15), enquanto a conta usa
-- private.referrer_c2c_bps (1%, 2,5% a partir de 5 e 5% a partir de 8).
-- Um jogador com 8 ativos aparecia com "comissão 0,50%" em vez de 5%.
-- Só troca essa chave. Não mexe em cálculo, saldo nem grant.
-- Não aplicado no remoto.

create or replace function public.admin_player(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := private.admin_require();
  v_profile public.profiles%rowtype;
  v_email text;
  v_pending integer := 0;
  v_available integer := 0;
  v_point integer;
begin
  select * into v_profile from public.profiles where id = p_user_id;
  if not found then
    raise exception 'jogador nao encontrado' using errcode = 'P0002';
  end if;
  select email into v_email from auth.users where id = p_user_id;
  select pending_points, available_points
    into v_pending, v_available
  from private.scape_balances(p_user_id);
  select point_value_cents into v_point
  from public.referral_program_settings where id = 1;
  return pg_catalog.jsonb_build_object(
    'id', v_profile.id,
    'display_name', v_profile.display_name,
    'email', v_email,
    'phone', v_profile.phone,
    'username', v_profile.username,
    'has_cpf', v_profile.cpf is not null,
    'created_at', v_profile.created_at,
    'suspended', v_profile.suspended_at is not null,
    'suspended_at', v_profile.suspended_at,
    'referral_code', (
      select code from public.referral_codes where owner_user_id = p_user_id
    ),
    'available_points', coalesce(v_available, 0),
    'pending_points', coalesce(v_pending, 0),
    'point_value_cents', v_point,
    'open_points_cents', coalesce(v_available, 0) * coalesce(v_point, 1),
    'tier', private.referrer_tier_name(p_user_id),
    'tier_bonus_bps', private.referrer_c2c_bps(p_user_id),
    'active_referrals', private.referrer_active_count(p_user_id),
    'referred_by', (
      select pg_catalog.jsonb_build_object(
        'referrer_kind', a.referrer_kind,
        'referrer_user_id', a.referrer_user_id,
        'referrer_venue_id', a.referrer_venue_id,
        'status', a.status,
        'code', a.code
      )
      from public.referral_attributions a
      where a.subject_user_id = p_user_id
      order by a.created_at desc
      limit 1
    ),
    'referrals_made', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(a) order by a.created_at desc)
      from (
        select subject_kind, subject_user_id, subject_venue_id, status, created_at
        from public.referral_attributions
        where referrer_user_id = p_user_id
        order by created_at desc
        limit 30
      ) a
    ), '[]'::jsonb),
    'reservations', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(r) order by r.starts_at desc)
      from (
        select
          g.id as group_id,
          r.name as room_name,
          v.name as venue_name,
          g.starts_at,
          m.attendance,
          m.payment_status
        from public.group_members m
        join public.groups g on g.id = m.group_id
        join public.rooms r on r.id = g.room_id
        join public.venues v on v.id = g.venue_id
        where m.user_id = p_user_id
        order by g.starts_at desc
        limit 30
      ) r
    ), '[]'::jsonb),
    'entries', coalesce((
      select pg_catalog.jsonb_agg(row_to_json(e) order by e.created_at desc)
      from (
        select kind, program, points, amount_cents, review_status, created_at
        from public.scape_point_entries
        where user_id = p_user_id
        order by created_at desc
        limit 40
      ) e
    ), '[]'::jsonb)
  );
end;
$function$;
