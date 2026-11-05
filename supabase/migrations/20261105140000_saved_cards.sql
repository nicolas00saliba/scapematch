-- Token do cartão fica só no servidor. anon e authenticated não leem a tabela.
-- O app vê final e bandeira por my_saved_cards(). A cobrança usa a service role
-- e filtra user_id + customer Asaas do jogador autenticado.

create table public.saved_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  asaas_customer_id text not null,
  credit_card_token text not null,
  last4 text not null,
  brand text not null default '',
  created_at timestamptz not null default now(),
  check (char_length(asaas_customer_id) between 1 and 80),
  check (char_length(credit_card_token) between 8 and 200),
  check (credit_card_token !~ '^[0-9]{13,19}$'),
  check (last4 ~ '^[0-9]{4}$'),
  check (char_length(brand) <= 32)
);

create unique index saved_cards_user_token
  on public.saved_cards (user_id, credit_card_token);

create index saved_cards_by_user
  on public.saved_cards (user_id);

alter table public.saved_cards enable row level security;

revoke all on table public.saved_cards from public, anon, authenticated;
grant select, insert, update, delete on table public.saved_cards to service_role;

create or replace function public.saved_cards_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = new.user_id
      and p.asaas_customer_id = new.asaas_customer_id
  ) then
    raise exception 'customer do cartão não é o do jogador';
  end if;
  return new;
end;
$$;

drop trigger if exists saved_cards_guard on public.saved_cards;
create trigger saved_cards_guard
  before insert or update on public.saved_cards
  for each row execute function public.saved_cards_guard();

revoke all on function public.saved_cards_guard() from public, anon, authenticated;

create or replace function public.my_saved_cards()
returns table (
  id uuid,
  last4 text,
  brand text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.last4, c.brand, c.created_at
  from public.saved_cards c
  where c.user_id = (select auth.uid())
  order by c.created_at desc;
$$;

revoke all on function public.my_saved_cards() from public, anon;
grant execute on function public.my_saved_cards() to authenticated;
