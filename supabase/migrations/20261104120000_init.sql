-- ScapeMatch: tabelas, cidades e a taxa inicial.
-- O cliente não recebe service_role. Escrita sensível fica nas funções
-- da migração seguinte.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  birth_date date,
  asaas_customer_id text unique,
  created_at timestamptz not null default now()
);

create table public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.cities (
  id text primary key,
  name text not null,
  state_code text not null,
  state_name text not null,
  latitude double precision not null,
  longitude double precision not null
);

insert into public.cities (id, name, state_code, state_name, latitude, longitude)
values
  ('curitiba', 'Curitiba', 'PR', 'Paraná', -25.4284, -49.2733),
  ('sao-paulo', 'São Paulo', 'SP', 'São Paulo', -23.5505, -46.6333),
  ('rio-de-janeiro', 'Rio de Janeiro', 'RJ', 'Rio de Janeiro', -22.9068, -43.1729),
  ('belo-horizonte', 'Belo Horizonte', 'MG', 'Minas Gerais', -19.9167, -43.9345),
  ('porto-alegre', 'Porto Alegre', 'RS', 'Rio Grande do Sul', -30.0346, -51.2177);

create table public.partner_invites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null,
  city_id text not null references public.cities (id),
  badge text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  check (char_length(code) between 3 and 40)
);

-- Convite real da primeira casa. O link e o QR usam este código.
insert into public.partner_invites (code, label, city_id, badge)
values (
  'ninja-cwb',
  'Ninja Escape Room',
  'curitiba',
  'Parceira Fundadora'
);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id),
  city_id text not null references public.cities (id),
  name text not null check (char_length(name) between 2 and 80),
  neighborhood text not null check (char_length(neighborhood) between 2 and 80),
  street_address text not null default '',
  address_number text not null default 'S/N',
  postal_code text not null,
  latitude double precision not null,
  longitude double precision not null,
  -- Renda mensal em reais. O Asaas exige este número ao abrir a subconta.
  income_value numeric not null check (income_value > 0),
  asaas_wallet_id text unique,
  document_kind text not null check (document_kind in ('cpf', 'cnpj')),
  document_number text not null,
  phone text not null,
  category text not null default 'escape-room' check (
    category in ('escape-room', 'rpg', 'board-game', 'laser-tag', 'immersive')
  ),
  badge text,
  invite_id uuid references public.partner_invites (id),
  -- Casa que indicou esta. Sem regra de recompensa nesta versão.
  referred_by uuid references public.venues (id),
  status text not null default 'pending' check (
    status in ('pending', 'approved', 'rejected')
  ),
  reviewed_by uuid references auth.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (document_kind = 'cpf' and document_number ~ '^[0-9]{11}$')
    or (document_kind = 'cnpj' and document_number ~ '^[0-9]{14}$')
  ),
  check (phone ~ '^[0-9]{10,13}$'),
  check (postal_code ~ '^[0-9]{8}$'),
  check (referred_by is null or referred_by <> id)
);

create index venues_by_owner on public.venues (owner_id);
create index venues_by_city_status on public.venues (city_id, status);
create index venues_by_referrer on public.venues (referred_by);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  theme text not null default '',
  category text not null default 'mystery' check (
    category in (
      'terror',
      'mystery',
      'adventure',
      'scienceFiction',
      'steampunk',
      'egypt'
    )
  ),
  game_type text not null default 'escape-room' check (
    game_type in ('escape-room', 'rpg', 'board-game', 'laser-tag', 'immersive')
  ),
  capacity integer not null check (capacity between 2 and 12),
  minimum_players integer not null check (
    minimum_players between 2 and 6 and minimum_players <= capacity
  ),
  duration_minutes integer not null check (duration_minutes between 15 and 480),
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard')),
  price_cents integer not null check (price_cents between 100 and 500000),
  price_mode text not null default 'per_person' check (
    price_mode in ('per_person', 'fixed_group')
  ),
  cancel_window_minutes integer not null default 120 check (
    cancel_window_minutes >= 0
  ),
  accent integer not null default 0,
  created_at timestamptz not null default now()
);

create index rooms_by_venue on public.rooms (venue_id);

create table public.room_photos (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index room_photos_by_room on public.room_photos (room_id, sort_order);

create table public.room_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  starts_at timestamptz,
  availability text not null check (
    availability in ('integrated', 'partner_grid', 'proposed', 'to_be_arranged')
  ),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (availability = 'to_be_arranged' and starts_at is null)
    or (availability <> 'to_be_arranged' and starts_at is not null)
  )
);

create index room_sessions_by_room on public.room_sessions (room_id, starts_at);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  city_id text not null references public.cities (id),
  venue_id uuid not null references public.venues (id),
  room_id uuid not null references public.rooms (id),
  session_id uuid references public.room_sessions (id),
  starts_at timestamptz not null,
  total_spots integer not null check (total_spots >= 2),
  minimum_spots integer not null check (minimum_spots >= 2),
  price_cents integer not null check (price_cents >= 0),
  price_mode text not null default 'per_person' check (
    price_mode in ('per_person', 'fixed_group')
  ),
  note text not null default '' check (char_length(note) <= 280),
  cancel_window_minutes integer not null default 120 check (
    cancel_window_minutes >= 0
  ),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancel_reason text not null default '',
  closed_at timestamptz,
  closes_at timestamptz,
  check (total_spots >= minimum_spots)
);

create unique index groups_one_per_room_and_time
  on public.groups (room_id, starts_at)
  where cancelled_at is null;

create index groups_by_city on public.groups (city_id, starts_at);
create index groups_by_venue on public.groups (venue_id, starts_at);

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id),
  display_name text not null check (char_length(display_name) between 1 and 80),
  is_creator boolean not null default false,
  attendance text not null default 'joined' check (
    attendance in ('joined', 'confirmed', 'cancelled')
  ),
  payment_status text not null default 'pending' check (
    payment_status in ('pending', 'reserved', 'paid', 'released')
  ),
  refund_status text not null default 'none' check (
    refund_status in ('none', 'refunded', 'denied')
  ),
  refund_reason text not null default 'none' check (
    refund_reason in (
      'none',
      'cancelled_in_time',
      'cancelled_too_late',
      'organizer_cancelled_event',
      'organizer_removed_member',
      'group_did_not_close',
      'hold_released'
    )
  ),
  joined_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create index group_members_by_group on public.group_members (group_id);
create index group_members_by_user on public.group_members (user_id);

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id),
  display_name text not null check (char_length(display_name) between 1 and 80),
  joined_at timestamptz not null default now(),
  offer_expires_at timestamptz,
  unique (group_id, user_id)
);

create table public.news_items (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 120),
  summary text not null check (char_length(summary) between 2 and 400),
  category text not null check (
    category in ('new_room', 'schedule', 'promotion', 'event')
  ),
  game_type text not null default 'escape-room' check (
    game_type in ('escape-room', 'rpg', 'board-game', 'laser-tag', 'immersive')
  ),
  image_url text,
  source_kind text not null default 'manual' check (
    source_kind in ('website', 'instagram', 'manual')
  ),
  source_url text,
  published_at timestamptz not null default now()
);

create index news_by_venue on public.news_items (venue_id, published_at desc);

create table public.promotions (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 80),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index promotions_by_venue on public.promotions (venue_id, created_at desc);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id),
  marked_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id),
  group_id uuid references public.groups (id),
  user_id uuid references auth.users (id),
  account text not null check (account in ('house', 'platform')),
  direction text not null check (direction in ('credit', 'debit')),
  kind text not null check (
    kind in ('house_net', 'commission', 'house_refund', 'commission_refund')
  ),
  amount_cents integer not null check (amount_cents > 0),
  payment_charge_id uuid,
  created_at timestamptz not null default now()
);

create index ledger_by_venue on public.ledger_entries (venue_id, created_at desc);

create table public.platform_settings (
  id integer primary key default 1 check (id = 1),
  commission_bps integer not null default 1000 check (
    commission_bps between 0 and 10000
  )
);

insert into public.platform_settings (id, commission_bps) values (1, 1000);

create or replace view public.groups_with_counts
with (security_invoker = true) as
select
  g.*,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance <> 'cancelled'
  ) as filled_spots,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
      and m.attendance = 'confirmed'
  ) as confirmed_count
from public.groups g;
