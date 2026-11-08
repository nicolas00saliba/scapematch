-- Antifraude do pagador. Não exige que o CPF de quem pagou seja o da conta.
-- Três travas, todas na linha de referral_program_settings:
--   block_self_payer: o pagador é o próprio indicador
--   payer_referred_account_cap: um pagador gera recompensa para no máximo N contas
--   same_device_review_threshold: contas do mesmo indicador e do mesmo aparelho
--     ficam em_revisao
-- O cashback não entra nessas travas.
-- O Asaas não devolve fingerprint de cartão. O token é de um cliente só.
-- A chave do cartão é bandeira + 4 finais. O documento vira hash SHA-256.
-- Não guarda o número. Não foi aplicado no projeto remoto.

alter table public.referral_program_settings
  add column block_self_payer boolean not null default true,
  add column payer_referred_account_cap integer not null default 3
    check (payer_referred_account_cap >= 0),
  add column same_device_review_threshold integer not null default 2
    check (same_device_review_threshold >= 0);

comment on column public.referral_program_settings.payer_referred_account_cap is
  'Contas indicadas distintas que um mesmo pagador pode premiar. 0 desliga.';

comment on column public.referral_program_settings.same_device_review_threshold is
  'Contas do mesmo indicador criadas no mesmo aparelho a partir deste número ficam em revisão. 0 desliga.';

alter table public.payment_charges
  add column payer_document_hash text,
  add column payer_card_key text;

alter table public.payment_charges
  add constraint payment_charges_payer_document_hash
  check (
    payer_document_hash is null
    or payer_document_hash ~ '^[0-9a-f]{64}$'
  );

alter table public.payment_charges
  add constraint payment_charges_payer_card_key
  check (
    payer_card_key is null
    or payer_card_key ~ '^[a-z0-9]+:[0-9]{4}$'
  );

comment on column public.payment_charges.payer_document_hash is
  'SHA-256 dos dígitos do documento de quem pagou. Não é o documento.';

comment on column public.payment_charges.payer_card_key is
  'Bandeira e 4 finais que o Asaas devolve. O token não serve entre clientes.';

alter table public.profiles
  add column device_install_id text;

alter table public.profiles
  add constraint profiles_device_install_id
  check (
    device_install_id is null
    or device_install_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

comment on column public.profiles.device_install_id is
  'Identificador da instalação gerado no app. Sem dado pessoal.';

alter table public.venues
  add column device_install_id text;

alter table public.venues
  add constraint venues_device_install_id
  check (
    device_install_id is null
    or device_install_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

alter table public.saved_cards
  add column holder_document_hash text,
  add column card_key text;

alter table public.saved_cards
  add constraint saved_cards_holder_document_hash
  check (
    holder_document_hash is null
    or holder_document_hash ~ '^[0-9a-f]{64}$'
  );

alter table public.saved_cards
  add constraint saved_cards_card_key
  check (
    card_key is null
    or card_key ~ '^[a-z0-9]+:[0-9]{4}$'
  );

create index scape_point_in_review
  on public.scape_point_entries (created_at)
  where review_status = 'em_revisao' and kind = 'accrual';

create index venue_referral_in_review
  on public.venue_referral_entries (created_at)
  where review_status = 'em_revisao' and kind = 'accrual';

create table public.payer_reward_subjects (
  id uuid primary key default gen_random_uuid(),
  payer_document_hash text,
  payer_card_key text,
  subject_user_id uuid,
  subject_venue_id uuid,
  created_at timestamptz not null default pg_catalog.now(),
  check (payer_document_hash is not null or payer_card_key is not null),
  check (num_nonnulls(subject_user_id, subject_venue_id) = 1),
  check (
    payer_document_hash is null
    or payer_document_hash ~ '^[0-9a-f]{64}$'
  ),
  check (
    payer_card_key is null
    or payer_card_key ~ '^[a-z0-9]+:[0-9]{4}$'
  )
);

create unique index payer_reward_user_doc
  on public.payer_reward_subjects (payer_document_hash, subject_user_id)
  where payer_document_hash is not null and subject_user_id is not null;

create unique index payer_reward_user_card
  on public.payer_reward_subjects (payer_card_key, subject_user_id)
  where payer_card_key is not null and subject_user_id is not null;

create unique index payer_reward_venue_doc
  on public.payer_reward_subjects (payer_document_hash, subject_venue_id)
  where payer_document_hash is not null and subject_venue_id is not null;

create unique index payer_reward_venue_card
  on public.payer_reward_subjects (payer_card_key, subject_venue_id)
  where payer_card_key is not null and subject_venue_id is not null;

alter table public.payer_reward_subjects enable row level security;

revoke all on table public.payer_reward_subjects
  from public, anon, authenticated, service_role;

create or replace function private.document_hash(p_raw text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_raw is null then null
    when pg_catalog.regexp_replace(p_raw, '\D', '', 'g') !~ '^[0-9]{11}$'
      and pg_catalog.regexp_replace(p_raw, '\D', '', 'g') !~ '^[0-9]{14}$'
      then null
    else pg_catalog.encode(
      extensions.digest(
        pg_catalog.convert_to(pg_catalog.regexp_replace(p_raw, '\D', '', 'g'), 'UTF8'),
        'sha256'
      ),
      'hex'
    )
  end;
$$;

create or replace function private.card_key(p_brand text, p_last4 text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_last4 is null or p_last4 !~ '^[0-9]{4}$' then null
    when p_brand is null or pg_catalog.btrim(p_brand) = '' then null
    else pg_catalog.lower(
      pg_catalog.regexp_replace(p_brand, '[^A-Za-z0-9]', '', 'g')
    ) || ':' || p_last4
  end;
$$;

create or replace function private.normalize_install_id(p_raw text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_raw is null then null
    when pg_catalog.lower(pg_catalog.btrim(p_raw))
      ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then pg_catalog.lower(pg_catalog.btrim(p_raw))
    else null
  end;
$$;

create or replace function private.payer_is_referrer(
  p_charge_id uuid,
  p_referrer_user uuid,
  p_referrer_venue uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_card text;
  v_block boolean;
begin
  select block_self_payer into v_block
  from public.referral_program_settings where id = 1;
  if v_block is not true then
    return false;
  end if;
  select payer_document_hash, payer_card_key into v_hash, v_card
  from public.payment_charges where id = p_charge_id;
  if v_hash is null and v_card is null then
    return false;
  end if;
  if p_referrer_user is not null then
    if v_hash is not null and v_hash = private.document_hash((
      select cpf from public.profiles where id = p_referrer_user
    )) then
      return true;
    end if;
    if v_card is not null and exists (
      select 1 from public.saved_cards s
      where s.user_id = p_referrer_user and s.card_key = v_card
    ) then
      return true;
    end if;
  end if;
  if p_referrer_venue is not null then
    if v_hash is not null and (
      v_hash = private.document_hash((
        select document_number from public.venues where id = p_referrer_venue
      ))
      or v_hash = private.document_hash((
        select p.cpf
        from public.venues v
        join public.profiles p on p.id = v.owner_id
        where v.id = p_referrer_venue
      ))
    ) then
      return true;
    end if;
    if v_card is not null and exists (
      select 1
      from public.venues v
      join public.saved_cards s on s.user_id = v.owner_id
      where v.id = p_referrer_venue and s.card_key = v_card
    ) then
      return true;
    end if;
  end if;
  return false;
end;
$$;

create or replace function private.payer_subject_known(
  p_hash text,
  p_card text,
  p_subject_user uuid,
  p_subject_venue uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.payer_reward_subjects s
    where (
      (p_hash is not null and s.payer_document_hash = p_hash)
      or (p_card is not null and s.payer_card_key = p_card)
    )
    and (
      (p_subject_user is not null and s.subject_user_id = p_subject_user)
      or (p_subject_venue is not null and s.subject_venue_id = p_subject_venue)
    )
  );
$$;

create or replace function private.payer_rewarded_accounts(
  p_hash text,
  p_card text
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(count(*), 0)::integer
  from (
    select 'u:' || s.subject_user_id::text as subject
    from public.payer_reward_subjects s
    where s.subject_user_id is not null
      and (
        (p_hash is not null and s.payer_document_hash = p_hash)
        or (p_card is not null and s.payer_card_key = p_card)
      )
    union
    select 'v:' || s.subject_venue_id::text
    from public.payer_reward_subjects s
    where s.subject_venue_id is not null
      and (
        (p_hash is not null and s.payer_document_hash = p_hash)
        or (p_card is not null and s.payer_card_key = p_card)
      )
  ) subjects;
$$;

create or replace function private.note_payer_reward_subject(
  p_charge_id uuid,
  p_subject_user uuid,
  p_subject_venue uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_card text;
begin
  select payer_document_hash, payer_card_key into v_hash, v_card
  from public.payment_charges where id = p_charge_id;
  if v_hash is not null then
    insert into public.payer_reward_subjects (
      payer_document_hash, subject_user_id, subject_venue_id
    ) values (v_hash, p_subject_user, p_subject_venue)
    on conflict do nothing;
  end if;
  if v_card is not null then
    insert into public.payer_reward_subjects (
      payer_card_key, subject_user_id, subject_venue_id
    ) values (v_card, p_subject_user, p_subject_venue)
    on conflict do nothing;
  end if;
end;
$$;

create or replace function private.withhold_referral(
  p_charge_id uuid,
  p_user_id uuid,
  p_reason text,
  p_program text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.referral_withholdings (
    payment_charge_id, user_id, reason, program
  ) values (
    p_charge_id, p_user_id, p_reason, p_program
  )
  on conflict (payment_charge_id, reason, program) do nothing;
end;
$$;

create or replace function private.subject_device(
  p_subject_user uuid,
  p_subject_venue uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_subject_user is not null then (
      select device_install_id from public.profiles where id = p_subject_user
    )
    else (
      select device_install_id from public.venues where id = p_subject_venue
    )
  end;
$$;

create or replace function private.device_cluster_size(
  p_subject_user uuid,
  p_subject_venue uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_attr public.referral_attributions%rowtype;
  v_device text;
  v_count integer;
begin
  select * into v_attr
  from public.referral_attributions
  where (p_subject_user is not null and subject_user_id = p_subject_user)
    or (p_subject_venue is not null and subject_venue_id = p_subject_venue)
  limit 1;
  if v_attr.id is null then
    return 0;
  end if;
  v_device := private.subject_device(p_subject_user, p_subject_venue);
  if v_device is null then
    return 0;
  end if;
  select count(*)::integer into v_count
  from public.referral_attributions a
  where a.status = 'active'
    and (
      (v_attr.referrer_user_id is not null and a.referrer_user_id = v_attr.referrer_user_id)
      or (v_attr.referrer_venue_id is not null and a.referrer_venue_id = v_attr.referrer_venue_id)
    )
    and private.subject_device(a.subject_user_id, a.subject_venue_id) = v_device;
  return coalesce(v_count, 0);
end;
$$;

create or replace function private.referral_review_status(
  p_subject_user uuid,
  p_subject_venue uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_threshold integer;
begin
  select same_device_review_threshold into v_threshold
  from public.referral_program_settings where id = 1;
  if v_threshold is null or v_threshold <= 0 then
    return null;
  end if;
  if private.device_cluster_size(p_subject_user, p_subject_venue) >= v_threshold then
    return 'em_revisao';
  end if;
  return null;
end;
$$;

create or replace function private.referral_reward_gate(
  p_charge_id uuid,
  p_program text,
  p_referrer_user uuid,
  p_referrer_venue uuid,
  p_subject_user uuid,
  p_subject_venue uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
  v_cap integer;
  v_review text;
begin
  select * into v_charge from public.payment_charges where id = p_charge_id;
  if private.payer_is_referrer(p_charge_id, p_referrer_user, p_referrer_venue) then
    perform private.withhold_referral(
      p_charge_id, v_charge.user_id, 'payer_is_referrer', p_program
    );
    return 'skip';
  end if;
  select payer_referred_account_cap into v_cap
  from public.referral_program_settings where id = 1;
  if coalesce(v_cap, 0) > 0
    and v_charge.payer_document_hash is null
    and v_charge.payer_card_key is null
  then
    null;
  elsif coalesce(v_cap, 0) > 0
    and not private.payer_subject_known(
      v_charge.payer_document_hash,
      v_charge.payer_card_key,
      p_subject_user,
      p_subject_venue
    )
    and private.payer_rewarded_accounts(
      v_charge.payer_document_hash,
      v_charge.payer_card_key
    ) >= v_cap
  then
    perform private.withhold_referral(
      p_charge_id, v_charge.user_id, 'payer_account_cap', p_program
    );
    return 'skip';
  end if;
  v_review := private.referral_review_status(p_subject_user, p_subject_venue);
  if v_review = 'em_revisao' then
    return 'em_revisao';
  end if;
  return 'post';
end;
$$;

create or replace function private.flag_same_device_rewards(
  p_subject_user uuid,
  p_subject_venue uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attr public.referral_attributions%rowtype;
  v_device text;
begin
  if private.referral_review_status(p_subject_user, p_subject_venue) is distinct from 'em_revisao' then
    return;
  end if;
  select * into v_attr
  from public.referral_attributions
  where (p_subject_user is not null and subject_user_id = p_subject_user)
    or (p_subject_venue is not null and subject_venue_id = p_subject_venue)
  limit 1;
  v_device := private.subject_device(p_subject_user, p_subject_venue);
  update public.scape_point_entries e
  set review_status = 'em_revisao'
  from public.payment_charges c
  where e.kind = 'accrual'
    and e.program in ('c2c', 'c2b')
    and e.review_status is null
    and e.source_charge_id = c.id
    and not exists (
      select 1 from public.scape_point_entries r
      where r.relates_to = e.id and r.kind in ('release', 'reversal')
    )
    and exists (
      select 1
      from public.referral_attributions a
      where a.status = 'active'
        and (
          (v_attr.referrer_user_id is not null and a.referrer_user_id = v_attr.referrer_user_id)
          or (v_attr.referrer_venue_id is not null and a.referrer_venue_id = v_attr.referrer_venue_id)
        )
        and private.subject_device(a.subject_user_id, a.subject_venue_id) = v_device
        and (
          (e.program = 'c2c' and a.subject_user_id = c.user_id)
          or (e.program = 'c2b' and a.subject_venue_id = c.venue_id)
        )
    );
  update public.venue_referral_entries e
  set review_status = 'em_revisao'
  from public.payment_charges c
  where e.kind = 'accrual'
    and e.program in ('b2c', 'b2b')
    and e.review_status is null
    and e.source_charge_id = c.id
    and not exists (
      select 1 from public.venue_referral_entries r
      where r.relates_to = e.id and r.kind = 'reversal'
    )
    and exists (
      select 1
      from public.referral_attributions a
      where a.status = 'active'
        and (
          (v_attr.referrer_user_id is not null and a.referrer_user_id = v_attr.referrer_user_id)
          or (v_attr.referrer_venue_id is not null and a.referrer_venue_id = v_attr.referrer_venue_id)
        )
        and private.subject_device(a.subject_user_id, a.subject_venue_id) = v_device
        and (
          (e.program = 'b2c' and a.subject_user_id = c.user_id)
          or (e.program = 'b2b' and a.subject_venue_id = c.venue_id)
        )
    );
end;
$$;

create or replace function private.venue_referral_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.ensure_venue_code(new.id);
  update public.venues v
  set device_install_id = p.device_install_id
  from public.profiles p
  where v.id = new.id
    and p.id = new.owner_id
    and v.device_install_id is null
    and p.device_install_id is not null;
  return new;
end;
$$;

create or replace function public.record_payer_identity(
  p_charge_id uuid,
  p_document_hash text,
  p_card_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_document_hash is not null and p_document_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'hash invalido' using errcode = '22023';
  end if;
  if p_card_key is not null and p_card_key !~ '^[a-z0-9]+:[0-9]{4}$' then
    raise exception 'cartao invalido' using errcode = '22023';
  end if;
  update public.payment_charges
  set payer_document_hash = coalesce(payer_document_hash, p_document_hash),
      payer_card_key = coalesce(payer_card_key, p_card_key)
  where id = p_charge_id;
  if not found then
    raise exception 'charge_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.copy_saved_card_payer(
  p_charge_id uuid,
  p_user_id uuid,
  p_card_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_card text;
begin
  select holder_document_hash, card_key into v_hash, v_card
  from public.saved_cards
  where id = p_card_id and user_id = p_user_id;
  if not found then
    return;
  end if;
  perform public.record_payer_identity(p_charge_id, v_hash, v_card);
end;
$$;

create or replace function public.mark_saved_card_payer_key(
  p_card_id uuid,
  p_user_id uuid,
  p_document_hash text,
  p_card_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_document_hash is not null and p_document_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'hash invalido' using errcode = '22023';
  end if;
  if p_card_key is not null and p_card_key !~ '^[a-z0-9]+:[0-9]{4}$' then
    raise exception 'cartao invalido' using errcode = '22023';
  end if;
  update public.saved_cards
  set holder_document_hash = coalesce(holder_document_hash, p_document_hash),
      card_key = coalesce(card_key, p_card_key)
  where id = p_card_id
    and user_id = p_user_id;
  if not found then
    raise exception 'cartão não encontrado' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.admin_referral_reviews()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  return coalesce((
    select pg_catalog.jsonb_agg(row_to_json(s) order by s.created_at)
    from (
      select
        e.id,
        'points'::text as entry_kind,
        e.program,
        e.points,
        e.amount_cents,
        e.created_at
      from public.scape_point_entries e
      where e.kind = 'accrual' and e.review_status = 'em_revisao'
      union all
      select
        e.id,
        'venue'::text,
        e.program,
        null::integer,
        e.amount_cents,
        e.created_at
      from public.venue_referral_entries e
      where e.kind = 'accrual' and e.review_status = 'em_revisao'
    ) s
  ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_decide_referral_review(
  p_entry_id uuid,
  p_entry_kind text,
  p_decision text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_points integer;
  v_cents integer;
  v_user uuid;
  v_program text;
  v_charge uuid;
  v_available timestamptz;
  v_venue uuid;
begin
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'reject') or p_entry_kind not in ('points', 'venue') then
    raise exception 'decisao invalida' using errcode = '22023';
  end if;
  if p_entry_kind = 'points' then
    select user_id, points, amount_cents, program, source_charge_id, available_at
      into v_user, v_points, v_cents, v_program, v_charge, v_available
    from public.scape_point_entries
    where id = p_entry_id
      and kind = 'accrual'
      and review_status = 'em_revisao';
    if not found then
      raise exception 'revisao nao encontrada' using errcode = 'P0002';
    end if;
    if p_decision = 'reject' then
      update public.scape_point_entries
      set review_status = 'rejected'
      where id = p_entry_id;
      insert into public.scape_point_entries (
        user_id, kind, points, amount_cents, program,
        source_charge_id, payment_charge_id, relates_to, idempotency_key
      ) values (
        v_user, 'reversal', v_points, v_cents, v_program,
        v_charge, v_charge, p_entry_id, 'reversal:' || p_entry_id::text
      )
      on conflict (idempotency_key) do nothing;
      return;
    end if;
    update public.scape_point_entries
    set review_status = 'approved'
    where id = p_entry_id;
    if v_available <= pg_catalog.now() then
      insert into public.scape_point_entries (
        user_id, kind, points, amount_cents, program,
        source_charge_id, payment_charge_id, relates_to, idempotency_key
      ) values (
        v_user, 'release', v_points, v_cents, v_program,
        v_charge, v_charge, p_entry_id, 'release:' || p_entry_id::text
      )
      on conflict (idempotency_key) do nothing;
    end if;
    return;
  end if;
  select venue_id, amount_cents, program, source_charge_id
    into v_venue, v_cents, v_program, v_charge
  from public.venue_referral_entries
  where id = p_entry_id
    and kind = 'accrual'
    and review_status = 'em_revisao';
  if not found then
    raise exception 'revisao nao encontrada' using errcode = 'P0002';
  end if;
  if p_decision = 'reject' then
    update public.venue_referral_entries
    set review_status = 'rejected'
    where id = p_entry_id;
    insert into public.venue_referral_entries (
      venue_id, kind, amount_cents, program,
      source_charge_id, payment_charge_id, relates_to, idempotency_key
    ) values (
      v_venue, 'reversal', v_cents, v_program,
      v_charge, v_charge, p_entry_id, 'reversal:' || p_entry_id::text
    )
    on conflict (idempotency_key) do nothing;
    return;
  end if;
  update public.venue_referral_entries
  set review_status = 'approved'
  where id = p_entry_id;
end;
$$;

revoke all on function private.document_hash(text) from public, anon, authenticated;
revoke all on function private.card_key(text, text) from public, anon, authenticated;
revoke all on function private.normalize_install_id(text) from public, anon, authenticated;
revoke all on function private.payer_is_referrer(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.payer_subject_known(text, text, uuid, uuid) from public, anon, authenticated;
revoke all on function private.payer_rewarded_accounts(text, text) from public, anon, authenticated;
revoke all on function private.note_payer_reward_subject(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.withhold_referral(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function private.subject_device(uuid, uuid) from public, anon, authenticated;
revoke all on function private.device_cluster_size(uuid, uuid) from public, anon, authenticated;
revoke all on function private.referral_review_status(uuid, uuid) from public, anon, authenticated;
revoke all on function private.referral_reward_gate(uuid, text, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.flag_same_device_rewards(uuid, uuid) from public, anon, authenticated;

revoke all on function public.record_payer_identity(uuid, text, text) from public, anon, authenticated;
revoke all on function public.copy_saved_card_payer(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.mark_saved_card_payer_key(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_referral_reviews() from public, anon, authenticated;
revoke all on function public.admin_decide_referral_review(uuid, text, text) from public, anon, authenticated;

grant execute on function public.record_payer_identity(uuid, text, text) to service_role;
grant execute on function public.copy_saved_card_payer(uuid, uuid, uuid) to service_role;
grant execute on function public.mark_saved_card_payer_key(uuid, uuid, text, text) to service_role;
grant execute on function public.admin_referral_reviews() to authenticated;
grant execute on function public.admin_decide_referral_review(uuid, text, text) to authenticated;
