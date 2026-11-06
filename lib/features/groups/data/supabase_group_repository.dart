import 'package:dominio/dominio.dart';
import 'package:scapematch/core/supabase/row_values.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/groups/data/group_rpc_errors.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const groupColumns =
    'id, city_id, venue_id, room_id, session_id, starts_at, total_spots, '
    'minimum_spots, price_cents, note, cancel_window_minutes, created_by, '
    'cancelled_at, cancel_reason, closed_at, closes_at, filled_spots, '
    'confirmed_count';

const memberColumns =
    'id, group_id, user_id, display_name, is_creator, attendance, '
    'payment_status, refund_status, refund_reason';

/// Grupos lidos de `groups_with_counts`. Escrita só pelas funções.
class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository({required this.client, required this.clock});

  final SupabaseClient client;
  final Clock clock;

  String? get _userId => client.auth.currentUser?.id;

  @override
  Future<List<Group>> listByCity(
    String cityId, {
    bool almostFullOnly = false,
  }) async {
    final rows = await client
        .from('groups_with_counts')
        .select(groupColumns)
        .eq('city_id', cityId)
        .isFilter('cancelled_at', null)
        .order('starts_at');
    final groups = await _hydrate(rows, hideWithoutPayout: true);
    final now = clock.now();
    return [
      for (final group in groups)
        if (!GroupRules.hasEnded(endsAt: group.endsAt, now: now) &&
            (!almostFullOnly || group.isAlmostFull))
          group,
    ];
  }

  @override
  Future<Group?> getById(String id) async {
    final row = await client
        .from('groups_with_counts')
        .select(groupColumns)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final groups = await _hydrate([row]);
    return groups.isEmpty ? null : groups.first;
  }

  @override
  Future<List<Group>> listForUser(String userId) async {
    final memberships = await client
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId);
    final ids = <String>{
      for (final row in memberships) row['group_id'] as String,
    };
    if (ids.isEmpty) return const [];
    final rows = await client
        .from('groups_with_counts')
        .select(groupColumns)
        .inFilter('id', ids.toList())
        .order('starts_at');
    return _hydrate(rows);
  }

  @override
  Future<JoinResult> join(
    String groupId, {
    required String participantUserId,
    required String participantName,
    bool markAsLocalUser = true,
  }) {
    return _joinCall(groupId);
  }

  @override
  Future<JoinResult> joinParty(
    String groupId, {
    required String leaderUserId,
    required String leaderName,
    required List<PartyCompanion> companions,
  }) async {
    if (companions.isEmpty) {
      return join(
        groupId,
        participantUserId: leaderUserId,
        participantName: leaderName,
      );
    }
    try {
      await client.rpc(
        'join_group_with_party',
        params: {
          'p_group_id': groupId,
          'p_companion_ids': [for (final person in companions) person.userId],
        },
      );
    } on PostgrestException catch (error) {
      return JoinFailure(
        partyFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) return const JoinFailure(JoinFailureReason.notFound);
    if (group.isFull && !group.isCancelled) {
      await _settleClosed(groupId);
    }
    return JoinSuccess(group);
  }

  @override
  Future<JoinResult> acceptWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  }) {
    return _joinCall(groupId, function: 'accept_waitlist');
  }

  Future<JoinResult> _joinCall(
    String groupId, {
    String function = 'join_group',
  }) async {
    try {
      await client.rpc(function, params: {'p_group_id': groupId});
    } on PostgrestException catch (error) {
      return JoinFailure(
        joinFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) return const JoinFailure(JoinFailureReason.notFound);
    if (group.isFull && !group.isCancelled) {
      await _settleClosed(groupId);
    }
    return JoinSuccess(group);
  }

  @override
  Future<String?> joinWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  }) async {
    try {
      await client.rpc('join_waitlist', params: {'p_group_id': groupId});
      return null;
    } on PostgrestException catch (error) {
      return waitlistError(rpcText(code: error.code, message: error.message));
    }
  }

  @override
  Future<void> declineWaitlist({
    required String groupId,
    required String userId,
  }) async {
    await client.rpc('decline_waitlist', params: {'p_group_id': groupId});
  }

  @override
  Future<PayShareResult> payShare(
    String groupId, {
    required String userId,
    required PaymentMethodKind kind,
    String? savedCardId,
  }) async {
    if (_userId == null || _userId != userId) {
      return const PayShareFailure(PayShareFailureReason.unavailable);
    }
    if (kind == PaymentMethodKind.card &&
        (savedCardId == null || savedCardId.isEmpty)) {
      return const PayShareFailure(PayShareFailureReason.unavailable);
    }
    try {
      await CardPaymentFlow(_invoke).charge(
        groupId: groupId,
        idempotencyKey: _chargeKey(groupId, userId),
        kind: kind,
        savedCardId: savedCardId,
      );
    } on Object {
      return const PayShareFailure(PayShareFailureReason.unavailable);
    }
    final group = await getById(groupId);
    if (group == null) {
      return const PayShareFailure(PayShareFailureReason.notFound);
    }
    return PayShareSuccess(group);
  }

  @override
  Future<PayShareResult> payWithNewCard(
    String groupId, {
    required String userId,
    required CardDraft card,
  }) async {
    if (_userId == null || _userId != userId) {
      return const PayShareFailure(PayShareFailureReason.unavailable);
    }
    try {
      await CardPaymentFlow(_invoke).payWithNewCard(
        card: card,
        groupId: groupId,
        idempotencyKey: _chargeKey(groupId, userId),
      );
    } on Object {
      return const PayShareFailure(PayShareFailureReason.unavailable);
    }
    final group = await getById(groupId);
    if (group == null) {
      return const PayShareFailure(PayShareFailureReason.notFound);
    }
    return PayShareSuccess(group);
  }

  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body,
  ) async {
    final response = await client.functions.invoke(name, body: body);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }

  String _chargeKey(String groupId, String userId) {
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'pay-$groupId-$userId-$stamp';
  }

  @override
  Future<CreateGroupResult> create(CreateGroupRequest request) async {
    try {
      final companions = request.companions;
      final id = companions.isEmpty
          ? await client.rpc(
              'create_group',
              params: {
                'p_session_id': request.slotId,
                'p_total_spots': 1 + request.extraSpots,
                'p_note': '',
              },
            )
          : await client.rpc(
              'create_group_with_party',
              params: {
                'p_session_id': request.slotId,
                'p_open_spots': request.extraSpots - companions.length,
                'p_note': '',
                'p_companion_ids': [
                  for (final person in companions) person.userId,
                ],
              },
            );
      final group = await getById(id.toString());
      if (group == null) {
        return const CreateGroupFailure(
          CreateGroupFailureReason.unknownSelection,
        );
      }
      return CreateGroupSuccess(group);
    } on PostgrestException catch (error) {
      final text = rpcText(code: error.code, message: error.message);
      return CreateGroupFailure(
        request.companions.isEmpty
            ? createGroupFailure(text)
            : partyCreateFailure(text),
      );
    }
  }

  @override
  Future<ConfirmAttendanceResult> confirmAttendance(
    String groupId, {
    required String userId,
  }) async {
    try {
      await client.rpc('confirm_attendance', params: {'p_group_id': groupId});
    } on PostgrestException catch (error) {
      return ConfirmAttendanceFailure(
        confirmFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) {
      return const ConfirmAttendanceFailure(
        ConfirmAttendanceFailureReason.notFound,
      );
    }
    return ConfirmAttendanceSuccess(group);
  }

  @override
  Future<LeaveGroupResult> leave(
    String groupId, {
    required String userId,
  }) async {
    try {
      await client.rpc('leave_group', params: {'p_group_id': groupId});
    } on PostgrestException catch (error) {
      return LeaveGroupFailure(
        leaveFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) {
      return const LeaveGroupFailure(LeaveGroupFailureReason.notFound);
    }
    return LeaveGroupSuccess(group);
  }

  @override
  Future<CloseGroupResult> closeWithFewer(
    String groupId, {
    required String userId,
  }) async {
    try {
      await client.rpc(
        'close_group_with_fewer',
        params: {'p_group_id': groupId},
      );
    } on PostgrestException catch (error) {
      return CloseGroupFailure(
        closeFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    await _settleClosed(groupId);
    final group = await getById(groupId);
    if (group == null) {
      return const CloseGroupFailure(CloseGroupFailureReason.notFound);
    }
    return CloseGroupSuccess(group);
  }

  @override
  Future<DeleteGroupResult> deleteGroup(
    String groupId, {
    required String userId,
  }) async {
    try {
      await client.rpc('delete_group', params: {'p_group_id': groupId});
      try {
        await client.functions.invoke(
          'cancel-house-group',
          body: {'group_id': groupId, 'action': 'release'},
        );
      } on Object {
        // O grupo já foi cancelado. A cobrança fica pending até o estorno.
      }
    } on PostgrestException catch (error) {
      return DeleteGroupFailure(
        deleteFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.notFound);
    }
    return DeleteGroupSuccess(group);
  }

  @override
  Future<RemoveMemberResult> removeMember(
    String groupId, {
    required String actorUserId,
    required String memberId,
  }) async {
    try {
      await client.rpc(
        'remove_member',
        params: {'p_group_id': groupId, 'p_member_id': memberId},
      );
    } on PostgrestException catch (error) {
      return RemoveMemberFailure(
        removeFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.notFound);
    }
    return RemoveMemberSuccess(group);
  }

  @override
  Future<EditGroupResult> edit(
    String groupId, {
    required String actorUserId,
    required int totalSpots,
    required String note,
  }) async {
    try {
      await client.rpc(
        'edit_group',
        params: {
          'p_group_id': groupId,
          'p_total_spots': totalSpots,
          'p_note': note,
        },
      );
    } on PostgrestException catch (error) {
      return EditGroupFailure(
        editFailure(rpcText(code: error.code, message: error.message)),
      );
    }
    final group = await getById(groupId);
    if (group == null) {
      return const EditGroupFailure(EditGroupFailureReason.notFound);
    }
    if (group.isFull && !group.isCancelled) {
      await _settleClosed(groupId);
    }
    return EditGroupSuccess(group);
  }

  /// Captura o cartão quando o grupo enche ou o host fecha com menos.
  /// Se a chamada falhar, a rotina de reconcile tenta de novo.
  Future<void> _settleClosed(String groupId) async {
    try {
      await client.functions.invoke(
        'settle-charges',
        body: {'group_id': groupId},
      );
    } on Object {
      // O grupo já fechou. A captura segue na próxima reconciliação.
    }
  }

  Future<List<Group>> _hydrate(
    List<dynamic> rawRows, {
    bool hideWithoutPayout = false,
  }) async {
    final rows = [
      for (final row in rawRows) Map<String, dynamic>.from(row as Map),
    ];
    if (rows.isEmpty) return const [];
    final venueIds = <String>{for (final row in rows) textOf(row['venue_id'])};
    final roomIds = <String>{for (final row in rows) textOf(row['room_id'])};
    final cityIds = <String>{for (final row in rows) textOf(row['city_id'])};
    final groupIds = <String>[for (final row in rows) row['id'] as String];
    final venues = await client
        .from('venues_vitrine')
        .select(venueVitrineColumns)
        .inFilter('id', venueIds.toList());
    final rooms = await client
        .from('rooms')
        .select(roomColumns)
        .inFilter('id', roomIds.toList());
    final cities = await client
        .from('cities')
        .select('id, name, state_code, state_name')
        .inFilter('id', cityIds.toList());
    final members = await client
        .from('group_members')
        .select(memberColumns)
        .inFilter('group_id', groupIds);
    final blockedVenues = <String>{
      for (final row in venues)
        if (!venueReceivesGroups(row)) row['id'] as String,
    };
    final houses = <String, EscapeHouse>{
      for (final row in venues)
        if (!hideWithoutPayout || venueReceivesGroups(row))
          row['id'] as String: houseFromRow(row),
    };
    final roomById = <String, EscapeRoom>{
      for (final row in rooms) row['id'] as String: roomFromRow(row),
    };
    final cityById = <String, City>{
      for (final row in cities) row['id'] as String: cityFromRow(row),
    };
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final row in members) {
      byGroup.putIfAbsent(row['group_id'] as String, () => []).add(row);
    }
    return [
      for (final row in rows)
        if (!hideWithoutPayout ||
            !blockedVenues.contains(textOf(row['venue_id'])))
          _group(
            row,
            house: houses[textOf(row['venue_id'])],
            room: roomById[textOf(row['room_id'])],
            city: cityById[textOf(row['city_id'])],
            members: byGroup[row['id'] as String] ?? const [],
          ),
    ];
  }

  Group _group(
    Map<String, dynamic> row, {
    required EscapeHouse? house,
    required EscapeRoom? room,
    required City? city,
    required List<Map<String, dynamic>> members,
  }) {
    final local = _userId;
    final participants = [
      for (final member in members)
        participantFromRow(member, localUserId: local),
    ];
    final startsAt = dateTimeOf(row['starts_at']) ?? DateTime.now();
    return Group(
      id: row['id'] as String,
      cityId: textOf(row['city_id']),
      cityName: city?.name ?? textOf(row['city_id']),
      houseId: textOf(row['venue_id']),
      houseName: house?.name ?? 'Casa',
      neighborhood: house?.neighborhood ?? '',
      roomId: textOf(row['room_id']),
      roomName: room?.name ?? 'Sala',
      roomTheme: room?.theme ?? '',
      roomCapacity: room?.capacity ?? intOf(row['total_spots'], fallback: 2),
      roomMinimum:
          room?.minimumPlayers ?? intOf(row['minimum_spots'], fallback: 2),
      durationMinutes: room?.durationMinutes ?? 60,
      difficulty: room?.difficulty ?? difficultyOf('medium'),
      slotId: textOf(row['session_id']),
      startsAt: startsAt,
      filledSpots: intOf(row['filled_spots']),
      totalSpots: intOf(row['total_spots'], fallback: 2),
      participants: participants,
      priceCents: intOf(row['price_cents']),
      gameType: room?.gameType ?? 'escape-room',
      note: textOf(row['note']),
      cancelledAt: dateTimeOf(row['cancelled_at']),
      cancelReason: textOf(row['cancel_reason']),
      minimumSpots: intOf(row['minimum_spots'], fallback: 2),
      closesAt: dateTimeOf(row['closes_at']),
      cancelWindow: Duration(
        minutes: intOf(row['cancel_window_minutes'], fallback: 120),
      ),
      streetAddress: house?.streetAddress ?? '',
      coverAsset: room == null ? '' : roomCategoryImage(room.category),
    );
  }
}

Participant participantFromRow(
  Map<String, dynamic> row, {
  required String? localUserId,
}) {
  final userId = textOf(row['user_id']);
  return Participant(
    id: row['id'] as String,
    userId: userId,
    displayName: textOf(row['display_name']),
    isCreator: row['is_creator'] == true,
    isLocalUser: localUserId != null && userId == localUserId,
    attendance: attendanceOf(textOf(row['attendance'])),
    payment: paymentOf(textOf(row['payment_status'])),
    refund: refundOf(textOf(row['refund_status'])),
    refundReason: refundReasonOf(textOf(row['refund_reason'])),
  );
}

AttendanceStatus attendanceOf(String raw) {
  return switch (raw) {
    'confirmed' => AttendanceStatus.confirmed,
    'cancelled' => AttendanceStatus.cancelled,
    _ => AttendanceStatus.joined,
  };
}

PaymentStatus paymentOf(String raw) {
  return switch (raw) {
    'reserved' => PaymentStatus.reserved,
    'paid' => PaymentStatus.paid,
    'released' => PaymentStatus.released,
    _ => PaymentStatus.pending,
  };
}

RefundStatus refundOf(String raw) {
  return switch (raw) {
    'refunded' => RefundStatus.refunded,
    'denied' => RefundStatus.denied,
    _ => RefundStatus.none,
  };
}

RefundReason refundReasonOf(String raw) {
  return switch (raw) {
    'cancelled_in_time' => RefundReason.cancelledInTime,
    'cancelled_too_late' => RefundReason.cancelledTooLate,
    'organizer_cancelled_event' => RefundReason.organizerCancelledEvent,
    'organizer_removed_member' => RefundReason.organizerRemovedMember,
    'group_did_not_close' => RefundReason.groupDidNotClose,
    'hold_released' => RefundReason.holdReleased,
    _ => RefundReason.none,
  };
}
