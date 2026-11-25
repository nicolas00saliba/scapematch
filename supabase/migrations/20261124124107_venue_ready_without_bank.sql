-- A casa recebe na conta PagBank do Connect. O saque para outro banco
-- é a Transferência Automática no próprio PagBank, no mesmo CNPJ ou CPF.
-- A API documentada não cadastra conta de saque nem transfere com o token
-- da casa. Pronta deixa de exigir venue_bank_accounts.

create or replace function public.venue_finance_ready(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues venue
    where venue.id = p_venue_id
      and venue.status = 'approved'
      and venue.suspended_at is null
      and venue.pagbank_account_id is not null
      and pg_catalog.btrim(venue.pagbank_account_id) <> ''
  );
$$;

comment on function public.venue_finance_ready(uuid) is
  'Aprovada, não suspensa e com pagbank_account_id. Não exige conta bancária.';

create or replace function public.list_due_venue_payouts()
returns table (
  venue_id uuid,
  period_key text,
  min_amount_cents integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    s.venue_id,
    public.venue_weekly_attempt_key(s.venue_id, pg_catalog.now()),
    s.min_amount_cents
  from public.venue_payout_schedules s
  join public.venues v on v.id = s.venue_id
  where public.venue_payouts_enabled()
    and s.enabled
    and s.frequency = 'weekly'
    and v.status = 'approved'
    and v.suspended_at is null
    and v.pagbank_account_id is not null
    and pg_catalog.btrim(v.pagbank_account_id) <> ''
    and public.venue_weekly_attempt_key(s.venue_id, pg_catalog.now()) is not null;
$$;

comment on function public.list_due_venue_payouts() is
  'Casas prontas para a agenda semanal. Não lê venue_bank_accounts.';
