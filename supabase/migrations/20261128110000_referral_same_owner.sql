-- Casa indica casa: unidade do mesmo dono não pode se autoindicar.
--
-- Desde o cadastro de várias unidades no mesmo login, private.identity_conflict
-- só barrava casa x casa quando o CNPJ ou o telefone coincidiam. Duas cidades
-- com documentos diferentes passavam, gravavam referral_attributions como
-- 'active' e setavam venues.referred_by. A filial levava a comissão de 5%.
--
-- same_owner entra no CHECK de block_reason. O ramo jogador x casa já
-- devolvia player_owns_venue pelo CPF; sem CPF a conta dona passava. Agora
-- a comparação é também subject_user = venues.owner_id, com o mesmo motivo.
-- Percentuais, níveis, desconto, pontos, parcelamento e CAC não mudam.

do $$
declare
  v_name text;
  v_count integer;
begin
  select count(*), min(con.conname)
    into v_count, v_name
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class rel on rel.oid = con.conrelid
  join pg_catalog.pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'referral_attributions'
    and con.contype = 'c'
    and pg_catalog.pg_get_constraintdef(con.oid) like '%block_reason%';
  if v_count is distinct from 1 then
    raise exception 'esperava uma constraint de block_reason, achei %', v_count;
  end if;
  execute format(
    'alter table public.referral_attributions drop constraint %I',
    v_name
  );
end
$$;

alter table public.referral_attributions
  add constraint referral_attributions_block_reason_check
  check (
    block_reason is null
    or block_reason in (
      'shared_cpf',
      'shared_phone',
      'shared_card',
      'shared_document',
      'player_owns_venue',
      'same_owner'
    )
  );

create or replace function private.identity_conflict(
  p_user_a uuid,
  p_user_b uuid,
  p_venue_a uuid,
  p_venue_b uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cpf_a text;
  v_cpf_b text;
  v_phone_a text;
  v_phone_b text;
  v_doc_a text;
  v_doc_b text;
  v_owner uuid;
  v_owner_b uuid;
  v_owner_cpf text;
begin
  if p_user_a is not null then
    select cpf, phone into v_cpf_a, v_phone_a
    from public.profiles where id = p_user_a;
  end if;
  if p_user_b is not null and p_user_b is distinct from p_user_a then
    select cpf, phone into v_cpf_b, v_phone_b
    from public.profiles where id = p_user_b;
    if v_cpf_a is not null and v_cpf_a = v_cpf_b then
      return 'shared_cpf';
    end if;
    if v_phone_a is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
    if exists (
      select 1
      from public.saved_cards a
      join public.saved_cards b
        on a.credit_card_token = b.credit_card_token
      where a.user_id = p_user_a
        and b.user_id = p_user_b
    ) then
      return 'shared_card';
    end if;
  end if;

  if p_user_a is not null and p_venue_a is not null then
    select document_number, phone, owner_id
      into v_doc_a, v_phone_b, v_owner
    from public.venues
    where id = p_venue_a;
    -- A conta é a dona da casa, mesmo com CPF vazio ou diferente do CNPJ.
    if v_owner is not null and v_owner = p_user_a then
      return 'player_owns_venue';
    end if;
    if v_cpf_a is not null and v_doc_a is not null and v_cpf_a = v_doc_a then
      return 'player_owns_venue';
    end if;
    if v_owner is not null then
      select cpf into v_owner_cpf from public.profiles where id = v_owner;
      if v_cpf_a is not null and v_cpf_a = v_owner_cpf then
        return 'player_owns_venue';
      end if;
    end if;
    if v_phone_a is not null and v_phone_b is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
  end if;

  if p_venue_a is not null and p_venue_b is not null and p_venue_a <> p_venue_b then
    select a.document_number, a.phone, a.owner_id,
           b.document_number, b.phone, b.owner_id
      into v_doc_a, v_phone_a, v_owner,
           v_doc_b, v_phone_b, v_owner_b
    from public.venues a
    join public.venues b on b.id = p_venue_b
    where a.id = p_venue_a;
    if v_doc_a is not null and v_doc_a = v_doc_b then
      return 'shared_document';
    end if;
    if v_phone_a is not null and v_phone_a = v_phone_b then
      return 'shared_phone';
    end if;
    if v_owner is not null and v_owner = v_owner_b then
      return 'same_owner';
    end if;
  end if;
  return null;
end;
$$;

revoke all on function private.identity_conflict(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
