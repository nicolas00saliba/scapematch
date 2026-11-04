-- NFS-e e aceite dos termos. O app não escreve em fiscal_invoices.
-- A Edge Function grava com a service role. Nada aqui chama o Asaas.

-- Chave da subconta. O Asaas só devolve a apiKey na criação.
-- O app não lê esta tabela. A função usa a service role, que ignora o RLS.
create table public.venue_asaas_keys (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  api_key text not null,
  created_at timestamptz not null default now()
);

alter table public.venue_asaas_keys enable row level security;
revoke all on table public.venue_asaas_keys from public, anon, authenticated;

-- Clientes Asaas criados pela função (jogador na subconta, casa na conta raiz).
create table public.asaas_customers (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('venue_player', 'platform_house')),
  venue_id uuid not null references public.venues (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,
  asaas_customer_id text not null,
  created_at timestamptz not null default now(),
  check (
    (scope = 'venue_player' and user_id is not null)
    or (scope = 'platform_house' and user_id is null)
  )
);

create unique index asaas_customers_venue_player
  on public.asaas_customers (venue_id, user_id)
  where scope = 'venue_player';

create unique index asaas_customers_platform_house
  on public.asaas_customers (venue_id)
  where scope = 'platform_house';

alter table public.asaas_customers enable row level security;
revoke all on table public.asaas_customers from public, anon, authenticated;

-- Dados fiscais da casa. O dono lê. Quem grava é a função configure-venue-fiscal.
create table public.venue_fiscal (
  venue_id uuid primary key references public.venues (id) on delete cascade,
  municipal_inscription text not null default '',
  service_code text not null default '',
  service_name text not null default '',
  iss_rate numeric not null default 0 check (iss_rate >= 0 and iss_rate <= 100),
  simples_nacional boolean not null default false,
  mei boolean not null default false,
  cnae text not null default '',
  emission text not null default 'pendente' check (
    emission in ('pendente', 'habilitada', 'sem_emissao')
  ),
  skip_reason text check (
    skip_reason is null or skip_reason in ('cpf', 'dados_fiscais')
  ),
  updated_at timestamptz not null default now()
);

alter table public.venue_fiscal enable row level security;

create policy venue_fiscal_select on public.venue_fiscal
  for select to authenticated
  using (public.owns_venue(venue_id) or public.is_admin());

revoke all on table public.venue_fiscal from public, anon, authenticated;
grant select on table public.venue_fiscal to authenticated;

-- Notas. Duas por cobrança paga: serviço (casa) e comissão (plataforma).
create table public.fiscal_invoices (
  id uuid primary key default gen_random_uuid(),
  payment_charge_id uuid not null references public.payment_charges (id),
  group_id uuid not null references public.groups (id),
  venue_id uuid not null references public.venues (id),
  player_user_id uuid references auth.users (id),
  issuer text not null check (issuer in ('venue', 'platform')),
  kind text not null check (kind in ('service', 'commission')),
  status text not null check (
    status in (
      'scheduled',
      'processing',
      'authorized',
      'error',
      'canceled',
      'sem_emissao',
      'simulated'
    )
  ),
  skip_reason text check (
    skip_reason is null or skip_reason in ('cpf', 'dados_fiscais')
  ),
  number text,
  pdf_url text,
  xml_url text,
  provider text not null default 'asaas',
  provider_invoice_id text,
  value_cents integer not null check (value_cents >= 0),
  iss_rate numeric,
  service_code text,
  description text not null default '',
  effective_date date,
  error_message text,
  created_at timestamptz not null default now(),
  issued_at timestamptz,
  check (
    (kind = 'service' and issuer = 'venue')
    or (kind = 'commission' and issuer = 'platform')
  ),
  check (status <> 'sem_emissao' or kind = 'service'),
  unique (payment_charge_id, kind)
);

create index fiscal_invoices_by_venue
  on public.fiscal_invoices (venue_id, created_at desc);

create index fiscal_invoices_by_player
  on public.fiscal_invoices (player_user_id)
  where kind = 'service';

create index fiscal_invoices_by_group
  on public.fiscal_invoices (group_id);

alter table public.fiscal_invoices enable row level security;

-- Dono da casa vê as da casa. Jogador vê só a nota de serviço dele.
-- Admin vê tudo. Não há política de escrita.
create policy fiscal_invoices_select on public.fiscal_invoices
  for select to authenticated
  using (
    public.is_admin()
    or public.owns_venue(venue_id)
    or (
      kind = 'service'
      and player_user_id = (select auth.uid())
    )
  );

revoke all on table public.fiscal_invoices from public, anon, authenticated;
grant select on table public.fiscal_invoices to authenticated;

-- Textos publicados. A versão do aceite aponta para esta linha.
create table public.legal_documents (
  code text not null check (
    code in ('player_terms', 'partner_terms', 'privacy', 'cancellation')
  ),
  version text not null check (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  title text not null,
  published_at timestamptz not null default now(),
  primary key (code, version)
);

insert into public.legal_documents (code, version, title) values
  ('player_terms', '2026-11-06', 'Termos de uso do jogador'),
  ('partner_terms', '2026-11-06', 'Termos do Parceiro'),
  ('privacy', '2026-11-06', 'Política de privacidade'),
  ('cancellation', '2026-11-06', 'Política de cancelamento e reembolso');

alter table public.legal_documents enable row level security;

create policy legal_documents_read on public.legal_documents
  for select to anon, authenticated
  using (true);

revoke all on table public.legal_documents from public, anon, authenticated;
grant select on table public.legal_documents to anon, authenticated;

create table public.terms_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  venue_id uuid references public.venues (id) on delete cascade,
  audience text not null check (audience in ('player', 'partner')),
  document_code text not null,
  document_version text not null,
  accepted_at timestamptz not null default now(),
  foreign key (document_code, document_version)
    references public.legal_documents (code, version),
  check (
    (
      audience = 'player'
      and venue_id is null
      and document_code in ('player_terms', 'privacy', 'cancellation')
    )
    or (
      audience = 'partner'
      and document_code in ('partner_terms', 'privacy', 'cancellation')
    )
  )
);

create unique index terms_acceptances_player
  on public.terms_acceptances (user_id, document_code, document_version)
  where audience = 'player';

create unique index terms_acceptances_partner_account
  on public.terms_acceptances (user_id, document_code, document_version)
  where audience = 'partner' and venue_id is null;

create unique index terms_acceptances_partner_venue
  on public.terms_acceptances (user_id, venue_id, document_code, document_version)
  where audience = 'partner' and venue_id is not null;

create index terms_acceptances_by_user on public.terms_acceptances (user_id);

alter table public.terms_acceptances enable row level security;

create policy terms_acceptances_select on public.terms_acceptances
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_admin()
    or (venue_id is not null and public.owns_venue(venue_id))
  );

revoke all on table public.terms_acceptances from public, anon, authenticated;
grant select on table public.terms_acceptances to authenticated;

-- O cliente não escolhe a data. A função grava now() e a versão publicada.
create or replace function public.accept_terms(
  p_audience text,
  p_venue_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_version text := '2026-11-06';
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_audience = 'player' then
    if p_venue_id is not null then
      raise exception 'player acceptance has no venue' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.legal_documents
      where code = 'player_terms' and version = v_version
    ) then
      raise exception 'unknown terms version' using errcode = '22023';
    end if;
    insert into public.terms_acceptances (
      user_id, audience, document_code, document_version
    )
    select v_user, 'player', d.code, v_version
    from (
      values ('player_terms'), ('privacy'), ('cancellation')
    ) as d(code)
    where not exists (
      select 1 from public.terms_acceptances t
      where t.user_id = v_user
        and t.audience = 'player'
        and t.document_code = d.code
        and t.document_version = v_version
    );
    return;
  end if;
  if p_audience = 'partner' then
    if p_venue_id is not null
      and not (public.owns_venue(p_venue_id) or public.is_admin()) then
      raise exception 'not owner' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.legal_documents
      where code = 'partner_terms' and version = v_version
    ) then
      raise exception 'unknown terms version' using errcode = '22023';
    end if;
    insert into public.terms_acceptances (
      user_id, venue_id, audience, document_code, document_version
    )
    select v_user, p_venue_id, 'partner', d.code, v_version
    from (
      values ('partner_terms'), ('privacy'), ('cancellation')
    ) as d(code)
    where not exists (
      select 1 from public.terms_acceptances t
      where t.user_id = v_user
        and t.audience = 'partner'
        and t.document_code = d.code
        and t.document_version = v_version
        and t.venue_id is not distinct from p_venue_id
    );
    return;
  end if;
  raise exception 'unknown audience' using errcode = '22023';
end;
$$;

revoke all on function public.accept_terms(text, uuid) from public, anon;
grant execute on function public.accept_terms(text, uuid) to authenticated, service_role;
