# Rascunho de esquema Supabase

Isto não está ligado ao app. Não há cliente Supabase, variável de ambiente, nem migração rodando. É o desenho para quando o `FakeGroupRepository` for trocado, em cima das decisões de [DECISOES.md](DECISOES.md) e do aviso de atomicidade em [ARQUITETURA.md](ARQUITETURA.md).

O banco é PostgreSQL, como o Supabase entrega. `auth.users` é a tabela de contas do Supabase Auth. O app ainda não autentica ninguém.

## Tabelas

- `cities` — cidade do seletor.
- `venues` — casa de escape.
- `rooms` — sala, com a capacidade física.
- `room_sessions` — horário oferecido pela casa, com o tipo de disponibilidade do `ExperienceSource`. Não é obrigatório para o grupo existir: um grupo “a combinar” pode nascer sem sessão.
- `groups` — o grupo que as pessoas montam. `total_spots` é quantas pessoas o grupo quer, e pode ser menor que a capacidade da sala.
- `group_members` — quem já sentou. A contagem de vagas preenchidas é `count(*)` aqui. Não há coluna `filled_spots` para o cliente atualizar.

```sql
-- Rascunho. Não executar isto no app desta versão.

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  state_code text not null,
  state_name text not null
);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.cities (id),
  name text not null,
  neighborhood text not null
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id),
  name text not null,
  theme text not null,
  capacity integer not null check (capacity > 0),
  duration_minutes integer not null check (duration_minutes > 0),
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard'))
);

create table public.room_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id),
  starts_at timestamptz,
  availability text not null check (
    availability in ('integrated', 'partner_grid', 'proposed', 'to_be_arranged')
  ),
  check (
    (availability = 'to_be_arranged' and starts_at is null)
    or (availability <> 'to_be_arranged' and starts_at is not null)
  )
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.cities (id),
  venue_id uuid not null references public.venues (id),
  room_id uuid not null references public.rooms (id),
  session_id uuid references public.room_sessions (id),
  starts_at timestamptz not null,
  total_spots integer not null check (total_spots >= 2),
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

-- Uma sala não hospeda dois grupos no mesmo instante.
create unique index groups_one_per_room_and_time
  on public.groups (room_id, starts_at);

create table public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id),
  display_name text not null check (char_length(display_name) between 1 and 80),
  is_creator boolean not null default false,
  joined_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create index group_members_by_group on public.group_members (group_id);
```

`filled_spots` para a tela pode ser uma view. Ela não guarda número que o cliente possa incrementar:

```sql
create view public.groups_with_counts
with (security_invoker = true) as
select
  g.*,
  (
    select count(*)::integer
    from public.group_members m
    where m.group_id = g.id
  ) as filled_spots
from public.groups g;
```

`security_invoker` faz a view obedecer o RLS de quem consulta, em vez do dono da view.

## RLS

Leitura da cidade, da casa, da sala, da sessão e do grupo é pública: a pessoa escolhe a cidade antes de ter conta. Escrever grupo ou membro direto pela API não é permitido. Quem entra passa pela função. Quem cria também.

```sql
alter table public.cities enable row level security;
alter table public.venues enable row level security;
alter table public.rooms enable row level security;
alter table public.room_sessions enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;

create policy cities_read on public.cities
  for select to anon, authenticated using (true);
create policy venues_read on public.venues
  for select to anon, authenticated using (true);
create policy rooms_read on public.rooms
  for select to anon, authenticated using (true);
create policy room_sessions_read on public.room_sessions
  for select to anon, authenticated using (true);
create policy groups_read on public.groups
  for select to anon, authenticated using (true);
create policy group_members_read on public.group_members
  for select to anon, authenticated using (true);

revoke insert, update, delete on public.cities from anon, authenticated;
revoke insert, update, delete on public.venues from anon, authenticated;
revoke insert, update, delete on public.rooms from anon, authenticated;
revoke insert, update, delete on public.room_sessions from anon, authenticated;
revoke insert, update, delete on public.groups from anon, authenticated;
revoke insert, update, delete on public.group_members from anon, authenticated;
```

Catálogo (cidade, casa, sala, sessão) entra por uma carga de serviço, não pelo celular. Por isso o cliente não recebe `insert` nessas tabelas.

## Entrar no grupo

A função trava a linha do grupo, conta os membros e só então insere. Duas pessoas na última vaga ficam em fila nesse `for update`: a segunda vê o grupo cheio. A decisão provisória é entrada livre, então não há linha de “pedido pendente”. O nome ainda vem do JWT (`user_metadata.display_name`) até existir uma tabela de perfil; se vier vazio, a função recusa, em vez de inventar “Você” no banco.

```sql
create or replace function public.join_group(p_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_total integer;
  v_filled integer;
  v_name text;
  v_member_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select total_spots
    into v_total
  from public.groups
  where id = p_group_id
  for update;

  if not found then
    raise exception 'group not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.group_members
    where group_id = p_group_id
      and user_id = v_user
  ) then
    raise exception 'already joined' using errcode = '23505';
  end if;

  select count(*)::integer
    into v_filled
  from public.group_members
  where group_id = p_group_id;

  if v_filled >= v_total then
    raise exception 'group full' using errcode = 'P0001';
  end if;

  v_name := nullif(trim(auth.jwt() -> 'user_metadata' ->> 'display_name'), '');
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;

  insert into public.group_members (group_id, user_id, display_name, is_creator)
  values (p_group_id, v_user, v_name, false)
  returning id into v_member_id;

  return v_member_id;
end;
$$;

revoke all on function public.join_group(uuid) from public;
grant execute on function public.join_group(uuid) to authenticated;
```

`security definer` ignora o RLS. Por isso o `revoke insert` na tabela só é seguro se a função fizer as checagens acima. Não mover a contagem para o app.

## Criar o grupo

Criar também é uma função, pelo mesmo motivo: o índice único e a cadeira de quem cria têm de acontecer juntos. Se duas pessoas pedirem a mesma sala no mesmo horário, a segunda cai no `unique_violation`.

```sql
create or replace function public.create_group(
  p_room_id uuid,
  p_starts_at timestamptz,
  p_total_spots integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_room public.rooms%rowtype;
  v_venue public.venues%rowtype;
  v_group_id uuid;
  v_name text;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_total_spots < 2 then
    raise exception 'group below minimum' using errcode = '22023';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'unknown room' using errcode = 'P0002';
  end if;
  if p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;

  select * into v_venue from public.venues where id = v_room.venue_id;

  v_name := nullif(trim(auth.jwt() -> 'user_metadata' ->> 'display_name'), '');
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;

  insert into public.groups (
    city_id, venue_id, room_id, starts_at, total_spots, created_by
  ) values (
    v_venue.city_id, v_venue.id, v_room.id, p_starts_at, p_total_spots, v_user
  )
  returning id into v_group_id;

  insert into public.group_members (group_id, user_id, display_name, is_creator)
  values (v_group_id, v_user, v_name, true);

  return v_group_id;
exception
  when unique_violation then
    raise exception 'duplicate session' using errcode = '23505';
end;
$$;

revoke all on function public.create_group(uuid, timestamptz, integer) from public;
grant execute on function public.create_group(uuid, timestamptz, integer) to authenticated;
```

## O que este rascunho não faz

- Não cria o projeto no Supabase.
- Não liga o Flutter.
- Não define a carga do catálogo a partir do `ExperienceSource`. Isso continua descrito em [DADOS_REAIS.md](DADOS_REAIS.md).
- Não trata perfil editável além do `display_name` no metadata do usuário. Uma tabela `profiles` pode substituir essa leitura quando a conta existir.
