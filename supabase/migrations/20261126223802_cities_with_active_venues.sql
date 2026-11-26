-- Cidades que têm pelo menos uma casa aprovada e não suspensa.
-- O app do jogador lista só estas. Com os 5571 municípios em public.cities,
-- ler a tabela inteira passaria do corte de 1000 linhas da API.
--
-- Não destrutivo: só cria uma view. security_invoker faz a RLS de
-- public.venues valer para quem consulta: o anon não vê casa de teste
-- nem casa suspensa, e nenhuma coluna sensível sai (a view só devolve
-- id, name, state_code e state_name da cidade).
-- Não aplicar em produção antes do ok do Nícolas.

create or replace view public.cities_with_active_venues
with (security_invoker = true) as
select
  c.id,
  c.name,
  c.state_code,
  c.state_name
from public.cities c
where exists (
  select 1
  from public.venues v
  where v.city_id = c.id
    and v.status = 'approved'
    and v.suspended_at is null
);

comment on view public.cities_with_active_venues is
  'Cidades com casa aprovada e não suspensa. A RLS de venues vale para quem consulta.';

revoke all on table public.cities_with_active_venues
  from public, anon, authenticated;
grant select on table public.cities_with_active_venues
  to anon, authenticated, service_role;
