-- Tentativas da NFS-e. Não aplicar no remoto.
-- attempt_count limita o retry. updated_at marca a trava processing
-- para uma emissão interrompida poder ser reaberta depois de 15 minutos.

alter table public.fiscal_invoices
  add column if not exists attempt_count integer not null default 0
    check (attempt_count >= 0);

alter table public.fiscal_invoices
  add column if not exists updated_at timestamptz not null default pg_catalog.now();

comment on column public.fiscal_invoices.attempt_count is
  'Vezes que a emissão chegou a chamar o Asaas ou a travar a linha. O retry para em 5.';

comment on column public.fiscal_invoices.updated_at is
  'Última troca de status. Uma linha processing mais velha que 15 minutos pode ser reaberta.';
