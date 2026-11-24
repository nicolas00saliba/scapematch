-- Total autorizado no cartão (principal + juros do comprador) e teto da
-- cotação de parcelas. Não altera migrations já aplicadas.

alter table public.payment_charges
  add column if not exists charged_amount_cents integer,
  add column if not exists buyer_interest_cents integer not null default 0;

alter table public.payment_charges
  drop constraint if exists payment_charges_charged_amount_check;

alter table public.payment_charges
  add constraint payment_charges_charged_amount_check
  check (
    charged_amount_cents is null
    or (
      charged_amount_cents > 0
      and charged_amount_cents = amount_cents + buyer_interest_cents
    )
  );

alter table public.payment_charges
  drop constraint if exists payment_charges_buyer_interest_check;

alter table public.payment_charges
  add constraint payment_charges_buyer_interest_check
  check (buyer_interest_cents >= 0);

comment on column public.payment_charges.charged_amount_cents is
  'Total autorizado na PagBank, principal mais juros do comprador. Captura e cancelamento usam este valor.';

comment on column public.payment_charges.buyer_interest_cents is
  'Juros do comprador de 4x a 12x. Zero até 3x.';

create table public.installment_quote_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index installment_quote_attempts_user_time
  on public.installment_quote_attempts (user_id, created_at);

alter table public.installment_quote_attempts enable row level security;

revoke all on table public.installment_quote_attempts
  from public, anon, authenticated, service_role;

create or replace function private.claim_installment_quote(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempts bigint;
begin
  if p_user_id is null then
    return false;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('installment_quote'),
    pg_catalog.hashtext(p_user_id::text)
  );
  delete from public.installment_quote_attempts
  where user_id = p_user_id
    and created_at <= pg_catalog.now() - interval '10 minutes';
  insert into public.installment_quote_attempts (user_id)
  values (p_user_id);
  select count(*) into v_attempts
  from public.installment_quote_attempts
  where user_id = p_user_id;
  return v_attempts <= 20;
end;
$$;

revoke all on function private.claim_installment_quote(uuid)
  from public, anon, authenticated;

grant execute on function private.claim_installment_quote(uuid)
  to service_role;

create or replace function public.claim_installment_quote(p_user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.claim_installment_quote(p_user_id);
$$;

revoke all on function public.claim_installment_quote(uuid)
  from public, anon, authenticated;

grant execute on function public.claim_installment_quote(uuid)
  to service_role;
