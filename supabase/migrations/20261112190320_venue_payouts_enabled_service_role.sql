-- schedule-venue-withdrawals chama public.venue_payouts_enabled()
-- com service_role. A migration de saques revogou esse execute
-- e deixou só authenticated. anon e authenticated não ganham grant aqui.

grant execute on function public.venue_payouts_enabled() to service_role;
