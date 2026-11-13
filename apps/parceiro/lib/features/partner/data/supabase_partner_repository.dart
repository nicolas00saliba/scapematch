import 'package:dominio/dominio.dart';
import 'package:scapematch/core/supabase/row_values.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/groups/data/supabase_group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_statement.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _cancelError(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('pgrst202') || lower.contains('could not find')) {
    return 'O cancelamento pela casa ainda não está aplicado no banco.';
  }
  if (lower.contains('too close')) {
    return 'Exclusão bloqueada (menos de 2 h)';
  }
  if (lower.contains('already cancelled')) {
    return 'Essa sessão já está cancelada.';
  }
  if (lower.contains('session started')) return 'A sessão já começou.';
  return 'Não foi possível cancelar a sessão.';
}

/// Painel da casa lido do banco. Saldo sai de `ledger_entries` da conta house.
class SupabasePartnerRepository implements PartnerDesk {
  SupabasePartnerRepository({required this.clock});

  final Clock clock;

  @override
  Future<PartnerSnapshot> load(
    String houseId, {
    VenueFiscalProfile fiscal = demoHouseFiscal,
  }) async {
    final venue = await scapeSupabase
        .from('venues')
        .select(partnerVenueColumns)
        .eq('id', houseId)
        .maybeSingle();
    if (venue == null) {
      throw StateError('Casa não encontrada.');
    }
    final city = await scapeSupabase
        .from('cities')
        .select('id, name, state_code, state_name')
        .eq('id', venue['city_id'])
        .maybeSingle();
    final roomRows = await scapeSupabase
        .from('rooms')
        .select(roomColumns)
        .eq('venue_id', houseId);
    final rooms = [for (final row in roomRows) roomFromRow(row)]
      ..sort((a, b) => a.name.compareTo(b.name));
    final roomIds = [for (final room in rooms) room.id];
    final sessionRows = roomIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await scapeSupabase
              .from('room_sessions')
              .select(sessionColumns)
              .inFilter('room_id', roomIds)
              .isFilter('cancelled_at', null);
    final slotsByRoom = <String, List<TimeSlot>>{};
    for (final row in sessionRows) {
      if (row['starts_at'] == null) continue;
      final slot = TimeSlot(
        id: row['id'] as String,
        roomId: row['room_id'] as String,
        startsAt: dateTimeOf(row['starts_at'])!,
      );
      slotsByRoom.putIfAbsent(slot.roomId, () => []).add(slot);
    }
    for (final slots in slotsByRoom.values) {
      slots.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    final groupRows = await scapeSupabase
        .from('groups_with_counts')
        .select(groupColumns)
        .eq('venue_id', houseId)
        .order('starts_at');
    final groupIds = [for (final row in groupRows) row['id'] as String];
    final memberRows = groupIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await scapeSupabase
              .from('group_members')
              .select(memberColumns)
              .inFilter('group_id', groupIds);
    final membersByGroup = <String, List<Map<String, dynamic>>>{};
    for (final row in memberRows) {
      membersByGroup.putIfAbsent(textOf(row['group_id']), () => []).add(row);
    }
    final venueRow = Map<String, dynamic>.from(venue);
    try {
      final ready = await scapeSupabase.rpc(
        'venue_finance_ready',
        params: {'p_venue_id': houseId},
      );
      venueRow['finance_ready'] = ready == true;
      if (ready != true) venueRow['receives_payments'] = false;
    } on Object {
      // Sem a função publicada, a faixa segue o que a vitrine já sabe.
    }
    final house = houseFromRow(venueRow);
    final local = scapeSupabase.auth.currentUser?.id;
    final groups = [
      for (final row in groupRows)
        _group(
          row,
          house: house,
          cityName: city == null ? house.cityId : textOf(city['name']),
          room: _room(rooms, textOf(row['room_id'])),
          members: membersByGroup[row['id']] ?? const [],
          localUserId: local,
        ),
    ];
    final ledger = await scapeSupabase
        .from('ledger_entries')
        .select(
          'id, venue_id, group_id, account, direction, kind, amount_cents, created_at',
        )
        .eq('venue_id', houseId)
        .order('created_at');
    final lines = _lines(ledger, groups);
    final absences = await scapeSupabase
        .from('absences')
        .select('group_id, user_id')
        .eq('venue_id', houseId);
    final counts = <String, int>{};
    final marks = <String>{};
    for (final row in absences) {
      final player = textOf(row['user_id']);
      marks.add('${row['group_id']}|$player');
      counts[player] = (counts[player] ?? 0) + 1;
    }
    const policy = _Standing();
    final standings = {
      for (final entry in counts.entries) entry.key: policy.of(entry.value),
    };
    var net = 0;
    var commission = 0;
    for (final line in lines) {
      net += line.netCents;
      commission += line.commissionCents;
    }
    final names = <String, String>{
      for (final group in groups)
        for (final person in group.participants)
          if (person.userId != null) person.userId!: person.displayName,
    };
    final storedFiscal = await _fiscalProfile(
      houseId,
      documentKind: textOf(venue['document_kind']),
    );
    final invoices = await _invoices(
      houseId: houseId,
      houseName: house.name,
      names: names,
    );
    return PartnerSnapshot(
      house: house,
      now: clock.now(),
      grossCents: net + commission,
      commissionCents: commission,
      netCents: net,
      reservedCents: _reserved(groups),
      lines: lines,
      moneyByGroup: {
        for (final line in lines)
          line.chargeId: GroupMoney(
            grossCents: line.grossCents,
            commissionCents: line.commissionCents,
            netCents: line.netCents,
          ),
      },
      groups: groups,
      rooms: rooms,
      slotsByRoom: slotsByRoom,
      absenceCounts: counts,
      absenceMarks: marks,
      attendanceMarks: await _attendanceMarks(houseId),
      standings: standings,
      invoices: invoices,
      fiscal: storedFiscal,
    );
  }

  Future<VenueFiscalProfile> _fiscalProfile(
    String houseId, {
    required String documentKind,
  }) async {
    final row = await scapeSupabase
        .from('venue_fiscal')
        .select(
          'municipal_inscription, service_code, service_name, iss_rate, mei',
        )
        .eq('venue_id', houseId)
        .maybeSingle();
    final kind = documentKind == 'cpf'
        ? FiscalDocumentKind.cpf
        : FiscalDocumentKind.cnpj;
    if (row == null) {
      return VenueFiscalProfile(documentKind: kind);
    }
    return VenueFiscalProfile(
      documentKind: kind,
      mei: row['mei'] == true,
      municipalInscription: textOf(row['municipal_inscription']),
      serviceCode: textOf(row['service_code']),
      serviceName: textOf(row['service_name']),
      issPercent: doubleOf(row['iss_rate']),
    );
  }

  Future<List<FiscalInvoiceView>> _invoices({
    required String houseId,
    required String houseName,
    required Map<String, String> names,
  }) async {
    final rows = await scapeSupabase
        .from('fiscal_invoices')
        .select(
          'id, payment_charge_id, group_id, venue_id, player_user_id, issuer, '
          'kind, status, skip_reason, number, pdf_url, xml_url, value_cents, '
          'iss_rate, service_code, description, created_at, issued_at',
        )
        .eq('venue_id', houseId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows) _invoice(row, houseName: houseName, names: names),
    ];
  }

  FiscalInvoiceView _invoice(
    Map<String, dynamic> row, {
    required String houseName,
    required Map<String, String> names,
  }) {
    final playerId = textOf(row['player_user_id']);
    final description = textOf(row['description']);
    final fromDescription = RegExp(r'para (.+)\.')
        .firstMatch(description)
        ?.group(1);
    final playerName = names[playerId] ?? fromDescription ?? 'Jogador';
    final issued =
        dateTimeOf(row['issued_at']) ?? dateTimeOf(row['created_at']);
    return FiscalInvoiceView(
      id: textOf(row['id']),
      chargeId: textOf(row['payment_charge_id']),
      groupId: textOf(row['group_id']),
      venueId: textOf(row['venue_id']),
      playerId: playerId,
      playerName: playerName,
      venueName: houseName,
      kind: textOf(row['kind']) == 'commission'
          ? FiscalInvoiceKind.commission
          : FiscalInvoiceKind.service,
      issuer: textOf(row['issuer']) == 'platform'
          ? FiscalIssuer.platform
          : FiscalIssuer.venue,
      status: _invoiceStatus(textOf(row['status'])),
      skipReason: switch (textOf(row['skip_reason'])) {
        'cpf' => FiscalSkipReason.cpf,
        'dados_fiscais' => FiscalSkipReason.dadosFiscais,
        _ => null,
      },
      valueCents: intOf(row['value_cents']),
      paidAt: issued ?? clock.now(),
      description: description,
      number: textOf(row['number']).isEmpty ? null : textOf(row['number']),
      pdfUrl: textOf(row['pdf_url']).isEmpty ? null : textOf(row['pdf_url']),
      xmlUrl: textOf(row['xml_url']).isEmpty ? null : textOf(row['xml_url']),
      issPercent: row['iss_rate'] == null ? null : doubleOf(row['iss_rate']),
      serviceCode: textOf(row['service_code']).isEmpty
          ? null
          : textOf(row['service_code']),
    );
  }

  FiscalInvoiceStatus _invoiceStatus(String raw) {
    return switch (raw) {
      'processing' => FiscalInvoiceStatus.processing,
      'authorized' => FiscalInvoiceStatus.authorized,
      'error' => FiscalInvoiceStatus.error,
      'canceled' => FiscalInvoiceStatus.canceled,
      'sem_emissao' => FiscalInvoiceStatus.semEmissao,
      'simulated' => FiscalInvoiceStatus.simulated,
      _ => FiscalInvoiceStatus.scheduled,
    };
  }

  @override
  Future<AbsenceMark> markAbsence({
    required String houseId,
    required String groupId,
    required String playerId,
  }) async {
    try {
      await scapeSupabase.rpc(
        'mark_absence',
        params: {'p_group_id': groupId, 'p_user_id': playerId},
      );
    } on PostgrestException catch (error) {
      final text = error.message.toLowerCase();
      if (text.contains('session not started')) {
        return const AbsenceRejected('A sessão ainda não começou.');
      }
      if (text.contains('group cancelled')) {
        return const AbsenceRejected('Grupo cancelado não registra falta.');
      }
      if (text.contains('not member')) {
        return const AbsenceRejected('Essa pessoa não está no grupo.');
      }
      return const AbsenceRejected('Não foi possível marcar a falta.');
    }
    final rows = await scapeSupabase
        .from('absences')
        .select('id')
        .eq('user_id', playerId);
    final count = rows.length;
    return AbsenceMarked(const _Standing().of(count), count);
  }

  Future<Set<String>> _attendanceMarks(String houseId) async {
    final rows = await scapeSupabase
        .from('session_checkins')
        .select('group_id, user_id')
        .eq('venue_id', houseId);
    return {
      for (final row in rows) '${row['group_id']}|${textOf(row['user_id'])}',
    };
  }

  @override
  Future<SessionCheckin> confirmAttendance({
    required String houseId,
    required String groupId,
    required String playerId,
  }) async {
    try {
      final raw = await scapeSupabase.rpc(
        'confirm_session_attendance',
        params: {'p_group_id': groupId, 'p_user_id': playerId},
      );
      final already = raw is Map && raw['already'] == true;
      return SessionCheckinRecorded(already: already);
    } on PostgrestException catch (error) {
      final text = error.message.toLowerCase();
      if (text.contains('session not started')) {
        return const SessionCheckinRejected('A sessão ainda não começou.');
      }
      if (text.contains('group cancelled')) {
        return const SessionCheckinRejected(
          'Grupo cancelado não confirma comparecimento.',
        );
      }
      if (text.contains('not member')) {
        return const SessionCheckinRejected('Essa pessoa não está no grupo.');
      }
      if (text.contains('reserva estornada') ||
          text.contains('reserva nao paga')) {
        return const SessionCheckinRejected(
          'Só confirma quem pagou e não foi estornado.',
        );
      }
      return const SessionCheckinRejected(
        'Não foi possível confirmar o comparecimento.',
      );
    }
  }

  @override
  Future<String?> updatePrice({
    required String roomId,
    required int priceCents,
  }) async {
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    await scapeSupabase
        .from('rooms')
        .update({'price_cents': priceCents})
        .eq('id', roomId);
    return null;
  }

  @override
  Future<TimeSlot> addSlot({
    required String roomId,
    required DateTime startsAt,
  }) async {
    final row = await scapeSupabase
        .from('room_sessions')
        .insert({
          'room_id': roomId,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'availability': 'partner_grid',
        })
        .select('id, room_id, starts_at')
        .single();
    return TimeSlot(
      id: row['id'] as String,
      roomId: row['room_id'] as String,
      startsAt: dateTimeOf(row['starts_at'])!,
    );
  }

  @override
  Future<String?> removeSlot({
    required String roomId,
    required String slotId,
  }) async {
    if (roomId.isEmpty) {
      return PartnerMessages.slotRemoveFailed;
    }
    try {
      await scapeSupabase.rpc(
        'remove_room_session',
        params: {'p_session_id': slotId},
      );
    } on PostgrestException catch (error) {
      final text = '${error.message} ${error.details ?? ''}';
      if (text.contains(PartnerMessages.slotHasReservation)) {
        return PartnerMessages.slotHasReservation;
      }
      return PartnerMessages.slotRemoveFailed;
    }
    return null;
  }

  @override
  Future<String?> openSession({
    required String houseId,
    required String roomId,
    required DateTime startsAt,
    required int priceCents,
  }) async {
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    if (!isHouseHour(startsAt)) {
      return 'Escolha 14:00, 16:30, 19:00 ou 21:00.';
    }
    final now = clock.now();
    if (!startsAt.isAfter(now)) return 'Esse horário já passou.';
    if (GroupRules.tooCloseToCreate(startsAt: startsAt, now: now)) {
      return 'Falta menos de 1 h. Escolha outro horário.';
    }
    final taken = await scapeSupabase
        .from('room_sessions')
        .select('id')
        .eq('room_id', roomId)
        .eq('starts_at', startsAt.toUtc().toIso8601String())
        .isFilter('cancelled_at', null);
    if (taken.isNotEmpty) return 'Essa sala já tem sessão nesse horário.';
    await addSlot(roomId: roomId, startsAt: startsAt);
    return null;
  }

  @override
  Future<String?> cancelSession({
    required String houseId,
    required String groupId,
    required String reason,
  }) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'cancel-house-group',
        body: {
          'group_id': groupId,
          'reason': reason.trim().isEmpty
              ? 'Cancelada pela casa'
              : reason.trim(),
        },
      );
      if (response.status != 200) {
        return _cancelError('${response.data}');
      }
      return null;
    } on FunctionException catch (error) {
      return _cancelError('${error.details ?? error.reasonPhrase ?? ''}');
    } on PostgrestException catch (error) {
      final text = '${error.code ?? ''} ${error.message}'.toLowerCase();
      return _cancelError(text);
    }
  }

  @override
  Future<String?> saveRoom({
    required String houseId,
    String? roomId,
    required String name,
    required Difficulty difficulty,
    required int durationMinutes,
    required int minimumPlayers,
    required int capacity,
    required int priceCents,
    required int accent,
    String theme = '',
    RoomCategory? category,
    List<RoomPicture>? pictures,
  }) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) return 'Dê um nome para a sala.';
    final story = theme.trim();
    if (story.isNotEmpty && (story.length < 8 || story.length > 180)) {
      return 'A história fica entre 8 e 180 caracteres.';
    }
    if (minimumPlayers < 2 || capacity < minimumPlayers || capacity > 12) {
      return 'O mínimo e o máximo precisam caber na sala.';
    }
    if (durationMinutes < 30 || durationMinutes > 240) {
      return 'A duração fica entre 30 e 240 minutos.';
    }
    if (priceCents < 100 || priceCents > 500000) {
      return 'Informe um preço entre R\$ 1,00 e R\$ 5.000,00.';
    }
    final payload = {
      'name': trimmed,
      'theme': story.isEmpty ? 'Sala aberta pela casa' : story,
      'category': (category ?? RoomCategory.mystery).name,
      'capacity': capacity,
      'minimum_players': minimumPlayers,
      'duration_minutes': durationMinutes,
      'difficulty': difficulty.name,
      'price_cents': priceCents,
      'accent': accent,
    };
    final String id;
    if (roomId == null) {
      final created = await scapeSupabase
          .from('rooms')
          .insert({...payload, 'venue_id': houseId, 'game_type': 'escape-room'})
          .select('id')
          .single();
      id = created['id'] as String;
    } else {
      await scapeSupabase.from('rooms').update(payload).eq('id', roomId);
      id = roomId;
    }
    final photos = pictures ?? const <RoomPicture>[];
    if (photos.isEmpty) return null;
    try {
      var order = 0;
      for (final picture in photos) {
        final path = '$houseId/$id/${picture.id}.jpg';
        await scapeSupabase.storage
            .from('room-photos')
            .uploadBinary(
              path,
              picture.source,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        await scapeSupabase.from('room_photos').insert({
          'room_id': id,
          'storage_path': path,
          'sort_order': order,
        });
        order += 1;
      }
    } on Object {
      return 'A sala foi salva, mas a foto não entrou.';
    }
    return null;
  }
}

class _Standing {
  const _Standing();

  AbsenceStanding of(int count) {
    if (count >= 3) return AbsenceStanding.blocked;
    if (count >= 1) return AbsenceStanding.warned;
    return AbsenceStanding.clear;
  }
}

EscapeRoom? _room(List<EscapeRoom> rooms, String id) {
  for (final room in rooms) {
    if (room.id == id) return room;
  }
  return null;
}

Group _group(
  Map<String, dynamic> row, {
  required EscapeHouse house,
  required String cityName,
  required EscapeRoom? room,
  required List<Map<String, dynamic>> members,
  required String? localUserId,
}) {
  return Group(
    id: row['id'] as String,
    cityId: house.cityId,
    cityName: cityName,
    houseId: house.id,
    houseName: house.name,
    neighborhood: house.neighborhood,
    roomId: textOf(row['room_id']),
    roomName: room?.name ?? 'Sala',
    roomTheme: room?.theme ?? '',
    roomCapacity: room?.capacity ?? intOf(row['total_spots'], fallback: 2),
    roomMinimum:
        room?.minimumPlayers ?? intOf(row['minimum_spots'], fallback: 2),
    durationMinutes: room?.durationMinutes ?? 60,
    difficulty: room?.difficulty ?? Difficulty.medium,
    slotId: textOf(row['session_id']),
    startsAt: dateTimeOf(row['starts_at']) ?? DateTime.now(),
    filledSpots: intOf(row['filled_spots']),
    totalSpots: intOf(row['total_spots'], fallback: 2),
    participants: [
      for (final member in members)
        participantFromRow(member, localUserId: localUserId),
    ],
    priceCents: intOf(row['price_cents']),
    gameType: room?.gameType ?? 'escape-room',
    note: textOf(row['note']),
    cancelledAt: dateTimeOf(row['cancelled_at']),
    cancelReason: textOf(row['cancel_reason']),
    minimumSpots: intOf(row['minimum_spots'], fallback: 2),
    confirmedAt: dateTimeOf(row['confirmed_at']),
    closesAt: dateTimeOf(row['closes_at']),
    cancelWindow: Duration(
      minutes: intOf(row['cancel_window_minutes'], fallback: 120),
    ),
    streetAddress: house.streetAddress,
    coverAsset: room == null ? '' : roomCategoryImage(room.category),
  );
}

int _reserved(List<Group> groups) {
  var sum = 0;
  for (final group in groups) {
    if (group.isCancelled) continue;
    for (final person in group.participants) {
      if (person.occupiesSeat && person.payment == PaymentStatus.reserved) {
        sum += group.priceCents;
      }
    }
  }
  return sum;
}

List<StatementLine> _lines(
  List<Map<String, dynamic>> rows,
  List<Group> groups,
) {
  final names = {for (final group in groups) group.id: group.roomName};
  final batches = <String, List<Map<String, dynamic>>>{};
  final order = <String>[];
  for (final row in rows) {
    final id = textOf(row['group_id']).isEmpty
        ? textOf(row['id'])
        : textOf(row['group_id']);
    batches
        .putIfAbsent(id, () {
          order.add(id);
          return <Map<String, dynamic>>[];
        })
        .add(row);
  }
  final lines = <StatementLine>[];
  for (final id in order.reversed) {
    var net = 0;
    var commission = 0;
    var refund = false;
    for (final row in batches[id]!) {
      final amount = intOf(row['amount_cents']);
      final sign = row['direction'] == 'debit' ? -1 : 1;
      final kind = textOf(row['kind']);
      if (kind == 'house_net' || kind == 'house_refund') net += sign * amount;
      if (kind == 'commission' || kind == 'commission_refund') {
        commission += sign * amount;
      }
      if (row['direction'] == 'debit') refund = true;
    }
    lines.add(
      StatementLine(
        chargeId: id,
        title: names[id] ?? 'Movimento',
        grossCents: net + commission,
        commissionCents: commission,
        netCents: net,
        refund: refund,
      ),
    );
  }
  return lines;
}
