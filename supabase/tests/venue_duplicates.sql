-- Prova da duplicata, do RLS e do que a função não pode devolver.
-- Roda depois das migrations, como superusuário, e troca de papel no meio.

\set ON_ERROR_STOP on

do $$
begin
  if public.normalize_venue_name('Ninja Escape Room Ltda.') <> 'ninja' then
    raise exception 'nome ninja virou %', public.normalize_venue_name('Ninja Escape Room Ltda.');
  end if;
  if public.normalize_venue_name('Mistério da Rua XV') <> 'misterio da rua xv' then
    raise exception 'nome misterio virou %', public.normalize_venue_name('Mistério da Rua XV');
  end if;
  if public.normalize_venue_name('Quest S.A.') <> 'quest' then
    raise exception 'nome quest virou %', public.normalize_venue_name('Quest S.A.');
  end if;
  if public.normalize_document('123.456.789-09') <> '12345678909' then
    raise exception 'cpf virou %', public.normalize_document('123.456.789-09');
  end if;
  if public.normalize_address_number('nº 120') <> '120'
    or public.normalize_address_number('S/N') <> 'sn' then
    raise exception 'número não normalizou';
  end if;
end $$;

do $$
declare
  v_public boolean;
  v_private boolean;
  v_result text;
begin
  select p.prosecdef
    into v_public
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'check_venue_duplicates';
  select p.prosecdef
    into v_private
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'check_venue_duplicates';
  if not v_public or not v_private then
    raise exception 'check_venue_duplicates precisa ser security definer nos dois schemas';
  end if;
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'check_venue_duplicates'
      and 'search_path=""' = any (p.proconfig)
  ) then
    raise exception 'check_venue_duplicates público sem search_path vazio';
  end if;

  select pg_get_function_result(p.oid)
    into v_result
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'check_venue_duplicates';
  if v_result ilike '%document%' or v_result ilike '%phone%' or v_result ilike '%telefone%' then
    raise exception 'retorno da função expõe dado pessoal: %', v_result;
  end if;

  if has_function_privilege(
    'anon',
    'public.check_venue_duplicates(text,text,text,text,text)',
    'execute'
  ) then
    raise exception 'anon executa check_venue_duplicates';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.check_venue_duplicates(text,text,text,text,text)',
    'execute'
  ) then
    raise exception 'authenticated não executa check_venue_duplicates';
  end if;
  if has_column_privilege('anon', 'public.venues', 'document_digits', 'select')
    or has_column_privilege('anon', 'public.venues', 'document_number', 'select')
    or has_column_privilege('anon', 'public.venues', 'phone', 'select')
    or has_column_privilege('anon', 'public.venues', 'name_normalized', 'select')
    or has_column_privilege('authenticated', 'public.venues', 'document_digits', 'select')
    or has_column_privilege('authenticated', 'public.venues', 'phone', 'select')
    or has_column_privilege('authenticated', 'public.venues', 'possible_duplicate_of', 'select')
    or has_column_privilege('authenticated', 'public.venues', 'merged_into', 'select') then
    raise exception 'documento, telefone ou vínculo de duplicata ficou legível';
  end if;
  if has_table_privilege('anon', 'public.venue_claims', 'select')
    or has_table_privilege('anon', 'public.venue_claims', 'insert') then
    raise exception 'anon alcança venue_claims';
  end if;
  if not (
    select c.relrowsecurity and c.relforcerowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'venue_claims'
  ) then
    raise exception 'venue_claims sem RLS estrita';
  end if;
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'venue_claims'
      and 'anon' = any (roles)
  ) then
    raise exception 'venue_claims tem política para anon';
  end if;
  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'venues_document_digits_active_uidx'
      and indexdef ilike '%unique%'
  ) then
    raise exception 'falta o índice único do documento';
  end if;
  if not exists (
    select 1 from pg_extension where extname = 'pg_trgm'
  ) then
    raise exception 'pg_trgm não foi instalada';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'dona@example.com', '{"display_name":"Dona"}'),
  ('22222222-2222-2222-2222-222222222222', 'outra@example.com', '{"display_name":"Outra"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@example.com', '{"display_name":"Admin"}');

insert into public.admins (user_id)
values ('33333333-3333-3333-3333-333333333333');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  '11111111-1111-1111-1111-111111111111',
  'curitiba',
  'Ninja Escape Room Ltda.',
  'Centro',
  'Rua das Flores',
  'nº 120',
  '80010-000',
  -25.43,
  -49.27,
  5000,
  'cnpj',
  '12.345.678/0001-95',
  '41988887777',
  'approved'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  '11111111-1111-1111-1111-111111111111',
  'curitiba',
  'Casa Sigilosa do Lote 9',
  'Batel',
  'Rua Escondida',
  '44',
  '80020999',
  -25.44,
  -49.28,
  4000,
  'cpf',
  '529.982.247-25',
  '41977776666',
  'pending'
);

do $$
declare
  v_digits text;
  v_name text;
  v_cep text;
  v_number text;
begin
  select document_digits, name_normalized, postal_code, address_number_normalized
    into v_digits, v_name, v_cep, v_number
  from public.venues
  where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  if v_digits <> '12345678000195' or v_name <> 'ninja' or v_cep <> '80010000' or v_number <> '120' then
    raise exception 'normalização da casa aprovada: % % % %', v_digits, v_name, v_cep, v_number;
  end if;
end $$;

begin;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_count integer;
  v_name text;
  v_id uuid;
  v_type text;
begin
  select count(*)
    into v_count
  from public.check_venue_duplicates(
    '12.345.678/0001-95',
    'Outra',
    'curitiba',
    '01310000',
    '999'
  )
  where conflict and conflict_type = 'documento';
  select venue_name, venue_id, conflict_type
    into v_name, v_id, v_type
  from public.check_venue_duplicates(
    '12.345.678/0001-95',
    'Outra',
    'curitiba',
    '01310000',
    '999'
  )
  where conflict and conflict_type = 'documento'
  limit 1;
  if v_count <> 1 or v_name <> 'Ninja Escape Room Ltda.' or v_id is null or v_type <> 'documento' then
    raise exception 'documento aprovado não avisou a casa pública: % %', v_count, v_name;
  end if;

  select count(*)
    into v_count
  from public.check_venue_duplicates(
    '529.982.247-25',
    'Outra',
    'curitiba',
    '01310000',
    '999'
  )
  where conflict and conflict_type = 'documento';
  select venue_name
    into v_name
  from public.check_venue_duplicates(
    '529.982.247-25',
    'Outra',
    'curitiba',
    '01310000',
    '999'
  )
  where conflict and conflict_type = 'documento';
  if v_count <> 1 or v_name is not null then
    raise exception 'documento pendente vazou nome: % %', v_count, v_name;
  end if;
  if exists (
    select 1
    from public.check_venue_duplicates(
      '529.982.247-25',
      'Casa Sigilosa do Lote 9',
      'curitiba',
      '80020999',
      '44'
    )
    where venue_name ilike '%sigilosa%'
       or conflict_type not in ('documento', 'endereço', 'nome parecido')
  ) then
    raise exception 'a função devolveu a casa pendente de terceiro';
  end if;

  if not exists (
    select 1
    from public.check_venue_duplicates(
      '10987654321',
      'Ninja Centro',
      'Curitiba',
      '01001000',
      '50'
    )
    where conflict and conflict_type = 'nome parecido' and venue_name = 'Ninja Escape Room Ltda.'
  ) then
    raise exception 'nome parecido na mesma cidade não avisou';
  end if;

  if exists (
    select 1
    from public.check_venue_duplicates(
      '10987654321',
      'Ninja Centro',
      'sao-paulo',
      '01001000',
      '50'
    )
    where conflict_type = 'nome parecido'
  ) then
    raise exception 'nome parecido cruzou a cidade';
  end if;

  if not exists (
    select 1
    from public.check_venue_duplicates(
      '10987654321',
      'Casa Totalmente Diferente',
      'curitiba',
      '80010-000',
      '120'
    )
    where conflict and conflict_type = 'endereço' and venue_name = 'Ninja Escape Room Ltda.'
  ) then
    raise exception 'mesmo CEP e número não avisou';
  end if;

  if exists (
    select 1
    from public.check_venue_duplicates(
      '10987654321',
      'Casa Totalmente Diferente',
      'curitiba',
      '80020999',
      '44'
    )
    where conflict_type = 'endereço'
  ) then
    raise exception 'endereço de casa pendente vazou';
  end if;
end $$;

do $$
begin
  begin
    perform 1
    from public.venues
    where document_number = '12345678000195';
    raise exception 'authenticated leu document_number';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    perform phone from public.venues;
    raise exception 'authenticated leu phone';
  exception
    when insufficient_privilege then
      null;
  end;
  if exists (
    select 1 from public.venues where name = 'Casa Sigilosa do Lote 9'
  ) then
    raise exception 'terceiro leu casa pendente';
  end if;
  if not exists (
    select 1 from public.venues where name = 'Ninja Escape Room Ltda.'
  ) then
    raise exception 'casa aprovada sumiu';
  end if;
end $$;

do $$
declare
  v_id uuid;
begin
  begin
    insert into public.venues (
      city_id, name, neighborhood, postal_code, latitude, longitude,
      income_value, document_number, phone
    ) values (
      'curitiba',
      'Cópia do Ninja',
      'Centro',
      '80010000',
      -25.43,
      -49.27,
      1000,
      '12345678000195',
      '41911112222'
    );
    raise exception 'documento repetido entrou';
  exception
    when unique_violation then
      if sqlerrm <> 'duplicate document' or sqlerrm ilike '%sigilosa%' or sqlerrm like '%12345678000195%' then
        raise exception 'erro do documento vazou: %', sqlerrm;
      end if;
  end;

  insert into public.venues (
    city_id, name, neighborhood, postal_code, address_number, latitude,
    longitude, income_value, document_number, phone, possible_duplicate_of
  ) values (
    'curitiba',
    'Ninja Centro',
    'Centro',
    '80010000',
    '120',
    -25.43,
    -49.27,
    1000,
    '99888777000166',
    '41911113333',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ) returning id into v_id;

  if v_id is null then
    raise exception 'cadastro parecido não entrou';
  end if;

  begin
    insert into public.venues (
      city_id, name, neighborhood, postal_code, latitude, longitude,
      income_value, document_number, phone, possible_duplicate_of
    ) values (
      'curitiba',
      'Ligação inválida',
      'Centro',
      '01001000',
      -23.5,
      -46.6,
      1000,
      '88777666000155',
      '41911114444',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    );
    raise exception 'possible_duplicate_of aceitou casa pendente';
  exception
    when foreign_key_violation then
      if sqlerrm <> 'invalid duplicate link' then
        raise exception 'erro do vínculo vazou: %', sqlerrm;
      end if;
  end;
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
set local role authenticated;

do $$
declare
  v_claim uuid;
begin
  select public.request_venue_claim(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'Sou a responsável pela casa.',
    null
  ) into v_claim;
  if v_claim is null then
    raise exception 'reivindicação não foi criada';
  end if;
  if not exists (
    select 1
    from public.venue_claims
    where id = v_claim
      and venue_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and status = 'pending'
      and note = 'Sou a responsável pela casa.'
  ) then
    raise exception 'quem pediu não vê o próprio pedido';
  end if;
  begin
    perform public.request_venue_claim(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'Casa pendente',
      null
    );
    raise exception 'reivindicação aceitou casa pendente';
  exception
    when sqlstate 'P0002' then
      null;
  end;
end $$;

rollback;

begin;
select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-2222-2222-222222222222',
  true
);
set local role authenticated;
select public.request_venue_claim(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Pedido da outra pessoa',
  null
);
reset role;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.venue_claims) then
    raise exception 'dona leu reivindicação alheia';
  end if;
  begin
    perform public.request_venue_claim(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'A casa já é minha',
      null
    );
    raise exception 'dona reivindicou a própria casa';
  exception
    when sqlstate 'P0002' then
      null;
  end;
  begin
    perform public.review_venue(
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'approved',
      null
    );
    raise exception 'quem não é admin aprovou casa';
  exception
    when insufficient_privilege then
      null;
  end;
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
set local role authenticated;
insert into public.venues (
  id, city_id, name, neighborhood, postal_code, address_number, latitude,
  longitude, income_value, document_number, phone, possible_duplicate_of
) values (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'curitiba',
  'Ninja Centro',
  'Centro',
  '80010000',
  '120',
  -25.43,
  -49.27,
  1000,
  '99888777000166',
  '41911113333',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
);
select public.request_venue_claim(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'A casa nova é a mesma.',
  'cccccccc-cccc-cccc-cccc-cccccccccccc'
);

reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);

do $$
begin
  if not exists (
    select 1
    from private.venue_link_status('cccccccc-cccc-cccc-cccc-cccccccccccc')
    where possible_duplicate_of = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ) then
    raise exception 'admin não vê a casa pendente marcada';
  end if;
end $$;

set local role authenticated;

do $$
declare
  v_claim uuid;
begin
  select id into v_claim from public.venue_claims where status = 'pending';
  if v_claim is null then
    raise exception 'admin não vê a reivindicação';
  end if;
  perform public.review_venue(
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'merged',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  );
  if not exists (
    select 1
    from public.venues
    where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
      and status = 'merged'
  ) then
    raise exception 'mescla não gravou';
  end if;
end $$;

reset role;

do $$
begin
  if not exists (
    select 1
    from private.venue_link_status('cccccccc-cccc-cccc-cccc-cccccccccccc')
    where merged_into = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  ) then
    raise exception 'mescla não gravou o vínculo';
  end if;
end $$;

rollback;

begin;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
set local role authenticated;
select public.request_venue_claim(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Quero a casa.',
  null
);
reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
set local role authenticated;

do $$
declare
  v_claim uuid;
begin
  select id into v_claim from public.venue_claims where status = 'pending';
  perform public.review_venue_claim(v_claim, 'approved');
  if not exists (
    select 1
    from public.venues
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and owner_id = '22222222-2222-2222-2222-222222222222'
      and status = 'approved'
  ) then
    raise exception 'aprovar a reivindicação não passou a casa';
  end if;
end $$;

reset role;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  true
);
set local role authenticated;
update public.venues
set neighborhood = 'Invadido'
where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

do $$
begin
  if exists (
    select 1
    from public.venues
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and neighborhood = 'Invadido'
  ) then
    raise exception 'dona antiga ainda altera a casa';
  end if;
end $$;

rollback;

begin;
select set_config('search_path', '', true);
insert into public.venues (
  owner_id, city_id, name, neighborhood, postal_code, latitude, longitude,
  income_value, document_kind, document_number, phone
) values (
  '22222222-2222-2222-2222-222222222222',
  'curitiba',
  'Ação & Café Ltda.',
  'Centro',
  '80020000',
  -25.43,
  -49.27,
  1000,
  'cnpj',
  '11222333000181',
  '41910000000'
);
do $$
declare
  v_norm text;
begin
  select name_normalized
    into v_norm
  from public.venues
  where document_digits = '11222333000181';
  if v_norm is null or position('acao' in v_norm) = 0 or v_norm ~ '[áàãâéêíóôõúç]' then
    raise exception 'unaccent falhou com search_path vazio: %', coalesce(v_norm, '(nulo)');
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
set local role authenticated;
do $$
begin
  if exists (
    select 1
    from public.check_venue_duplicates(
      '12.345.678/0001-95',
      'Outra',
      'curitiba',
      '01310000',
      '999'
    )
    where conflict_type = 'documento'
  ) then
    raise exception 'dono com casa ativa enumerou documento';
  end if;
end $$;
rollback;

begin;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
set local role authenticated;
do $$
declare
  i integer;
begin
  for i in 1..10 loop
    perform 1
    from public.check_venue_duplicates(
      '00000000000',
      'x',
      'curitiba',
      '00000000',
      '1'
    );
  end loop;
  begin
    perform 1
    from public.check_venue_duplicates(
      '00000000000',
      'x',
      'curitiba',
      '00000000',
      '1'
    );
    raise exception 'a 11ª consulta de documento passou';
  exception
    when others then
      if sqlerrm <> 'too many attempts' then
        raise exception 'limite inesperado: %', sqlerrm;
      end if;
  end;
end $$;
rollback;

begin;
set local role anon;
do $$
begin
  begin
    perform * from public.check_venue_duplicates('1', 'a', 'curitiba', '80010000', '1');
    raise exception 'anon chamou check_venue_duplicates';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    perform * from public.venue_claims;
    raise exception 'anon leu venue_claims';
  exception
    when insufficient_privilege then
      null;
  end;
  begin
    perform document_digits from public.venues;
    raise exception 'anon leu document_digits';
  exception
    when insufficient_privilege then
      null;
  end;
  if exists (
    select 1 from public.venues where name = 'Casa Sigilosa do Lote 9'
  ) then
    raise exception 'anon leu casa pendente';
  end if;
  if not exists (
    select 1 from public.venues where name = 'Ninja Escape Room Ltda.'
  ) then
    raise exception 'anon não lê a casa aprovada';
  end if;
end $$;
rollback;
