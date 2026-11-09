-- Todas as ordens de estorno, devolução e replay do horário vazio.
-- Some o livro da casa com um modelo que não lê a implementação.

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

do $skip$
begin
  if to_regprocedure('private.apply_cashback_refund(uuid,uuid,integer)') is null then
    raise notice 'horario vazio ainda nao existe neste banco';
  end if;
end;
$skip$;

insert into auth.users (id, email, raw_user_meta_data)
values (
  'ef100000-0000-4000-8000-000000000001',
  'permuta-vazio@example.com',
  '{"display_name":"Vazio"}'
);

insert into public.venues (
  id, owner_id, city_id, name, neighborhood, street_address, address_number,
  postal_code, latitude, longitude, income_value, document_kind,
  document_number, phone, status
) values (
  'ef200000-0000-4000-8000-000000000001',
  'ef100000-0000-4000-8000-000000000001',
  'curitiba', 'Casa Vazio', 'Centro', 'Rua do Horario', '4', '80010000',
  -25.43, -49.27, 5000, 'cnpj', '45997418000153', '4130000177', 'approved'
);

insert into public.rooms (
  id, venue_id, name, theme, capacity, minimum_players, duration_minutes,
  difficulty, price_cents
) values (
  'ef300000-0000-4000-8000-000000000001',
  'ef200000-0000-4000-8000-000000000001',
  'Sala', '', 4, 2, 60, 'medium', 10000
);

insert into public.room_sessions (id, room_id, starts_at, availability)
values (
  'ef310000-0000-4000-8000-000000000001',
  'ef300000-0000-4000-8000-000000000001',
  '2027-04-01 18:00:00+00', 'partner_grid'
);

create temp table empty_perm (case_key text, seq text[]);

insert into empty_perm (case_key, seq)
with recursive cases as (
  select *
  from (values
    ('2t', array['P', 'R', 'S1', 'S2', 'B']::text[]),
    ('2f', array['P', 'R', 'S1', 'S2', 'B1', 'B2']::text[]),
    ('3t', array['P', 'R', 'S1', 'S2', 'S3', 'B']::text[]),
    ('3f', array['P', 'R', 'S1', 'S2', 'S3', 'B1', 'B2', 'B3']::text[])
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
  v_venue uuid := 'ef200000-0000-4000-8000-000000000001';
  v_room uuid := 'ef300000-0000-4000-8000-000000000001';
  v_session uuid := 'ef310000-0000-4000-8000-000000000001';
  v_user uuid := 'ef100000-0000-4000-8000-000000000001';
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
  v_sources uuid[];
  v_absorbers uuid[];
  v_payout uuid;
  v_source_paid boolean[];
  v_absorber_paid boolean[];
  v_applied boolean[];
  v_refund boolean[];
  v_refund_paid boolean[];
  v_refund_void boolean[];
  v_payout_paid boolean;
  v_model integer;
  v_open_model integer;
  v_house integer;
  v_open integer;
  v_charge uuid;
begin
  if to_regprocedure('private.apply_cashback_refund(uuid,uuid,integer)') is null then
    return;
  end if;

  for v_case in
    select * from (values (2, true), (2, false), (3, true), (3, false)) as t(n, same)
  loop
    v_n := v_case.n;
    v_same := v_case.same;
    if v_n = 3 and not v_full then
      continue;
    end if;
    v_sources := '{}';
    v_absorbers := '{}';
    for v_i in 1..v_n loop
      v_charge := (
        'ef4' || v_case.n::text || (case when v_same then '0' else '1' end)
        || lpad(v_i::text, 3, '0') || '-0000-4000-8000-000000000001'
      )::uuid;
      v_sources := v_sources || v_charge;
      insert into public.groups (
        id, city_id, venue_id, room_id, session_id, starts_at,
        total_spots, minimum_spots, price_cents, created_by
      ) values (
        (
          'ef5' || v_case.n::text || (case when v_same then '0' else '1' end)
          || lpad(v_i::text, 3, '0') || '-0000-4000-8000-000000000001'
        )::uuid,
        'curitiba', v_venue, v_room, v_session,
        timestamptz '2027-05-01 18:00:00+00' + make_interval(days => v_case.n * 20 + v_i),
        4, 2, 10000, v_user
      );
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type, status,
        idempotency_key, wallet_id, commission_bps, paid_at
      ) values (
        v_charge,
        (
          'ef5' || v_case.n::text || (case when v_same then '0' else '1' end)
          || lpad(v_i::text, 3, '0') || '-0000-4000-8000-000000000001'
        )::uuid,
        v_user, v_venue, 10000, 'PIX', 'paid',
        'idem-empty-s-' || v_charge::text, 'wal', 2500, now()
      );
      perform private.ledger_credit_charge(v_charge);
    end loop;

    if v_same then
      v_charge := ('ef60' || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid;
      v_absorbers := array[v_charge];
      insert into public.groups (
        id, city_id, venue_id, room_id, session_id, starts_at,
        total_spots, minimum_spots, price_cents, created_by
      ) values (
        ('ef70' || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid,
        'curitiba', v_venue, v_room, v_session,
        timestamptz '2027-07-01 18:00:00+00' + make_interval(days => v_n),
        4, 2, 10000, v_user
      );
      insert into public.payment_charges (
        id, group_id, user_id, venue_id, amount_cents, billing_type, status,
        idempotency_key, wallet_id, commission_bps, paid_at
      ) values (
        v_charge,
        ('ef70' || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid,
        v_user, v_venue, 10000, 'PIX', 'paid',
        'idem-empty-b-' || v_charge::text, 'wal', 2500, now()
      );
    else
      for v_i in 1..v_n loop
        v_charge := (
          'ef61' || v_n::text || lpad(v_i::text, 3, '0')
          || '-0000-4000-8000-000000000001'
        )::uuid;
        v_absorbers := v_absorbers || v_charge;
        insert into public.groups (
          id, city_id, venue_id, room_id, session_id, starts_at,
          total_spots, minimum_spots, price_cents, created_by
        ) values (
          (
            'ef71' || v_n::text || lpad(v_i::text, 3, '0')
            || '-0000-4000-8000-000000000001'
          )::uuid,
          'curitiba', v_venue, v_room, v_session,
          timestamptz '2027-07-10 18:00:00+00'
            + make_interval(days => v_n * 10 + v_i),
          4, 2, 10000, v_user
        );
        insert into public.payment_charges (
          id, group_id, user_id, venue_id, amount_cents, billing_type, status,
          idempotency_key, wallet_id, commission_bps, paid_at
        ) values (
          v_charge,
          (
            'ef71' || v_n::text || lpad(v_i::text, 3, '0')
            || '-0000-4000-8000-000000000001'
          )::uuid,
          v_user, v_venue, 10000, 'PIX', 'paid',
          'idem-empty-b-' || v_charge::text, 'wal', 2500, now()
        );
      end loop;
    end if;

    for v_i in 1..v_n loop
      v_charge := case when v_same then v_absorbers[1] else v_absorbers[v_i] end;
      insert into public.venue_cashback_debits (
        venue_id, source_charge_id, amount_cents, applied_cents, applied_charge_id
      ) values (
        v_venue, v_sources[v_i], v_amounts[v_i], v_amounts[v_i], v_charge
      );
    end loop;
    if v_same then
      perform private.ledger_credit_charge(v_absorbers[1]);
    else
      for v_i in 1..v_n loop
        perform private.ledger_credit_charge(v_absorbers[v_i]);
      end loop;
    end if;

    v_payout := ('ef8' || (case when v_same then '0' else '1' end) || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid;
    insert into public.groups (
      id, city_id, venue_id, room_id, session_id, starts_at,
      total_spots, minimum_spots, price_cents, created_by
    ) values (
      ('ef9' || (case when v_same then '0' else '1' end) || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid,
      'curitiba', v_venue, v_room, v_session,
      timestamptz '2027-08-01 18:00:00+00' + make_interval(days => v_n + (case when v_same then 0 else 4 end)),
      4, 2, 10000, v_user
    );
    insert into public.payment_charges (
      id, group_id, user_id, venue_id, amount_cents, billing_type, status,
      idempotency_key, wallet_id, commission_bps, paid_at
    ) values (
      v_payout,
      ('ef9' || (case when v_same then '0' else '1' end) || lpad(v_n::text, 4, '0') || '-0000-4000-8000-000000000001')::uuid,
      v_user, v_venue, 10000, 'PIX', 'paid',
      'idem-empty-p-' || v_payout::text, 'wal', 2500, now()
    );
    perform private.ledger_credit_charge(v_payout);

    for v_seq in
      select seq from empty_perm
      where case_key = v_n::text || case when v_same then 't' else 'f' end
    loop
      v_count := v_count + 1;
      v_source_paid := array_fill(true, array[v_n]);
      v_absorber_paid := array_fill(true, array[v_n]);
      v_applied := array_fill(true, array[v_n]);
      v_refund := array_fill(false, array[v_n]);
      v_refund_paid := array_fill(false, array[v_n]);
      v_refund_void := array_fill(false, array[v_n]);
      v_payout_paid := true;
      v_model := 7500 * (v_n + (case when v_same then 1 else v_n end) + 1);
      v_open_model := 0;
      for v_i in 1..v_n loop
        v_model := v_model - v_amounts[v_i];
      end loop;

      begin
      foreach v_event in array v_seq loop
        if v_event = 'P' then
          perform private.apply_cashback_refund(v_payout, v_venue, 100000);
          perform private.ledger_credit_charge(v_payout);
          if v_payout_paid then
            for v_i in 1..v_n loop
              if v_refund[v_i] and not v_refund_void[v_i] and not v_refund_paid[v_i] then
                v_refund_paid[v_i] := true;
                v_model := v_model + v_amounts[v_i];
                v_open_model := v_open_model - v_amounts[v_i];
              end if;
            end loop;
          end if;
        elsif v_event = 'R' then
          if v_payout_paid then
            update public.payment_charges
            set status = 'refunded', refunded_at = now()
            where id = v_payout;
            perform private.ledger_reverse_charge(v_payout);
            v_payout_paid := false;
            v_model := v_model - 7500;
            for v_i in 1..v_n loop
              if v_refund_paid[v_i] and not v_refund_void[v_i] then
                v_model := v_model - v_amounts[v_i];
                v_refund_paid[v_i] := false;
                v_open_model := v_open_model + v_amounts[v_i];
              end if;
            end loop;
          end if;
        elsif left(v_event, 1) = 'S' then
          v_i := right(v_event, 1)::integer;
          if v_source_paid[v_i] then
            update public.payment_charges
            set status = 'refunded', refunded_at = now()
            where id = v_sources[v_i];
            perform private.ledger_reverse_charge(v_sources[v_i]);
            perform private.reverse_referral_rewards(v_sources[v_i]);
            v_source_paid[v_i] := false;
            v_model := v_model - 7500;
            if v_applied[v_i] and not v_refund[v_i] then
              v_refund[v_i] := true;
              v_open_model := v_open_model + v_amounts[v_i];
            elsif not v_applied[v_i] then
              v_open_model := v_open_model - v_amounts[v_i];
            end if;
          end if;
        elsif left(v_event, 1) = 'B' then
          for v_i in 1..v_n loop
            if v_same or v_event = 'B' || v_i::text then
              if v_absorber_paid[v_i] then
                v_charge := case when v_same then v_absorbers[1] else v_absorbers[v_i] end;
                if v_same and v_i = 1 or not v_same then
                  update public.payment_charges
                  set status = 'refunded', refunded_at = now()
                  where id = v_charge and status <> 'refunded';
                  perform private.ledger_reverse_charge(v_charge);
                end if;
                v_absorber_paid[v_i] := false;
                if not v_same or v_i = 1 then
                  v_model := v_model - 7500;
                end if;
                if v_applied[v_i] and not (v_refund_paid[v_i] and not v_refund_void[v_i]) then
                  v_model := v_model + v_amounts[v_i];
                  if v_refund[v_i] and not v_refund_paid[v_i] then
                    v_refund_void[v_i] := true;
                    v_open_model := v_open_model - v_amounts[v_i];
                  elsif not v_refund[v_i] then
                    v_applied[v_i] := false;
                    v_open_model := v_open_model + v_amounts[v_i];
                  end if;
                end if;
              end if;
            end if;
          end loop;
        end if;
      end loop;

      select coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)
      into v_house
      from public.ledger_entries
      where venue_id = v_venue and account = 'house';
      select
        coalesce((
          select sum(f.amount_cents - f.applied_cents)
          from public.venue_cashback_refunds f
          join public.venue_cashback_debits d on d.id = f.debit_id
          where d.venue_id = v_venue and f.voided_at is null
        ), 0)
        + coalesce((
          select sum(amount_cents)
          from public.venue_cashback_debits
          where venue_id = v_venue
            and voided_at is null
            and applied_cents = 0
            and not exists (
              select 1 from public.venue_cashback_refunds f
              where f.debit_id = venue_cashback_debits.id and f.voided_at is null
            )
        ), 0)
      into v_open;
      if v_house <> v_model or v_open <> v_open_model then
        raise exception 'vazio % casa %/% aberto %/%', v_seq, v_house, v_model, v_open, v_open_model;
      end if;

      if v_payout_paid = false then
        perform private.ledger_reverse_charge(v_payout);
      end if;
      select coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)
      into v_house
      from public.ledger_entries
      where payment_charge_id = v_payout and account = 'house';
      if v_house <> (case when v_payout_paid then 7500 else 0 end) then
        raise exception 'cicatriz da devolucao na ordem %: %', v_seq, v_house;
      end if;

      raise exception 'perm_done' using errcode = 'P0004';
      exception
        when sqlstate 'P0004' then null;
      end;
    end loop;

    delete from public.ledger_entries where venue_id = v_venue;
    delete from public.venue_cashback_refunds
    where debit_id in (select id from public.venue_cashback_debits where venue_id = v_venue);
    delete from public.venue_cashback_debits where venue_id = v_venue;
    delete from public.payment_charges where venue_id = v_venue;
    delete from public.groups where venue_id = v_venue;
  end loop;

  if v_count <> (case when v_full then 120 + 720 + 720 + 40320 else 120 + 720 end) then
    raise exception 'a matriz do horario vazio nao enumerou %', v_count;
  end if;
  raise notice 'permutacoes de horario vazio conferidas: %', v_count;
end;
$body$;

do $$
declare
  v_venue uuid := 'ef200000-0000-4000-8000-000000000001';
  v_room uuid := 'ef300000-0000-4000-8000-000000000001';
  v_session uuid := 'ef310000-0000-4000-8000-000000000001';
  v_user uuid := 'ef100000-0000-4000-8000-000000000001';
  v_offset integer;
  v_refund integer;
begin
  if to_regprocedure('private.apply_empty_slot_debit(uuid,uuid,integer,boolean)') is null then
    return;
  end if;
  update public.referral_program_settings
  set first_booking_discount_bps = 0
  where id = 1;
  insert into public.groups (
    id, city_id, venue_id, room_id, session_id, starts_at,
    total_spots, minimum_spots, price_cents, created_by
  ) values
    ('ef400000-0000-4000-8000-000000000091', 'curitiba', v_venue, v_room, v_session, '2027-09-01 18:00:00+00', 4, 2, 10000, v_user),
    ('ef400000-0000-4000-8000-000000000092', 'curitiba', v_venue, v_room, v_session, '2027-09-02 18:00:00+00', 4, 2, 10000, v_user),
    ('ef400000-0000-4000-8000-000000000093', 'curitiba', v_venue, v_room, v_session, '2027-09-03 18:00:00+00', 4, 2, 10000, v_user);
  insert into public.group_members (
    group_id, user_id, display_name, is_creator, payment_status, refund_status, refund_reason
  ) values (
    'ef400000-0000-4000-8000-000000000092', v_user, 'Vazio', true, 'pending', 'none', 'none'
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps, paid_at
  ) values (
    'ef500000-0000-4000-8000-000000000091',
    'ef400000-0000-4000-8000-000000000091',
    v_user, v_venue, 10000, 'PIX', 'paid', 'idem-matriz-origem', 'wal', 2500, now()
  );
  insert into public.venue_cashback_debits (venue_id, source_charge_id, amount_cents)
  values (v_venue, 'ef500000-0000-4000-8000-000000000091', 4000);
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'ef500000-0000-4000-8000-000000000092',
    'ef400000-0000-4000-8000-000000000092',
    v_user, v_venue, 10000, 'PIX', 'creating', 'idem-matriz-reserva', 'wal', 2500
  );
  perform private.apply_share_adjustments('ef500000-0000-4000-8000-000000000092');
  perform private.reverse_referral_rewards('ef500000-0000-4000-8000-000000000091');
  perform private.apply_payment_transition(
    'ef500000-0000-4000-8000-000000000092', 'cancelled', false
  );
  insert into public.payment_charges (
    id, group_id, user_id, venue_id, amount_cents, billing_type, status,
    idempotency_key, wallet_id, commission_bps
  ) values (
    'ef500000-0000-4000-8000-000000000093',
    'ef400000-0000-4000-8000-000000000093',
    v_user, v_venue, 10000, 'PIX', 'creating', 'idem-matriz-seguinte', 'wal', 2500
  );
  perform private.apply_share_adjustments('ef500000-0000-4000-8000-000000000093');
  select empty_slot_offset_cents, cashback_refund_cents into v_offset, v_refund
  from public.payment_charges
  where id = 'ef500000-0000-4000-8000-000000000093';
  if v_offset <> 0 or v_refund <> 0 then
    raise exception 'matriz: estorno entre reserva e cancelamento cobrou % / %', v_offset, v_refund;
  end if;
  raise notice 'ordem reserva-estorno-cancelamento conferida';
end $$;

rollback;
