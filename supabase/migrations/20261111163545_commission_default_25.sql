-- Comissão padrão das casas: 10% (1000 bps) passa a 25% (2500 bps).
--
-- O fallback de commission_bps_for_venue é a linha de platform_settings,
-- não um 1000 escrito na função. Mudar essa linha muda a taxa das casas
-- sem override. venue_commissions não entra: toda linha tem updated_by,
-- então a taxa foi definida pelo Admin, mesmo quando o número é 1000.
-- Cobranças já feitas guardam commission_bps na própria linha e ficam.

alter table public.platform_settings
  alter column commission_bps set default 2500;

update public.platform_settings s
set commission_bps = 2500
where s.id = 1
  and s.commission_bps = 1000
  and s.updated_by is null
  and s.updated_at is null
  and not exists (
    select 1
    from public.commission_changes c
    where c.venue_id is null
  );
