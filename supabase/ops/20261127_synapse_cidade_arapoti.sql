-- Correção de dados proposta (NÃO aplicada): a Synapse Escape Room fica em
-- Arapoti-PR, mas foi cadastrada com Curitiba porque o cadastro antigo não
-- tinha a cidade. Em 27/11/2026: 0 salas e 0 grupos, então nada mais muda.
-- Rodar só com o ok do Nícolas, no SQL editor do projeto, como admin.

begin;

update public.venues
set city_id = 'arapoti-pr',
    latitude = c.latitude,
    longitude = c.longitude
from public.cities c
where c.id = 'arapoti-pr'
  and public.venues.id = '20295a2e-ee3e-4f99-b5a3-cdf8135344d9'
  and public.venues.city_id = 'curitiba';

-- Confere: deve mostrar arapoti-pr.
select id, name, city_id, latitude, longitude
from public.venues
where id = '20295a2e-ee3e-4f99-b5a3-cdf8135344d9';

commit;
