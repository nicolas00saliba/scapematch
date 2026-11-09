-- Todas as ordens de estorno, clawback e replay para 2 e 3 créditos.
-- O líquido esperado é calculado por um modelo local, sem copiar o livro.

\set ON_ERROR_STOP on

\set FULL_PERMUTATIONS ''
\getenv FULL_PERMUTATIONS FULL_PERMUTATIONS
select set_config(
  'scapematch.full_permutations',
  coalesce(nullif(:'FULL_PERMUTATIONS', ''), ''),
  false
);

begin;

select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, email, raw_user_meta_data)
values (
  'ee100000-0000-4000-8000-000000000001',
  'permuta@example.com',
  '{"display_name":"Permuta"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ee200000-0000-4000-8000-000000000001',
  'ee100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Permuta', 'Centro', 'Rua da Ordem', '9', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '45997418000153', '4130000199', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ee300000-0000-4000-8000-000000000001',
  'ee200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ee310000-0000-4000-8000-000000000001',
  'ee300000-0000-4000-8000-000000000001',
  '2027-10-01 18:00:00+00', 'partner_grid'
);

create or replace function pg_temp.permute(items text[])
returns setof text[]
language plpgsql
as $fn$
declare
  i integer;
  tail text[];
begin
  if coalesce(cardinality(items), 0) = 0 then
    return next '{}'::text[];
    return;
  end if;
  for i in 1..cardinality(items) loop
    for tail in
      select pg_temp.permute(
        items[1:i - 1] || items[i + 1:cardinality(items)]
      )
    loop
      return next array[items[i]] || tail;
    end loop;
  end loop;
end;
$fn$;

create or replace function pg_temp.slot_uuid(p_prefix text, p_n integer)
returns uuid
language sql
immutable
as $fn$
  select (
    p_prefix || pg_catalog.lpad(p_n::text, 4, '0')
    || '-0000-4000-8000-000000000001'
  )::uuid;
$fn$;

create temp table perm_seq (case_key text, seq text[]);

insert into perm_seq (case_key, seq)
with recursive cases as (
  select *
  from (values
    ('2t', array['C', 'K', 'O1', 'O2', 'U']::text[]),
    ('2f', array['C', 'K', 'O1', 'O2', 'U1', 'U2']::text[]),
    ('3t', array['C', 'K', 'O1', 'O2', 'O3', 'U']::text[]),
    ('3f', array['C', 'K', 'O1', 'O2', 'O3', 'U1', 'U2', 'U3']::text[])
  ) as listed(case_key, all_items)
),
walk as (
  select case_key, array[item] as seq, array_remove(all_items, item) as rest
  from cases, lateral unnest(all_items) as item
  union all
  select w.case_key, w.seq || item, array_remove(w.rest, item)
  from walk w, lateral unnest(w.rest) as item
)
select case_key, seq from walk where cardinality(rest) = 0;

do $body$
declare
  v_venue uuid := 'ee200000-0000-4000-8000-000000000001';
  v_room uuid := 'ee300000-0000-4000-8000-000000000001';
  v_session uuid := 'ee310000-0000-4000-8000-000000000001';
  v_user uuid := 'ee100000-0000-4000-8000-000000000001';
  v_amounts integer[] := array[200, 150, 100];
  v_case record;
  v_seq text[];
  v_event text;
  v_n integer;
  v_i integer;
  v_same boolean;
  v_count integer := 0;
  v_full boolean := coalesce(
    current_setting('scapematch.full_permutations', true), ''
  ) = '1';
  v_house integer;
  v_open_claw integer;
  v_open_credit integer;
  v_origin_paid boolean[];
  v_consumer_paid boolean[];
  v_claw_open boolean[];
  v_collected boolean[];
  v_neutral boolean[];
  v_applied boolean[];
  v_collector_paid boolean;
  v_model integer;
  v_open_model integer;
  v_credit_model integer;
  v_origins uuid[];
  v_consumers uuid[];
  v_groups uuid[];
  v_collector uuid;
  v_collector_group uuid;
  v_charge uuid;
begin
  for v_case in
    select * from (values
      (2, true),
      (2, false),
      (3, true),
      (3, false)
    ) as t(n, same)
  loop
    v_n := v_case.n;
    v_same := v_case.same;
    if v_n = 3 and not v_full then
      continue;
    end if;
    v_origins := '{}';
    v_consumers := '{}';
    v_groups := '{}';

    for v_i in 1..v_n loop
      v_charge := pg_temp.slot_uuid('ee41', v_case.n * 10 + (case when v_same then 0 else 5 end) + v_i);
      v_origins := v_origins || v_charge;
      v_groups := v_groups || pg_temp.slot_uuid('ee51', v_case.n * 10 + (case when v_same then 0 else 5 end) + v_i);
      insert into public.groups (
        id, city_id, venue_id, room_id, session_id, starts_at,
        total_spots, minimum_spots, price_cents, created_by
      ) values (
        v_groups[v_i], 'curitiba', v_venue, v_room, v_session,
        timestamptz '2027-11-01 18:00:00+00' + make_interval(days => v_case.n * 40 + v_i),
        4, 2, 10000, v_user
      );
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type, status,
        idempotency_key, wallet_id, commission_bps, paid_at
      ) values (
        v_charge, v_groups[v_i], v_user, v_venue, 10000, 'PIX', 'paid',
        'idem-perm-o-' || v_charge::text, 'wal', 2500, now()
      );
      perform private.ledger_credit_charge(v_charge);
      insert into public.venue_referral_entries (
        venue_id, kind, amount_cents, program, settlement, source_charge_id,
        idempotency_key, available_at, applied_cents
      ) values (
        v_venue, 'accrual', v_amounts[v_i], 'b2c', 'released', v_charge,
        'idem-perm-c-' || v_charge::text,
        now() + make_interval(secs => v_i), 0
      );
    end loop;

    if v_same then
      v_charge := pg_temp.slot_uuid('ee61', v_case.n);
      v_consumers := array[v_charge];
      insert into public.groups (
        id, city_id, venue_id, room_id, session_id, starts_at,
        total_spots, minimum_spots, price_cents, created_by
      ) values (
        pg_temp.slot_uuid('ee71', v_case.n), 'curitiba', v_venue, v_room, v_session,
        timestamptz '2027-12-01 18:00:00+00' + make_interval(days => v_case.n),
        4, 2, 10000, v_user
      );
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type, status,
        idempotency_key, wallet_id, commission_bps, paid_at
      ) values (
        v_charge, pg_temp.slot_uuid('ee71', v_case.n), v_user, v_venue,
        10000, 'PIX', 'paid', 'idem-perm-u-' || v_charge::text, 'wal', 2500, now()
      );
      if private.apply_venue_credit(v_charge, v_venue, 10000) <> (
        select sum(v_amounts[g]) from generate_series(1, v_n) g
      ) then
        raise exception 'os creditos do mesmo consumidor nao entraram';
      end if;
      perform private.ledger_credit_charge(v_charge);
    else
      for v_i in 1..v_n loop
        v_charge := pg_temp.slot_uuid('ee62', v_case.n * 10 + v_i);
        v_consumers := v_consumers || v_charge;
        insert into public.groups (
          id, city_id, venue_id, room_id, session_id, starts_at,
          total_spots, minimum_spots, price_cents, created_by
        ) values (
          pg_temp.slot_uuid('ee72', v_case.n * 10 + v_i),
          'curitiba', v_venue, v_room, v_session,
          timestamptz '2027-12-10 18:00:00+00'
            + make_interval(days => v_case.n * 10 + v_i),
          4, 2, 10000, v_user
        );
        insert into public.payment_charges (
          id, group_id, user_id, venue_id, amount_cents, billing_type, status,
          idempotency_key, wallet_id, commission_bps, paid_at
        ) values (
          v_charge, pg_temp.slot_uuid('ee72', v_case.n * 10 + v_i),
          v_user, v_venue, 10000, 'PIX', 'paid',
          'idem-perm-u-' || v_charge::text, 'wal', 2500, now()
        );
        if private.apply_venue_credit(v_charge, v_venue, v_amounts[v_i])
          <> v_amounts[v_i]
        then
          raise exception 'o credito % nao entrou sozinho', v_i;
        end if;
        perform private.ledger_credit_charge(v_charge);
      end loop;
    end if;

    v_collector := pg_temp.slot_uuid('ee81', v_case.n * 10 + (case when v_same then 1 else 2 end));
    v_collector_group := pg_temp.slot_uuid('ee91', v_case.n * 10 + (case when v_same then 1 else 2 end));
    insert into public.groups (
      id, city_id, venue_id, room_id, session_id, starts_at,
      total_spots, minimum_spots, price_cents, created_by
    ) values (
      v_collector_group, 'curitiba', v_venue, v_room, v_session,
      timestamptz '2028-01-01 18:00:00+00' + make_interval(days => v_case.n + (case when v_same then 0 else 3 end)),
      4, 2, 10000, v_user
    );
    insert into public.payment_charges (
      id, group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, wallet_id, commission_bps, paid_at
    ) values (
      v_collector, v_collector_group, v_user, v_venue, 10000, 'PIX', 'paid',
      'idem-perm-c-' || v_collector::text, 'wal', 2500, now()
    );
    perform private.ledger_credit_charge(v_collector);

    for v_seq in
      select seq
      from perm_seq
      where case_key = v_n::text || case when v_same then 't' else 'f' end
    loop
      v_count := v_count + 1;
      v_origin_paid := array_fill(true, array[v_n]);
      v_consumer_paid := array_fill(true, array[v_n]);
      v_claw_open := array_fill(false, array[v_n]);
      v_collected := array_fill(false, array[v_n]);
      v_neutral := array_fill(false, array[v_n]);
      v_applied := array_fill(true, array[v_n]);
      v_collector_paid := true;
      v_model := 7500 * (v_n + (case when v_same then 1 else v_n end) + 1);
      for v_i in 1..v_n loop
        v_model := v_model + v_amounts[v_i];
      end loop;
      v_open_model := 0;
      v_credit_model := 0;

      begin
      foreach v_event in array v_seq loop
        if v_event = 'K' then
          perform private.apply_venue_clawback(v_collector, v_venue, 100000);
          perform private.ledger_credit_charge(v_collector);
          if v_collector_paid then
            for v_i in 1..v_n loop
              if v_claw_open[v_i] and not v_collected[v_i] and not v_neutral[v_i] then
                v_model := v_model - v_amounts[v_i];
                v_collected[v_i] := true;
                v_claw_open[v_i] := false;
                v_open_model := v_open_model - v_amounts[v_i];
              end if;
            end loop;
          end if;
        elsif v_event = 'C' then
          if v_collector_paid then
            update public.payment_charges
            set status = 'refunded', refunded_at = now()
            where id = v_collector;
            perform private.ledger_reverse_charge(v_collector);
            v_collector_paid := false;
            v_model := v_model - 7500;
            for v_i in 1..v_n loop
              if v_collected[v_i] and not v_neutral[v_i] then
                v_model := v_model + v_amounts[v_i];
                v_collected[v_i] := false;
                if v_consumer_paid[v_i] and not v_origin_paid[v_i] then
                  v_claw_open[v_i] := true;
                  v_open_model := v_open_model + v_amounts[v_i];
                end if;
              end if;
            end loop;
          end if;
        elsif left(v_event, 1) = 'U' then
          for v_i in 1..v_n loop
            if v_same or v_event = 'U' || v_i::text then
              if v_consumer_paid[v_i] then
                v_charge := case when v_same then v_consumers[1] else v_consumers[v_i] end;
                if v_same and v_i = 1 or not v_same then
                  update public.payment_charges
                  set status = 'refunded', refunded_at = now()
                  where id = v_charge and status <> 'refunded';
                  perform private.ledger_reverse_charge(v_charge);
                  perform private.reverse_referral_rewards(v_charge);
                end if;
                v_consumer_paid[v_i] := false;
                if not v_same or v_i = 1 then
                  v_model := v_model - 7500;
                end if;
                if v_applied[v_i] then
                  v_model := v_model - v_amounts[v_i];
                  v_applied[v_i] := false;
                end if;
                if v_origin_paid[v_i] then
                  v_credit_model := v_credit_model + v_amounts[v_i];
                elsif v_collected[v_i] and not v_neutral[v_i] then
                  v_model := v_model + v_amounts[v_i];
                  v_neutral[v_i] := true;
                else
                  if v_claw_open[v_i] then
                    v_open_model := v_open_model - v_amounts[v_i];
                  end if;
                  v_claw_open[v_i] := false;
                end if;
              end if;
            end if;
          end loop;
        elsif left(v_event, 1) = 'O' then
          v_i := right(v_event, 1)::integer;
          if v_origin_paid[v_i] then
            update public.payment_charges
            set status = 'refunded', refunded_at = now()
            where id = v_origins[v_i];
            perform private.ledger_reverse_charge(v_origins[v_i]);
            perform private.reverse_referral_rewards(v_origins[v_i]);
            v_origin_paid[v_i] := false;
            v_model := v_model - 7500;
            if v_consumer_paid[v_i] and v_applied[v_i] then
              v_claw_open[v_i] := true;
              v_open_model := v_open_model + v_amounts[v_i];
            elsif not v_consumer_paid[v_i] then
              v_credit_model := v_credit_model - v_amounts[v_i];
            end if;
          end if;
        end if;
      end loop;

      select coalesce(sum(
        case when direction = 'credit' then amount_cents else -amount_cents end
      ), 0)
      into v_house
      from public.ledger_entries
      where venue_id = v_venue and account = 'house';

      select coalesce(sum(amount_cents - applied_cents), 0)
      into v_open_claw
      from public.venue_credit_clawbacks
      where venue_id = v_venue
        and voided_at is null
        and neutralized_at is null;

      select coalesce(sum(e.amount_cents - e.applied_cents), 0)
      into v_open_credit
      from public.venue_referral_entries e
      where e.venue_id = v_venue
        and e.kind = 'accrual'
        and e.settlement = 'released'
        and not exists (
          select 1 from public.venue_referral_entries r
          where r.relates_to = e.id and r.kind = 'reversal'
        );

      if v_house <> v_model
        or v_open_claw <> v_open_model
        or v_open_credit <> v_credit_model
      then
        raise exception
          'ordem % casa %/% aberto %/% credito %/%',
          v_seq, v_house, v_model, v_open_claw, v_open_model,
          v_open_credit, v_credit_model;
      end if;

      foreach v_event in array v_seq loop
        if v_event = 'C' then
          perform private.ledger_reverse_charge(v_collector);
        elsif left(v_event, 1) = 'U' then
          v_charge := case
            when v_same then v_consumers[1]
            else v_consumers[right(v_event, 1)::integer]
          end;
          perform private.ledger_reverse_charge(v_charge);
          perform private.reverse_referral_rewards(v_charge);
        elsif left(v_event, 1) = 'O' then
          perform private.ledger_reverse_charge(v_origins[right(v_event, 1)::integer]);
          perform private.reverse_referral_rewards(v_origins[right(v_event, 1)::integer]);
        end if;
      end loop;

      select coalesce(sum(
        case when direction = 'credit' then amount_cents else -amount_cents end
      ), 0)
      into v_house
      from public.ledger_entries
      where venue_id = v_venue and account = 'house';
      if v_house <> v_model then
        raise exception 'replay mudou a casa na ordem %: % / %', v_seq, v_house, v_model;
      end if;
      if v_count % 5000 = 0 then
        raise notice 'ordens conferidas %', v_count;
      end if;
      raise exception 'perm_done' using errcode = 'P0004';
      exception
        when sqlstate 'P0004' then
          null;
      end;
    end loop;

    -- Desfaz os dados deste caso antes do próximo, senão os créditos se acumulam.
    delete from public.ledger_entries where venue_id = v_venue;
    delete from public.venue_credit_clawbacks where venue_id = v_venue;
    delete from public.venue_credit_applications
    where entry_id in (
      select id from public.venue_referral_entries where venue_id = v_venue
    );
    delete from public.venue_referral_entries where venue_id = v_venue;
    delete from public.payment_charges where venue_id = v_venue;
    delete from public.groups where venue_id = v_venue;
  end loop;

  if v_count <> (case when v_full then 120 + 720 + 720 + 40320 else 120 + 720 end) then
    raise exception 'a matriz de creditos nao enumerou %', v_count;
  end if;
  raise notice 'permutacoes de credito conferidas: %', v_count;
end;
$body$;

rollback;
