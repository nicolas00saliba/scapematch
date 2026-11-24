-- Leitura pública das regras vigentes. Não aplicado no remoto.
-- O app mostra estes números e os recalcula na prévia. O pedido já
-- criado no PagBank não muda: o valor, o split e o fixo da casa foram
-- gravados na cobrança e enviados no Order. A conta PagBank não guarda
-- taxa de indicação, cashback nem desconto.

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
    'redeem_max_bps', s.redeem_max_bps,
    'cashback_min_bps', s.cashback_min_bps,
    'cashback_max_bps', s.cashback_max_bps
  )
  from public.referral_program_settings s
  where s.id = 1;
$$;

comment on function public.reward_rules_public() is
  'Regras vigentes para o app. Sem distribuição do sorteio, sem trava de antifraude e sem flag interna. updated_at é a versão.';

revoke all on function public.reward_rules_public() from public;
grant execute on function public.reward_rules_public() to anon, authenticated, service_role;
