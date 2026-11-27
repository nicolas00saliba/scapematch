-- Admin compartilha a conta PagBank entre cidades do mesmo dono e reativa
-- cidade removida (20261127200000). Exige MFA e grava auditoria. Desfaz no fim.

\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e4a11111-1111-4111-8111-111111111111', 'dono-adm-unid@example.com', '{"display_name":"Dono"}'),
  ('e4a22222-2222-4222-8222-222222222222', 'outro-adm-unid@example.com', '{"display_name":"Outro"}'),
  ('e4a33333-3333-4333-8333-333333333333', 'admin-adm-unid@example.com', '{"display_name":"Admin"}');
insert into public.admins (user_id) values ('e4a33333-3333-4333-8333-333333333333');

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values
  ('e4a11111-1111-4111-8111-1111111111a1', 'e4a11111-1111-4111-8111-111111111111',
   'curitiba', 'Adm Unid Curitiba', 'Centro', 'Rua A', '1', '80020020',
   -25.43, -49.27, 5000, 'cnpj', '27200000000101', '41977790001', 'approved'),
  ('e4a11111-1111-4111-8111-1111111111a2', 'e4a11111-1111-4111-8111-111111111111',
   'curitiba', 'Adm Unid Cascavel', 'Centro', 'Rua B', '2', '80020021',
   -25.43, -49.27, 5000, 'cnpj', '27200000000202', '41977790002', 'pending'),
  ('e4a22222-2222-4222-8222-2222222222b1', 'e4a22222-2222-4222-8222-222222222222',
   'curitiba', 'Adm Unid Outro Dono', 'Centro', 'Rua C', '3', '80020022',
   -25.43, -49.27, 5000, 'cnpj', '27200000000303', '41977790003', 'approved');

select public.connect_venue_pagbank(
  'e4a11111-1111-4111-8111-1111111111a1', 'e4a11111-1111-4111-8111-111111111111',
  'ACCO_E4A00000-0000-4000-8000-00000000A1A1', 'acc-e4a', 'ref-e4a',
  now() + interval '1 hour'
);

-- Conta única da casa: conectar a1 liga a2 (mesmo dono) e não b1.
do $$
declare
  v_out jsonb;
  v_ok boolean := false;
  v_msg text;
begin
  if not exists (
    select 1 from public.venues
    where id = 'e4a11111-1111-4111-8111-1111111111a2'
      and pagbank_token_venue_id = 'e4a11111-1111-4111-8111-1111111111a1'
  ) or exists (
    select 1 from public.venues
    where id = 'e4a22222-2222-4222-8222-2222222222b1' and pagbank_account_id is not null
  ) then
    raise exception 'conta da casa não ligou só as cidades do dono';
  end if;

  -- Outra conta numa cidade da casa: recusada (a casa troca a conta dela).
  update public.venues set pagbank_account_id = null, pagbank_token_venue_id = null
  where id = 'e4a11111-1111-4111-8111-1111111111a2';
  begin
    perform public.connect_venue_pagbank(
      'e4a11111-1111-4111-8111-1111111111a2', 'e4a11111-1111-4111-8111-111111111111',
      'ACCO_E4A00000-0000-4000-8000-00000000B2B2', 'acc-b2', 'ref-b2',
      now() + interval '1 hour'
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_account_exists';
  end;
  if not v_ok then raise exception 'casa ficou com duas contas'; end if;

  -- A mesma conta por outra cidade: renova na cidade que guarda o token.
  v_out := public.connect_venue_pagbank(
    'e4a11111-1111-4111-8111-1111111111a2', 'e4a11111-1111-4111-8111-111111111111',
    'ACCO_E4A00000-0000-4000-8000-00000000A1A1', 'acc-e4a-2', 'ref-e4a-2',
    now() + interval '1 hour'
  );
  if v_out ->> 'house_root' <> 'e4a11111-1111-4111-8111-1111111111a1' then
    raise exception 'connect pela outra cidade devolveu %', v_out;
  end if;
  if exists (select 1 from public.venue_pagbank_tokens
             where venue_id = 'e4a11111-1111-4111-8111-1111111111a2')
    or (select access_token from public.read_venue_pagbank_tokens(
          'e4a11111-1111-4111-8111-1111111111a1')) is distinct from 'acc-e4a-2'
  then
    raise exception 'token não foi para a cidade da conta da casa';
  end if;
end $$;

-- Para testar o compartilhamento pelo Admin, solta a2.
update public.venues set pagbank_account_id = null, pagbank_token_venue_id = null
where id = 'e4a11111-1111-4111-8111-1111111111a2';

-- Sem MFA (aal1) o Admin não usa.
select set_config('request.jwt.claim.sub', 'e4a33333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal1', true);
set local role authenticated;
do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.admin_share_venue_pagbank_account(
      'e4a11111-1111-4111-8111-1111111111a2', 'e4a11111-1111-4111-8111-1111111111a1'
    );
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'admin sem MFA compartilhou'; end if;
end $$;
reset role;

-- Dono comum não chama as funções do Admin.
select set_config('request.jwt.claim.sub', 'e4a11111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.admin_reactivate_unit('e4a11111-1111-4111-8111-1111111111a2');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then raise exception 'dono chamou função do Admin'; end if;
end $$;
reset role;

-- Admin com MFA.
select set_config('request.jwt.claim.sub', 'e4a33333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_out jsonb;
  v_ok boolean;
  v_msg text;
begin
  v_out := public.admin_venue_units('e4a11111-1111-4111-8111-1111111111a2');
  if jsonb_array_length(v_out -> 'share_sources') <> 1
    or v_out -> 'share_sources' -> 0 ->> 'venue_id' <> 'e4a11111-1111-4111-8111-1111111111a1'
    or v_out::text ~ 'ACCO_'
  then
    raise exception 'origens do admin: %', v_out;
  end if;

  -- Outro dono: recusado.
  v_ok := false;
  begin
    perform public.admin_share_venue_pagbank_account(
      'e4a22222-2222-4222-8222-2222222222b1', 'e4a11111-1111-4111-8111-1111111111a1'
    );
  exception when sqlstate 'PB409' then
    get stacked diagnostics v_msg = message_text;
    v_ok := v_msg = 'pagbank_share_invalid';
  end;
  if not v_ok then raise exception 'admin compartilhou entre donos diferentes'; end if;

  v_out := public.admin_share_venue_pagbank_account(
    'e4a11111-1111-4111-8111-1111111111a2', 'e4a11111-1111-4111-8111-1111111111a1'
  );
  if (v_out ->> 'shared')::boolean is not true then
    raise exception 'admin share devolveu %', v_out;
  end if;
  v_out := public.admin_venue_units('e4a11111-1111-4111-8111-1111111111a2');
  if v_out ->> 'shared_from_name' <> 'Adm Unid Curitiba'
    or jsonb_array_length(v_out -> 'share_sources') <> 0
  then
    raise exception 'admin_venue_units depois do share: %', v_out;
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if not exists (
    select 1 from public.venues
    where id = 'e4a11111-1111-4111-8111-1111111111a2'
      and pagbank_token_venue_id = 'e4a11111-1111-4111-8111-1111111111a1'
      and pagbank_account_id = 'ACCO_E4A00000-0000-4000-8000-00000000A1A1'
  ) then
    raise exception 'conta não ficou compartilhada';
  end if;
  if not exists (
    select 1 from public.admin_audit_log
    where action = 'admin_share_pagbank'
      and actor_id = 'e4a33333-3333-4333-8333-333333333333'
      and target_id = 'e4a11111-1111-4111-8111-1111111111a2'
      and after_state::text !~ 'ACCO_'
  ) then
    raise exception 'sem auditoria do share do admin';
  end if;
end $$;

-- Reativar pelo Admin: removida pelo dono (em análise) e removida pelo Admin
-- (suspensa antes, sem auditoria = estado desconhecido, continua suspensa).
select set_config('request.jwt.claim.sub', 'e4a11111-1111-4111-8111-111111111111', true);
set local role authenticated;
select public.deactivate_my_unit('e4a11111-1111-4111-8111-1111111111a2');
reset role;
select set_config('request.jwt.claim.sub', '', true);
update public.venues
set suspended_at = now() - interval '3 days',
    deactivated_at = now() - interval '2 days',
    deactivated_by = 'e4a33333-3333-4333-8333-333333333333'
where id = 'e4a22222-2222-4222-8222-2222222222b1';

select set_config('request.jwt.claim.sub', 'e4a33333-3333-4333-8333-333333333333', true);
select set_config('request.jwt.claim.aal', 'aal2', true);
set local role authenticated;
do $$
declare
  v_out jsonb;
begin
  v_out := public.admin_venue_units('e4a22222-2222-4222-8222-2222222222b1');
  if (v_out ->> 'deactivated')::boolean is not true
    or (v_out ->> 'deactivated_by_owner')::boolean
  then
    raise exception 'admin_venue_units da removida pelo admin: %', v_out;
  end if;

  v_out := public.admin_reactivate_unit('e4a11111-1111-4111-8111-1111111111a2');
  if v_out ->> 'status' <> 'pending' or (v_out ->> 'suspended')::boolean then
    raise exception 'admin reativar a2 devolveu %', v_out;
  end if;
  v_out := public.admin_reactivate_unit('e4a22222-2222-4222-8222-2222222222b1');
  if (v_out ->> 'suspended')::boolean is not true
    or (v_out ->> 'previous_known')::boolean
  then
    raise exception 'admin reativar b1 devolveu %', v_out;
  end if;
  v_out := public.admin_reactivate_unit('e4a11111-1111-4111-8111-1111111111a2');
  if (v_out ->> 'already')::boolean is not true then
    raise exception 'repetir devolveu %', v_out;
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  if not exists (
    select 1 from public.venues
    where id = 'e4a11111-1111-4111-8111-1111111111a2'
      and status = 'pending' and deactivated_at is null and suspended_at is null
  ) then
    raise exception 'a2 não voltou em análise';
  end if;
  if not exists (
    select 1 from public.venues
    where id = 'e4a22222-2222-4222-8222-2222222222b1'
      and deactivated_at is null and suspended_at is not null
  ) then
    raise exception 'b1 perdeu a suspensão';
  end if;
  if (select count(*) from public.admin_audit_log
      where action = 'admin_reactivate_unit'
        and actor_id = 'e4a33333-3333-4333-8333-333333333333') <> 2
  then
    raise exception 'auditoria do reativar do admin';
  end if;
  if has_function_privilege('anon', 'public.admin_reactivate_unit(uuid)', 'execute')
    or has_function_privilege('anon', 'public.admin_share_venue_pagbank_account(uuid,uuid)', 'execute')
    or has_function_privilege('anon', 'public.admin_venue_units(uuid)', 'execute')
  then
    raise exception 'anon executa função do Admin';
  end if;
end $$;

rollback;
