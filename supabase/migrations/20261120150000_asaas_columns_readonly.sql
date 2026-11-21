-- Colunas do provedor anterior ficam no banco. Cobrança com
-- provider = 'asaas' continua só leitura. Este arquivo não dá DROP,
-- não apaga linha e não desliga cron. O DROP fica para um passo separado.

comment on column public.venues.asaas_wallet_id is
  'Descontinuada em 2026-11-20. Não usar em cobrança nova. O DROP fica para um passo separado.';

comment on column public.profiles.asaas_customer_id is
  'Descontinuada em 2026-11-20. Cliente histórico. O DROP fica para um passo separado.';

comment on column public.payment_charges.asaas_fee_cents is
  'Taxa histórica. Não preencher em cobrança nova. O DROP fica para um passo separado.';

comment on column public.venue_withdrawals.asaas_transfer_id is
  'Id histórico de transferência. Saque novo não grava aqui. O DROP fica para um passo separado.';

alter table public.payment_charges
  alter column provider set default 'woovi';

comment on column public.payment_charges.provider is
  'woovi ou mercadopago nas cobranças novas. asaas é registro histórico, só leitura.';
