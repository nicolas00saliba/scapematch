-- Liquidação ao fechar, Pix apagado e horário inexistente.
-- Não aplica segredo novo e não afrouxa o RLS.
-- PostgREST traduz P0002 para HTTP 500. PT404 devolve 404.

create or replace function public.create_group(
  p_session_id uuid,
  p_total_spots integer,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_room public.rooms%rowtype;
  v_venue public.venues%rowtype;
  v_name text;
  v_note text;
  v_group_id uuid;
  v_closes timestamptz;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into v_session
  from public.room_sessions
  where id = p_session_id
  for update;
  if not found or v_session.cancelled_at is not null or v_session.starts_at is null then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;

  select * into v_room from public.rooms where id = v_session.room_id;
  if not found then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;
  select * into v_venue from public.venues where id = v_room.venue_id;
  if v_venue.status <> 'approved' then
    raise exception 'venue not approved' using errcode = '42501';
  end if;

  if p_total_spots < v_room.minimum_players then
    raise exception 'below room minimum' using errcode = '22023';
  end if;
  if p_total_spots > v_room.capacity then
    raise exception 'exceeds room capacity' using errcode = '22023';
  end if;
  if v_session.starts_at <= now() then
    raise exception 'session started' using errcode = 'P0001';
  end if;
  if v_session.starts_at - now() <= interval '1 hour' then
    raise exception 'too close to create' using errcode = '22023';
  end if;
  if private.user_has_overlap(v_user, v_session.starts_at, v_room.duration_minutes, null::uuid) then
    raise exception 'overlaps' using errcode = 'P0001';
  end if;

  v_name := private.profile_display_name(v_user);
  if v_name is null then
    raise exception 'display name required' using errcode = '22023';
  end if;
  v_note := trim(coalesce(p_note, ''));
  if char_length(v_note) > 280 then
    raise exception 'note too long' using errcode = '22023';
  end if;

  if v_session.starts_at - interval '24 hours' > now() then
    v_closes := v_session.starts_at - interval '24 hours';
  else
    v_closes := v_session.starts_at - interval '1 hour';
  end if;

  insert into public.groups (
    city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, price_mode,
    note, cancel_window_minutes, created_by, closes_at
  ) values (
    v_venue.city_id, v_venue.id, v_room.id, v_session.id, v_session.starts_at,
    p_total_spots, v_room.minimum_players, v_room.price_cents, v_room.price_mode,
    v_note, v_room.cancel_window_minutes, v_user, v_closes
  )
  returning id into v_group_id;

  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status
  ) values (
    v_group_id, v_user, v_name, true, 'pending'
  );

  return v_group_id;
exception
  when unique_violation then
    raise exception 'duplicate session' using errcode = '23505';
end;
$$;

create or replace function public.create_group_with_party(
  p_session_id uuid,
  p_open_spots integer,
  p_note text,
  p_companion_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_session public.room_sessions%rowtype;
  v_room public.rooms%rowtype;
  v_total integer;
  v_group_id uuid;
  v_person uuid;
  v_name text;
  v_count integer;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_open_spots is null or p_open_spots < 1 then
    raise exception 'open spot required' using errcode = '22023';
  end if;
  if p_companion_ids is null or cardinality(p_companion_ids) = 0 then
    raise exception 'party empty' using errcode = '22023';
  end if;
  if cardinality(p_companion_ids) > 11 then
    raise exception 'party too large' using errcode = '22023';
  end if;
  select count(distinct id) into v_count from unnest(p_companion_ids) as t(id);
  if v_count <> cardinality(p_companion_ids) or v_user = any (p_companion_ids) then
    raise exception 'invalid companion' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.friendships blocked
    where blocked.status = 'blocked'
      and blocked.requester_id = any (array[v_user] || p_companion_ids)
      and blocked.addressee_id = any (array[v_user] || p_companion_ids)
  ) then
    raise exception 'companion unavailable' using errcode = 'P0001';
  end if;

  select * into v_session from public.room_sessions where id = p_session_id;
  if not found then
    raise sqlstate 'PT404' using message = 'unknown session';
  end if;
  select * into v_room from public.rooms where id = v_session.room_id;

  foreach v_person in array p_companion_ids loop
    if not exists (
      select 1
      from public.crew_members leader
      join public.crews crew
        on crew.id = leader.crew_id
       and crew.deleted_at is null
      join public.crew_members mate
        on mate.crew_id = leader.crew_id
       and mate.user_id = v_person
       and mate.status = 'accepted'
      where leader.user_id = v_user
        and leader.status = 'accepted'
    ) then
      raise exception 'not crew mate' using errcode = '42501';
    end if;
    if private.user_has_overlap(
      v_person, v_session.starts_at, v_room.duration_minutes, null::uuid
    ) then
      raise exception 'companion unavailable' using errcode = 'P0001';
    end if;
  end loop;

  v_total := 1 + cardinality(p_companion_ids) + p_open_spots;
  v_group_id := public.create_group(p_session_id, v_total, p_note);

  foreach v_person in array p_companion_ids loop
    v_name := private.profile_display_name(v_person);
    if v_name is null then
      raise exception 'display name required' using errcode = '22023';
    end if;
    insert into public.group_members (
      group_id, user_id, display_name, is_creator, payment_status
    ) values (
      v_group_id, v_person, v_name, false, 'pending'
    );
    perform private.post_app_notice(
      v_person,
      'party_seat',
      'Vaga reservada',
      'Você entrou num grupo com a sua turma. Pague a sua parte. As outras vagas ficam abertas.',
      v_group_id,
      v_group_id::text || '-' || v_person::text
    );
  end loop;

  if private.group_filled_spots(v_group_id) >= v_total then
    raise exception 'party does not fit' using errcode = 'P0001';
  end if;
  return v_group_id;
end;
$$;


-- Captura única: a segunda liquidação do mesmo cartão não chama o Asaas
-- enquanto a trava estiver fresca. A coluna não entra no select do app.
alter table public.payment_charges
  add column if not exists capture_claimed_at timestamptz;

comment on column public.payment_charges.capture_claimed_at is
  'Trava curta da captura. Não é exposta ao app.';

revoke select (capture_claimed_at) on table public.payment_charges
  from public, anon, authenticated;

create or replace function private.claim_card_capture(p_charge_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
begin
  select * into v_charge
  from public.payment_charges
  where id = p_charge_id
  for update;
  if v_charge.id is null
    or v_charge.status <> 'authorized'
    or v_charge.billing_type <> 'CREDIT_CARD'
    or v_charge.provider_ref is null then
    return false;
  end if;
  if v_charge.capture_claimed_at is not null
    and v_charge.capture_claimed_at > pg_catalog.now() - interval '90 seconds' then
    return false;
  end if;
  update public.payment_charges
  set capture_claimed_at = pg_catalog.now()
  where id = v_charge.id;
  return true;
end;
$$;

create or replace function private.release_card_capture_claim(p_charge_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.payment_charges
  set capture_claimed_at = null
  where id = p_charge_id
    and status = 'authorized';
end;
$$;

-- Pix apagado no Asaas (deleted:true, status ainda pending) deixa de
-- prender o QR. A reserva nasce vencida para a próxima tentativa seguir.
create or replace function private.detach_gone_pix(
  p_charge_id uuid,
  p_provider_ref text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_charge public.payment_charges%rowtype;
begin
  update public.payment_charges
  set
    provider_ref = null,
    qr_code = null,
    qr_code_base64 = null,
    status = 'creating',
    reserved_at = pg_catalog.now() - interval '3 minutes',
    attempt_id = gen_random_uuid()
  where id = p_charge_id
    and provider_ref = p_provider_ref
    and billing_type = 'PIX'
    and status in ('pending', 'creating')
  returning * into v_charge;
  if v_charge.id is null then
    return null;
  end if;
  perform private.sync_charge_member(v_charge);
  return v_charge.attempt_id;
end;
$$;

revoke all on function private.claim_card_capture(uuid)
  from public, anon, authenticated;
revoke all on function private.release_card_capture_claim(uuid)
  from public, anon, authenticated;
revoke all on function private.detach_gone_pix(uuid, text)
  from public, anon, authenticated;

grant execute on function private.claim_card_capture(uuid) to service_role;
grant execute on function private.release_card_capture_claim(uuid) to service_role;
grant execute on function private.detach_gone_pix(uuid, text) to service_role;

create or replace function public.claim_card_capture(p_charge_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.claim_card_capture(p_charge_id);
$$;

create or replace function public.release_card_capture_claim(p_charge_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform private.release_card_capture_claim(p_charge_id);
end;
$$;

create or replace function public.detach_gone_pix(
  p_charge_id uuid,
  p_provider_ref text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.detach_gone_pix(p_charge_id, p_provider_ref);
$$;

revoke all on function public.claim_card_capture(uuid)
  from public, anon, authenticated;
revoke all on function public.release_card_capture_claim(uuid)
  from public, anon, authenticated;
revoke all on function public.detach_gone_pix(uuid, text)
  from public, anon, authenticated;

grant execute on function public.claim_card_capture(uuid) to service_role;
grant execute on function public.release_card_capture_claim(uuid) to service_role;
grant execute on function public.detach_gone_pix(uuid, text) to service_role;

-- Fechar o grupo avisa a rotina que já reconcilia, com o mesmo segredo
-- do vault. Sem o segredo, ou sem pg_net, o update do grupo segue.
-- Não grava service role nem chave nova.
create or replace function private.notify_settle_on_close()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if new.closed_at is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.closed_at is not distinct from new.closed_at then
    return new;
  end if;
  begin
    select btrim(s.decrypted_secret) into v_url
    from vault.decrypted_secrets s
    where s.name = 'reconcile_payments_url'
    limit 1;
    select btrim(s.decrypted_secret) into v_secret
    from vault.decrypted_secrets s
    where s.name = 'reconcile_secret'
    limit 1;
    if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
      return new;
    end if;
    perform net.http_post(
      url := v_url,
      body := pg_catalog.jsonb_build_object('settle_group_id', new.id),
      headers := pg_catalog.jsonb_build_object(
        'Content-Type', 'application/json',
        'x-reconcile-secret', v_secret
      ),
      timeout_milliseconds := 90000
    );
  exception
    when others then
      return new;
  end;
  return new;
end;
$$;

revoke all on function private.notify_settle_on_close()
  from public, anon, authenticated, service_role;

drop trigger if exists groups_settle_on_close on public.groups;
create trigger groups_settle_on_close
  after update of closed_at on public.groups
  for each row
  when (new.closed_at is not null and old.closed_at is distinct from new.closed_at)
  execute function private.notify_settle_on_close();
