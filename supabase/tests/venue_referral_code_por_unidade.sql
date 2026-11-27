-- Login com duas unidades: cada uma tem o próprio código, e ninguém lê o
-- código de unidade alheia. Roda dentro de uma transação e desfaz.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e1a11111-1111-4111-8111-111111111111', 'unidades@example.com', '{"display_name":"Dono"}'),
  ('e1a22222-2222-4222-8222-222222222222', 'outro@example.com', '{"display_name":"Outro"}');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status, created_at
) values
  ('e1a11111-1111-4111-8111-1111111111c1', 'e1a11111-1111-4111-8111-111111111111',
   'curitiba', 'Casa Unidade Um', 'Centro', 'Rua Um', '1', '80020000',
   -25.43, -49.27, 5000, 'cnpj', '11222333000181', '41988880001', 'approved',
   now() - interval '2 days'),
  ('e1a11111-1111-4111-8111-1111111111c2', 'e1a11111-1111-4111-8111-111111111111',
   'curitiba', 'Casa Unidade Dois', 'Centro', 'Rua Dois', '2', '80020001',
   -25.43, -49.27, 5000, 'cnpj', '11444777000161', '41988880002', 'pending',
   now() - interval '1 day'),
  ('e1a22222-2222-4222-8222-2222222222c3', 'e1a22222-2222-4222-8222-222222222222',
   'curitiba', 'Casa De Outro Dono', 'Centro', 'Rua Tres', '3', '80020002',
   -25.43, -49.27, 5000, 'cnpj', '11555888000106', '41988880003', 'approved',
   now());

select set_config('request.jwt.claim.sub', 'e1a11111-1111-4111-8111-111111111111', true);
set local role authenticated;

do $$
declare
  v_one text := public.my_venue_referral_code('e1a11111-1111-4111-8111-1111111111c1');
  v_two text := public.my_venue_referral_code('e1a11111-1111-4111-8111-1111111111c2');
  v_other text := public.my_venue_referral_code('e1a22222-2222-4222-8222-2222222222c3');
  v_newest text := public.my_venue_referral_code();
begin
  if v_one is null or v_two is null then
    raise exception 'unidade do login ficou sem código (% / %)', v_one, v_two;
  end if;
  if v_one = v_two then
    raise exception 'as duas unidades devolveram o mesmo código';
  end if;
  if v_other is not null then
    raise exception 'leu o código de unidade de outro dono';
  end if;
  if v_newest is distinct from v_two then
    raise exception 'o RPC antigo deixou de devolver a unidade mais nova';
  end if;
end $$;

reset role;
rollback;
