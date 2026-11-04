-- Cobranças do Asaas. O app não insere aqui. A Edge Function grava com a
-- service role. Pix nasce pendente; cartão nasce authorized (authorizeOnly).

create table public.payment_charges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  user_id uuid not null references auth.users (id),
  venue_id uuid not null references public.venues (id),
  amount_cents integer not null check (amount_cents > 0),
  billing_type text not null check (billing_type in ('PIX', 'CREDIT_CARD')),
  status text not null default 'pending' check (
    status in (
      'pending',
      'authorized',
      'paid',
      'refunded',
      'cancelled',
      'failed'
    )
  ),
  provider text not null default 'asaas',
  provider_ref text,
  qr_code text,
  qr_code_base64 text,
  idempotency_key text not null unique,
  wallet_id text,
  commission_bps integer not null check (commission_bps between 0 and 10000),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  refunded_at timestamptz,
  unique (group_id, user_id)
);

create index payment_charges_by_provider_ref
  on public.payment_charges (provider_ref);

create unique index ledger_one_credit_per_charge_kind
  on public.ledger_entries (payment_charge_id, kind)
  where payment_charge_id is not null and direction = 'credit';

alter table public.ledger_entries
  add constraint ledger_entries_payment_charge_id_fkey
  foreign key (payment_charge_id) references public.payment_charges (id);

alter table public.payment_charges enable row level security;

create policy payment_charges_select on public.payment_charges
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.owns_venue(venue_id)
    or public.is_admin()
  );

revoke insert, update, delete on public.payment_charges from anon, authenticated;
