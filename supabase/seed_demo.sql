-- Opcional. Não faz parte das migrations obrigatórias.
-- Casa real no banco, para a demonstração: o jogador cria o grupo aqui,
-- o Pix de teste cai nesta casa e o saldo aparece no Parceiro.
-- Não é dado de exemplo do app. Rode depois das migrations e depois de
-- inserir o seu usuário em public.admins.
--
-- O walletId da subconta sandbox NÃO entra neste arquivo. Depois de gravar
-- ASAAS_API_KEY na função, chame provision-venue-wallet. Ela cria a subconta
-- da ScapeMatch Demo e salva venues.asaas_wallet_id.

do $$
declare
  v_owner uuid;
  v_venue uuid;
  v_cofre uuid;
  v_biblioteca uuid;
  v_calabouco uuid;
  v_day date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select user_id into v_owner from public.admins order by created_at limit 1;
  if v_owner is null then
    raise exception 'Crie o admin antes do seed. Veja supabase/README.md.';
  end if;

  if exists (select 1 from public.venues where name = 'ScapeMatch Demo') then
    raise exception 'ScapeMatch Demo já existe.';
  end if;

  insert into public.venues (
    owner_id, city_id, name, neighborhood, street_address, address_number,
    postal_code, latitude, longitude, document_kind, document_number, phone,
    income_value, category, status, reviewed_by, reviewed_at
  ) values (
    v_owner,
    'curitiba',
    'ScapeMatch Demo',
    'Centro',
    'Rua XV de Novembro',
    '100',
    '80020310',
    -25.4296,
    -49.2719,
    'cnpj',
    '04252011000110',
    '41999990000',
    5000,
    'escape-room',
    'approved',
    v_owner,
    now()
  )
  returning id into v_venue;

  insert into public.rooms (
    venue_id, name, theme, category, game_type, capacity, minimum_players,
    duration_minutes, difficulty, price_cents
  ) values (
    v_venue,
    'O Cofre',
    'Um cofre no centro da cidade.',
    'mystery',
    'escape-room',
    6,
    2,
    60,
    'medium',
    12000
  )
  returning id into v_cofre;

  insert into public.rooms (
    venue_id, name, theme, category, game_type, capacity, minimum_players,
    duration_minutes, difficulty, price_cents
  ) values (
    v_venue,
    'A Biblioteca',
    'Uma biblioteca que esconde a saída.',
    'adventure',
    'escape-room',
    8,
    3,
    60,
    'easy',
    10000
  )
  returning id into v_biblioteca;

  insert into public.rooms (
    venue_id, name, theme, category, game_type, capacity, minimum_players,
    duration_minutes, difficulty, price_cents
  ) values (
    v_venue,
    'O Calabouço',
    'Uma cela e uma hora para sair.',
    'terror',
    'escape-room',
    6,
    4,
    60,
    'hard',
    14000
  )
  returning id into v_calabouco;

  insert into public.room_sessions (room_id, starts_at, availability)
  select room_id, starts_at, 'partner_grid'
  from (
    values
      (v_cofre, ((v_day + 2)::timestamp + time '19:00') at time zone 'America/Sao_Paulo'),
      (v_cofre, ((v_day + 3)::timestamp + time '21:00') at time zone 'America/Sao_Paulo'),
      (v_biblioteca, ((v_day + 2)::timestamp + time '16:30') at time zone 'America/Sao_Paulo'),
      (v_biblioteca, ((v_day + 4)::timestamp + time '14:00') at time zone 'America/Sao_Paulo'),
      (v_calabouco, ((v_day + 3)::timestamp + time '19:00') at time zone 'America/Sao_Paulo'),
      (v_calabouco, ((v_day + 5)::timestamp + time '21:00') at time zone 'America/Sao_Paulo')
  ) as slot(room_id, starts_at);

  insert into public.promotions (venue_id, title, active)
  values
    (v_venue, 'Noite de abertura', true),
    (v_venue, 'Grupo de 6 na sexta', true);
end $$;
