-- Dias e horários em que o jogador ainda pode criar um grupo.
-- Não aplicado no remoto.
--
-- Livre: sessão da casa com hora marcada, sem cancelled_at, com mais de
-- 1 h de antecedência (o create_group recusa "too close to create" e
-- "session started") e sem grupo ativo na mesma sala no mesmo instante.
-- O índice groups_one_per_room_and_time ocupa o horário enquanto
-- groups.cancelled_at é nulo, mesmo sem pagamento. Grupo cancelado
-- devolve o horário. Sessão removida pela casa (cancelled_at) não volta.
-- O dia é o calendário America/Sao_Paulo.
--
-- security invoker: a leitura passa pelo RLS já público do catálogo
-- (casa aprovada, visível, sessão cancelada só para dono/admin).
-- Não há grant novo de tabela para anon.

create or replace function public.venue_open_slots(p_venue_id uuid)
returns table (
  session_id uuid,
  room_id uuid,
  room_name text,
  starts_at timestamptz,
  day date,
  starts_hm text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    s.id,
    r.id,
    r.name,
    s.starts_at,
    (s.starts_at at time zone 'America/Sao_Paulo')::date,
    pg_catalog.to_char(
      s.starts_at at time zone 'America/Sao_Paulo',
      'HH24:MI'
    )
  from public.room_sessions s
  join public.rooms r on r.id = s.room_id
  where r.venue_id = p_venue_id
    and s.cancelled_at is null
    and s.starts_at is not null
    and s.starts_at > pg_catalog.now() + interval '1 hour'
    and not exists (
      select 1
      from public.groups g
      where g.cancelled_at is null
        and (
          g.session_id = s.id
          or (g.room_id = s.room_id and g.starts_at = s.starts_at)
        )
    )
  order by 3, s.starts_at;
$$;

comment on function public.venue_open_slots(uuid) is
  'Horários livres das salas de uma casa. Dia em America/Sao_Paulo. Sem passado, sem a janela de 1 h, sem sessão removida e sem grupo ativo.';

create or replace function public.venue_open_days(p_venue_id uuid)
returns table (day date)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct s.day
  from public.venue_open_slots(p_venue_id) s
  order by s.day;
$$;

comment on function public.venue_open_days(uuid) is
  'Dias em que a casa tem pelo menos um horário livre em alguma sala.';

revoke all on function public.venue_open_slots(uuid) from public;
revoke all on function public.venue_open_days(uuid) from public;
grant execute on function public.venue_open_slots(uuid)
  to anon, authenticated, service_role;
grant execute on function public.venue_open_days(uuid)
  to anon, authenticated, service_role;
