import 'package:dominio/dominio.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/groups/data/group_repository.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:scapematch/features/social/data/social_repository.dart';

/// Sample implementation of [GroupRepository].
///
/// [failList] exists so the error screen can be tested. The real app leaves
/// it false. Changes live only inside [FakeDatabase]. Time comes from [clock].
class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(
    this._database, {
    this.clock = const SystemClock(),
    this.latency = const Duration(milliseconds: 280),
    this.failList = false,
    this.friends,
    CommunityBoard? board,
  }) : board = board ?? CommunityBoard(),
       payments = PaymentBook(provider: SimulatedPaymentProvider()),
       absences = AbsenceBook();

  /// Livro da sessão. A tela não soma comissão; ela só lê a cadeira.
  final PaymentBook payments;

  /// Faltas marcadas pela casa. O mesmo livro vale para o app do jogador.
  final AbsenceBook absences;

  final FakeDatabase _database;
  final Clock clock;
  final Duration latency;
  final bool failList;
  final CommunityBoard board;

  /// Amizades da sessão. Sem isto, entrar com turma é recusado.
  final FriendDirectory? friends;

  @override
  Future<List<Group>> listByCity(
    String cityId, {
    bool almostFullOnly = false,
  }) async {
    await _sweep(clock.now());
    await _pause();
    if (failList) {
      throw Exception('sample list failed');
    }
    final now = clock.now();
    final groups = _database.groups.where((group) {
      if (group.cityId != cityId || !_listed(group, now)) {
        return false;
      }
      if (almostFullOnly && !group.isAlmostFull) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(groups);
  }

  @override
  Future<List<Group>> listForUser(String userId) async {
    await _sweep(clock.now());
    await _pause();
    final groups =
        _database.groups
            .where((group) => group.participantForUser(userId) != null)
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return List.unmodifiable(groups);
  }

  @override
  Future<Group?> getById(String id) async {
    await _sweep(clock.now());
    await _pause();
    return _find(id);
  }

  @override
  Future<String?> joinWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  }) {
    return Future.value(
      board.joinWaitlist(
        groupId: groupId,
        userId: userId,
        displayName: displayName,
        now: clock.now(),
      ),
    );
  }

  @override
  Future<JoinResult> acceptWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
  }) async {
    final now = clock.now();
    final entry = board.entryFor(groupId, userId);
    if (entry == null || !board.offerStillOpen(entry, now)) {
      final group = _find(groupId);
      if (group != null) {
        _syncWaitlist(group, now);
      }
      return const JoinFailure(JoinFailureReason.offerExpired);
    }
    final result = await join(
      groupId,
      participantUserId: userId,
      participantName: displayName,
    );
    if (result is JoinSuccess) {
      board.removeWaitlist(groupId, userId);
    }
    return result;
  }

  @override
  Future<void> declineWaitlist({
    required String groupId,
    required String userId,
  }) async {
    final now = clock.now();
    board.removeWaitlist(groupId, userId);
    final group = _find(groupId);
    if (group != null) {
      _syncWaitlist(group, now);
    }
  }

  @override
  Future<JoinResult> join(
    String groupId, {
    required String participantUserId,
    required String participantName,
    bool markAsLocalUser = true,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const JoinFailure(JoinFailureReason.notFound);
    }
    if (board.restricted(participantUserId, clock.now())) {
      return const JoinFailure(JoinFailureReason.restricted);
    }
    final current = _database.groups[index];
    for (final person in current.participants) {
      final memberId = person.userId;
      if (!person.occupiesSeat || memberId == null || memberId.isEmpty) {
        continue;
      }
      if (board.isBlocked(memberId, participantUserId)) {
        return const JoinFailure(JoinFailureReason.blocked);
      }
    }
    final now = clock.now();
    if (current.isCancelled) {
      return const JoinFailure(JoinFailureReason.groupCancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.sessionEnded);
    }
    final mine = current.participantForUser(participantUserId);
    if (mine != null && mine.occupiesSeat) {
      return const JoinFailure(JoinFailureReason.alreadyJoined);
    }
    if (mine != null) {
      return const JoinFailure(JoinFailureReason.membershipClosed);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.alreadyStarted);
    }
    if (_overlaps(
      userId: participantUserId,
      startsAt: current.startsAt,
      durationMinutes: current.durationMinutes,
      ignoringGroupId: current.id,
    )) {
      return const JoinFailure(JoinFailureReason.overlapsAnotherGroup);
    }
    if (!GroupRules.canJoin(
      filledSpots: current.filledSpots,
      totalSpots: current.totalSpots,
    )) {
      return const JoinFailure(JoinFailureReason.full);
    }
    final held = board.openOfferCount(
      current.id,
      now,
      exceptUserId: participantUserId,
    );
    if (current.openSeats <= held) {
      return const JoinFailure(JoinFailureReason.seatReserved);
    }
    final updated = await _confirmIfReady(
      current.copyWith(
        filledSpots: current.filledSpots + 1,
        participants: [
          ...current.participants,
          Participant(
            id: _database.nextParticipantId(),
            userId: participantUserId,
            displayName: participantName,
            isCreator: false,
            isLocalUser: markAsLocalUser,
          ),
        ],
      ),
    );
    _database.groups[index] = updated;
    board.removeWaitlist(groupId, participantUserId);
    return JoinSuccess(updated);
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
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const JoinFailure(JoinFailureReason.notFound);
    }
    final current = _database.groups[index];
    final party = <({String id, String name})>[
      (id: leaderUserId, name: leaderName),
    ];
    final seen = <String>{leaderUserId};
    for (final companion in companions) {
      if (companion.userId == leaderUserId) {
        continue;
      }
      if (!seen.add(companion.userId)) {
        return const JoinFailure(
          JoinFailureReason.companionUnavailable,
          detail: 'A turma tem uma pessoa repetida. Ninguém entrou.',
        );
      }
      party.add((id: companion.userId, name: companion.displayName));
    }
    if (party.length < 2) {
      return join(
        groupId,
        participantUserId: leaderUserId,
        participantName: leaderName,
      );
    }

    final blocked = _partyBlocked(
      current,
      party: party,
      leaderUserId: leaderUserId,
    );
    if (blocked != null) {
      return blocked;
    }

    final people = [...current.participants];
    for (var indexInParty = 0; indexInParty < party.length; indexInParty++) {
      final person = party[indexInParty];
      people.add(
        Participant(
          id: _database.nextParticipantId(),
          userId: person.id,
          displayName: person.name,
          isCreator: false,
          isLocalUser: indexInParty == 0,
        ),
      );
      board.removeWaitlist(groupId, person.id);
      if (indexInParty > 0) {
        board.postNotice(
          userId: person.id,
          kind: NoticeKind.partySeat,
          title: 'Vaga reservada',
          body:
              '$leaderName reservou sua vaga em ${current.roomName}. Pague a sua parte para confirmar. Nada é cobrado se o grupo não confirmar.',
          at: clock.now(),
          groupId: current.id,
          scope: 'party-${current.id}-${person.id}',
        );
      }
    }
    final updated = await _confirmIfReady(
      current.copyWith(
        participants: people,
        filledSpots: _occupied(people),
      ),
    );
    _database.groups[index] = updated;
    return JoinSuccess(updated);
  }

  /// Confere a turma inteira antes de escrever. Qualquer falha devolve
  /// o grupo como estava.
  JoinFailure? _partyBlocked(
    Group current, {
    required List<({String id, String name})> party,
    required String leaderUserId,
  }) {
    final now = clock.now();
    if (current.isCancelled) {
      return const JoinFailure(JoinFailureReason.groupCancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.sessionEnded);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const JoinFailure(JoinFailureReason.alreadyStarted);
    }
    final ids = {for (final person in party) person.id};
    if (current.openSeats < party.length) {
      return JoinFailure(
        JoinFailureReason.partyDoesNotFit,
        detail:
            'Há ${current.openSeats} vaga(s) e a turma precisa de ${party.length}. Ninguém entrou.',
      );
    }
    final held = board.openOfferCount(current.id, now);
    var heldByOthers = held;
    for (final id in ids) {
      final entry = board.entryFor(current.id, id);
      if (entry != null && board.offerStillOpen(entry, now)) {
        heldByOthers -= 1;
      }
    }
    if (heldByOthers < 0) {
      heldByOthers = 0;
    }
    if (current.openSeats - heldByOthers < party.length) {
      return const JoinFailure(JoinFailureReason.seatReserved);
    }

    for (final person in party) {
      if (board.restricted(person.id, now)) {
        return JoinFailure(
          JoinFailureReason.companionUnavailable,
          detail: '${person.name} está em pausa. Ninguém entrou.',
        );
      }
      for (final seated in current.participants) {
        final memberId = seated.userId;
        if (!seated.occupiesSeat || memberId == null || memberId.isEmpty) {
          continue;
        }
        if (board.isBlocked(memberId, person.id)) {
          return JoinFailure(
            JoinFailureReason.companionUnavailable,
            detail: '${person.name} foi bloqueado neste grupo. Ninguém entrou.',
          );
        }
      }
      final mine = current.participantForUser(person.id);
      if (mine != null && mine.occupiesSeat) {
        return JoinFailure(
          JoinFailureReason.companionUnavailable,
          detail: '${person.name} já está neste grupo. Ninguém entrou.',
        );
      }
      if (mine != null) {
        return JoinFailure(
          JoinFailureReason.companionUnavailable,
          detail: '${person.name} já saiu deste grupo. Ninguém entrou.',
        );
      }
      if (_overlaps(
        userId: person.id,
        startsAt: current.startsAt,
        durationMinutes: current.durationMinutes,
        ignoringGroupId: current.id,
      )) {
        return JoinFailure(
          JoinFailureReason.companionUnavailable,
          detail:
              '${person.name} já está em outro grupo nesse horário. Ninguém entrou.',
        );
      }
      if (person.id != leaderUserId) {
        final directory = friends;
        if (directory == null ||
            !directory.areFriends(leaderUserId, person.id)) {
          return JoinFailure(
            JoinFailureReason.companionNotFriend,
            detail: '${person.name} não é um amigo aceito. Ninguém entrou.',
          );
        }
      }
    }
    return null;
  }

  @override
  Future<PayShareResult> payWithNewCard(
    String groupId, {
    required String userId,
    required CardDraft card,
  }) {
    if (card.number.isEmpty) {
      return Future.value(
        const PayShareFailure(PayShareFailureReason.unavailable),
      );
    }
    return payShare(groupId, userId: userId, kind: PaymentMethodKind.card);
  }

  @override
  Future<PayShareResult> payShare(
    String groupId, {
    required String userId,
    required PaymentMethodKind kind,
    String? savedCardId,
    int points = 0,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const PayShareFailure(PayShareFailureReason.notFound);
    }
    final current = _database.groups[index];
    if (current.isCancelled) {
      return const PayShareFailure(PayShareFailureReason.groupCancelled);
    }
    final member = current.participantForUser(userId);
    if (member == null || !member.occupiesSeat) {
      return const PayShareFailure(PayShareFailureReason.notSeated);
    }
    if (member.payment == PaymentStatus.paid ||
        member.payment == PaymentStatus.reserved) {
      return const PayShareFailure(PayShareFailureReason.alreadyPaid);
    }
    final seated = [
      for (final person in current.participants)
        if (person.occupiesSeat) person,
    ];
    var reservation = await _ensureReservation(current, seated);
    var share = _shareFor(reservation, member);
    if (share.status == ShareStatus.refunded ||
        share.status == ShareStatus.released) {
      reservation = payments.addShare(
        reservationId: current.id,
        playerId: _payerId(member),
        amountCents: current.priceCents,
      );
      share = _shareFor(reservation, member);
    }
    final paid = await payments.payShare(
      reservationId: current.id,
      shareId: share.id,
      kind: kind,
      idempotencyKey: 'pay-${share.id}',
    );
    final settled = _shareFor(paid, member);
    if (settled.status != ShareStatus.reserved &&
        settled.status != ShareStatus.paid) {
      return const PayShareFailure(PayShareFailureReason.notSeated);
    }
    var updated = _replaceMember(
      current,
      member.copyWith(
        payment: settled.status == ShareStatus.paid
            ? PaymentStatus.paid
            : PaymentStatus.reserved,
      ),
    );
    updated = await _confirmIfReady(updated);
    _database.groups[index] = updated;
    return PayShareSuccess(updated);
  }

  @override
  Future<CloseGroupResult> closeWithFewer(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const CloseGroupFailure(CloseGroupFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (!current.createdBy(userId)) {
      return const CloseGroupFailure(CloseGroupFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const CloseGroupFailure(CloseGroupFailureReason.alreadyCancelled);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const CloseGroupFailure(CloseGroupFailureReason.sessionStarted);
    }
    final seated = current.occupiedSpots;
    if (seated >= current.totalSpots) {
      return const CloseGroupFailure(
        CloseGroupFailureReason.alreadyPlannedSize,
      );
    }
    return const CloseGroupFailure(CloseGroupFailureReason.staysOpen);
  }

  @override
  Future<CreateGroupResult> create(CreateGroupRequest request) async {
    await _pause();
    final city = _database.cityById(request.cityId);
    final house = _database.houseById(request.houseId);
    final room = _database.roomById(request.roomId);
    final slot = _database.slotById(request.slotId);
    if (city == null ||
        house == null ||
        room == null ||
        slot == null ||
        house.cityId != city.id ||
        room.houseId != house.id ||
        slot.roomId != room.id ||
        !slot.active) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.unknownSelection,
      );
    }

    final maximumPlayers = 1 + request.extraSpots;
    final minimumPlayers = request.minimumPlayers ?? maximumPlayers;
    final validation = GroupRules.validatePlayerBand(
      minimumPlayers: minimumPlayers,
      maximumPlayers: maximumPlayers,
      roomMinimum: room.minimumPlayers,
      roomCapacity: room.capacity,
    );
    switch (validation) {
      case GroupSizeValidation.belowMinimum:
        return const CreateGroupFailure(CreateGroupFailureReason.belowMinimum);
      case GroupSizeValidation.belowRoomMinimum:
        return const CreateGroupFailure(
          CreateGroupFailureReason.belowRoomMinimum,
        );
      case GroupSizeValidation.exceedsRoomCapacity:
        return const CreateGroupFailure(
          CreateGroupFailureReason.exceedsRoomCapacity,
        );
      case GroupSizeValidation.valid:
        break;
    }

    final now = clock.now();
    if (GroupRules.hasStarted(startsAt: slot.startsAt, now: now)) {
      return const CreateGroupFailure(CreateGroupFailureReason.alreadyStarted);
    }
    if (GroupRules.tooCloseToCreate(startsAt: slot.startsAt, now: now)) {
      return const CreateGroupFailure(CreateGroupFailureReason.tooCloseToStart);
    }

    final taken = GroupRules.roomAndTimeTaken(
      roomId: room.id,
      startsAt: slot.startsAt,
      existing: [
        for (final group in _database.groups)
          if (!group.isCancelled)
            (roomId: group.roomId, startsAt: group.startsAt),
      ],
    );
    if (taken) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.duplicateSession,
      );
    }

    if (_overlaps(
      userId: request.creatorUserId,
      startsAt: slot.startsAt,
      durationMinutes: room.durationMinutes,
    )) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.overlapsAnotherGroup,
      );
    }

    final companions = <PartyCompanion>[];
    final seen = <String>{request.creatorUserId};
    for (final companion in request.companions) {
      if (!seen.add(companion.userId)) {
        return const CreateGroupFailure(
          CreateGroupFailureReason.companionUnavailable,
        );
      }
      final directory = friends;
      if (directory == null ||
          !directory.areFriends(request.creatorUserId, companion.userId)) {
        return const CreateGroupFailure(
          CreateGroupFailureReason.companionNotFriend,
        );
      }
      if (_overlaps(
        userId: companion.userId,
        startsAt: slot.startsAt,
        durationMinutes: room.durationMinutes,
      )) {
        return const CreateGroupFailure(
          CreateGroupFailureReason.companionUnavailable,
        );
      }
      companions.add(companion);
    }
    if (companions.isNotEmpty && companions.length >= request.extraSpots) {
      return const CreateGroupFailure(
        CreateGroupFailureReason.crewLeavesNoOpenSeat,
      );
    }

    final id = _database.nextGroupId();
    final seated = [
      Participant(
        id: _database.nextParticipantId(),
        userId: request.creatorUserId,
        displayName: request.creatorDisplayName,
        isCreator: true,
        isLocalUser: true,
      ),
      for (final companion in companions)
        Participant(
          id: _database.nextParticipantId(),
          userId: companion.userId,
          displayName: companion.displayName,
          isCreator: false,
          isLocalUser: false,
        ),
    ];
    final group = Group(
      id: id,
      cityId: city.id,
      cityName: city.name,
      houseId: house.id,
      houseName: house.name,
      neighborhood: house.neighborhood,
      roomId: room.id,
      roomName: room.name,
      roomTheme: room.theme,
      roomCapacity: room.capacity,
      roomMinimum: room.minimumPlayers,
      durationMinutes: room.durationMinutes,
      difficulty: room.difficulty,
      slotId: slot.id,
      startsAt: slot.startsAt,
      filledSpots: seated.length,
      totalSpots: maximumPlayers,
      priceCents: room.priceCents,
      minimumSpots: minimumPlayers,
      confirmedAt: seated.length >= minimumPlayers ? now : null,
      cancelWindow: room.cancelWindow,
      streetAddress: house.streetAddress,
      coverAsset: roomCategoryImage(room.category),
      closesAt: GroupRules.closeDeadline(startsAt: slot.startsAt, now: now),
      participants: seated,
    );
    for (final companion in companions) {
      board.postNotice(
        userId: companion.userId,
        kind: NoticeKind.partySeat,
        title: 'Vaga reservada',
        body:
            '${request.creatorDisplayName} criou ${room.name} com você dentro. Pague a sua parte. As outras vagas ficam abertas.',
        at: now,
        groupId: id,
        scope: 'create-$id-${companion.userId}',
      );
    }
    _database.groups.add(group);
    return CreateGroupSuccess(group);
  }

  @override
  Future<ConfirmAttendanceResult> confirmAttendance(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    switch (_lookupSeat(groupId, userId)) {
      case _SeatProblem(:final kind):
        return ConfirmAttendanceFailure(_confirmProblem(kind));
      case _SeatFound(:final index, :final group, :final member):
        final updated = _replaceMember(
          group,
          member.copyWith(attendance: AttendanceStatus.confirmed),
        );
        _database.groups[index] = updated;
        return ConfirmAttendanceSuccess(updated);
    }
  }

  @override
  Future<LeaveGroupResult> leave(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    switch (_lookupSeat(groupId, userId)) {
      case _SeatProblem(:final kind):
        return LeaveGroupFailure(_leaveProblem(kind));
      case _SeatFound(
        index: final index,
        group: final current,
        member: final member,
      ):
        if (member.isCreator) {
          return const LeaveGroupFailure(
            LeaveGroupFailureReason.creatorMustDelete,
          );
        }
        final outcome = GroupRules.refundForParticipantCancel(
          startsAt: current.startsAt,
          now: clock.now(),
          window: current.cancelWindow,
        );
        final updatedPeople = <Participant>[];
        for (final person in current.participants) {
          if (person.id == member.id) {
            updatedPeople.add(
              await _closeSeat(
                group: current,
                person: person,
                outcome: outcome,
              ),
            );
          } else {
            updatedPeople.add(person);
          }
        }
        final updated = current.copyWith(
          participants: updatedPeople,
          filledSpots: _occupied(updatedPeople),
        );
        _database.groups[index] = updated;
        _syncWaitlist(updated, clock.now());
        return LeaveGroupSuccess(updated);
    }
  }

  @override
  Future<DeleteGroupResult> deleteGroup(
    String groupId, {
    required String userId,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.notFound);
    }
    final current = _database.groups[index];
    if (!current.createdBy(userId)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const DeleteGroupFailure(
        DeleteGroupFailureReason.alreadyCancelled,
      );
    }
    final now = clock.now();
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.sessionEnded);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const DeleteGroupFailure(DeleteGroupFailureReason.sessionStarted);
    }
    if (!GroupRules.canDeleteGroup(startsAt: current.startsAt, now: now)) {
      return const DeleteGroupFailure(
        DeleteGroupFailureReason.tooCloseToDelete,
      );
    }
    final outcome = GroupRules.refundForOrganizer(
      RefundReason.organizerCancelledEvent,
    );
    final updated = current.copyWith(
      cancelledAt: now,
      filledSpots: 0,
      participants: await _closeOccupants(current, outcome),
    );
    _database.groups[index] = updated;
    return DeleteGroupSuccess(updated);
  }

  /// A casa cancela a sessão. Vale a mesma janela de 2 h do host.
  Future<String?> cancelForHouse({
    required String houseId,
    required String groupId,
    required String reason,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return 'Sessão não encontrada.';
    }
    final current = _database.groups[index];
    if (current.houseId != houseId) {
      return 'Sessão não encontrada.';
    }
    if (current.isCancelled) {
      return 'Essa sessão já está cancelada.';
    }
    final now = clock.now();
    if (!now.isBefore(current.startsAt)) {
      return 'A sessão já começou.';
    }
    if (!GroupRules.canDeleteGroup(startsAt: current.startsAt, now: now)) {
      return 'Exclusão bloqueada (menos de 2 h)';
    }
    final outcome = GroupRules.refundForOrganizer(
      RefundReason.organizerCancelledEvent,
    );
    final text = reason.trim().isEmpty ? 'Cancelada pela casa' : reason.trim();
    _database.groups[index] = current.copyWith(
      cancelledAt: now,
      cancelReason: text,
      filledSpots: 0,
      participants: await _closeOccupants(current, outcome),
    );
    return null;
  }

  @override
  Future<RemoveMemberResult> removeMember(
    String groupId, {
    required String actorUserId,
    required String memberId,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (!current.createdBy(actorUserId)) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.groupCancelled,
      );
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const RemoveMemberFailure(RemoveMemberFailureReason.sessionEnded);
    }
    if (GroupRules.hasStarted(startsAt: current.startsAt, now: now)) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.sessionStarted,
      );
    }
    Participant? target;
    for (final person in current.participants) {
      if (person.id == memberId) {
        target = person;
        break;
      }
    }
    if (target == null || !target.occupiesSeat) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.memberNotFound,
      );
    }
    if (target.isCreator) {
      return const RemoveMemberFailure(
        RemoveMemberFailureReason.cannotRemoveCreator,
      );
    }
    final outcome = GroupRules.refundForOrganizer(
      RefundReason.organizerRemovedMember,
    );
    final updatedPeople = <Participant>[];
    for (final person in current.participants) {
      if (person.id == target.id) {
        updatedPeople.add(
          await _closeSeat(group: current, person: person, outcome: outcome),
        );
      } else {
        updatedPeople.add(person);
      }
    }
    final updated = current.copyWith(
      participants: updatedPeople,
      filledSpots: _occupied(updatedPeople),
    );
    _database.groups[index] = updated;
    _syncWaitlist(updated, now);
    return RemoveMemberSuccess(updated);
  }

  @override
  Future<EditGroupResult> edit(
    String groupId, {
    required String actorUserId,
    required int totalSpots,
    required String note,
    int? minimumSpots,
  }) async {
    await _pause();
    final index = _indexOf(groupId);
    if (index < 0) {
      return const EditGroupFailure(EditGroupFailureReason.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (!current.createdBy(actorUserId)) {
      return const EditGroupFailure(EditGroupFailureReason.notCreator);
    }
    if (current.isCancelled) {
      return const EditGroupFailure(EditGroupFailureReason.groupCancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const EditGroupFailure(EditGroupFailureReason.sessionEnded);
    }
    if (GroupRules.noteTooLong(note)) {
      return const EditGroupFailure(EditGroupFailureReason.noteTooLong);
    }
    final occupied = current.occupiedSpots;
    final minimum = minimumSpots ?? current.minimumSpots;
    if (minimum < current.roomMinimum || minimum > current.roomCapacity) {
      return const EditGroupFailure(EditGroupFailureReason.belowRoomMinimum);
    }
    final validation = GroupRules.validateTotalSpots(
      totalSpots: totalSpots,
      occupiedSpots: occupied,
      roomCapacity: current.roomCapacity,
      minimumPlayers: minimum,
    );
    switch (validation) {
      case TotalSpotsValidation.belowMinimum:
        return const EditGroupFailure(EditGroupFailureReason.belowMinimum);
      case TotalSpotsValidation.belowRoomMinimum:
        return const EditGroupFailure(EditGroupFailureReason.belowRoomMinimum);
      case TotalSpotsValidation.belowOccupancy:
        return const EditGroupFailure(EditGroupFailureReason.belowOccupancy);
      case TotalSpotsValidation.exceedsRoomCapacity:
        return const EditGroupFailure(
          EditGroupFailureReason.exceedsRoomCapacity,
        );
      case TotalSpotsValidation.valid:
        break;
    }
    final updated = await _confirmIfReady(
      current.copyWith(
        totalSpots: totalSpots,
        minimumSpots: minimum,
        note: GroupRules.normalizeNote(note),
      ),
    );
    _database.groups[index] = updated;
    return EditGroupSuccess(updated);
  }

  void _syncWaitlist(Group group, DateTime now) {
    board.clearExpiredOffers(group.id, now);
    var slack = group.openSeats - board.openOfferCount(group.id, now);
    while (slack > 0) {
      final offered = board.offerNext(groupId: group.id, now: now);
      if (!offered) {
        return;
      }
      slack -= 1;
    }
  }

  Future<void> _sweep(DateTime now) async {
    for (var index = 0; index < _database.groups.length; index++) {
      final group = await _releaseUnpaid(index, _database.groups[index], now);
      final portal =
          group.phaseOverride != null && isPortalPhase(group.phaseOverride!);
      if (GroupRules.missedMinimum(
        alreadyCancelled: group.isCancelled,
        portalOwned: portal,
        filledSpots: group.filledSpots,
        minimumSpots: group.minimumSpots,
        alreadyConfirmed: group.confirmedAt != null,
        closesAt: group.closesAtResolved,
        startsAt: group.startsAt,
        now: now,
      )) {
        final outcome = GroupRules.refundForOrganizer(
          RefundReason.groupDidNotClose,
        );
        final closed = group.copyWith(
          cancelledAt: now,
          filledSpots: 0,
          participants: await _closeOccupants(group, outcome),
        );
        _database.groups[index] = closed;
        board.recordClosedGroup(group, now);
        continue;
      }
      if (!group.isCancelled) {
        _syncWaitlist(group, now);
      }
    }
  }

  bool _listed(Group group, DateTime now) {
    if (group.isCancelled) {
      return false;
    }
    return !GroupRules.hasEnded(endsAt: group.endsAt, now: now);
  }

  bool _overlaps({
    required String userId,
    required DateTime startsAt,
    required int durationMinutes,
    String? ignoringGroupId,
  }) {
    final now = clock.now();
    final window = Duration(minutes: durationMinutes);
    for (final group in _database.groups) {
      if (group.id == ignoringGroupId || group.isCancelled) {
        continue;
      }
      if (GroupRules.hasEnded(endsAt: group.endsAt, now: now)) {
        continue;
      }
      final member = group.participantForUser(userId);
      if (member == null || !member.occupiesSeat) {
        continue;
      }
      if (GroupRules.sessionsOverlap(
        startA: group.startsAt,
        durationA: Duration(minutes: group.durationMinutes),
        startB: startsAt,
        durationB: window,
      )) {
        return true;
      }
    }
    return false;
  }

  _SeatLookup _lookupSeat(String groupId, String userId) {
    final index = _indexOf(groupId);
    if (index < 0) {
      return const _SeatProblem(_SeatKind.notFound);
    }
    final current = _database.groups[index];
    final now = clock.now();
    if (current.isCancelled) {
      return const _SeatProblem(_SeatKind.cancelled);
    }
    if (GroupRules.hasEnded(endsAt: current.endsAt, now: now)) {
      return const _SeatProblem(_SeatKind.ended);
    }
    final member = current.participantForUser(userId);
    if (member == null || !member.occupiesSeat) {
      return const _SeatProblem(_SeatKind.notMember);
    }
    return _SeatFound(index, current, member);
  }

  ConfirmAttendanceFailureReason _confirmProblem(_SeatKind kind) {
    return switch (kind) {
      _SeatKind.notFound => ConfirmAttendanceFailureReason.notFound,
      _SeatKind.cancelled => ConfirmAttendanceFailureReason.groupCancelled,
      _SeatKind.ended => ConfirmAttendanceFailureReason.sessionEnded,
      _SeatKind.notMember => ConfirmAttendanceFailureReason.notMember,
    };
  }

  LeaveGroupFailureReason _leaveProblem(_SeatKind kind) {
    return switch (kind) {
      _SeatKind.notFound => LeaveGroupFailureReason.notFound,
      _SeatKind.cancelled => LeaveGroupFailureReason.groupCancelled,
      _SeatKind.ended => LeaveGroupFailureReason.sessionEnded,
      _SeatKind.notMember => LeaveGroupFailureReason.notMember,
    };
  }

  /// Abre as reservas da casa no livro compartilhado.
  ///
  /// Quem a cadeira já marca como pago é capturado. Quem está reservado
  /// ganha a pré-autorização, sem entrar no extrato.
  Future<void> materializeHouse(String houseId) async {
    await _sweep(clock.now());
    await _pause();
    for (final group in List<Group>.of(_database.groups)) {
      if (group.houseId != houseId || group.isCancelled) {
        continue;
      }
      final seated = [
        for (final person in group.participants)
          if (person.occupiesSeat) person,
      ];
      if (seated.isEmpty) {
        continue;
      }
      var reservation = await _ensureReservation(group, seated);
      for (final person in seated) {
        if (person.payment != PaymentStatus.reserved) {
          continue;
        }
        final share = _shareFor(reservation, person);
        if (share.status != ShareStatus.pending &&
            share.status != ShareStatus.failed) {
          continue;
        }
        reservation = await payments.payShare(
          reservationId: group.id,
          shareId: share.id,
          kind: PaymentMethodKind.pix,
          idempotencyKey: 'seed-hold-${group.id}-${_payerId(person)}',
        );
      }
    }
  }

  String _payerId(Participant person) {
    final userId = person.userId;
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }
    return person.id;
  }

  ReservationShare _shareFor(Reservation reservation, Participant person) {
    final payerId = _payerId(person);
    ReservationShare? refunded;
    for (final share in reservation.shares) {
      if (share.playerId != payerId) {
        continue;
      }
      if (share.status != ShareStatus.refunded &&
          share.status != ShareStatus.released) {
        return share;
      }
      refunded = share;
    }
    if (refunded != null) {
      return refunded;
    }
    throw StateError('Parte ausente para ${person.displayName}.');
  }

  /// Abre a reserva do grupo e grava como pago quem a cadeira já marca pago.
  Future<Reservation> _ensureReservation(
    Group group,
    List<Participant> seated,
  ) async {
    final ids = [for (final person in seated) _payerId(person)];
    final existing = payments.lookup(group.id);
    var reservation =
        existing ??
        payments.createReservation(
          id: group.id,
          groupId: group.id,
          houseId: group.houseId,
          totalCents: group.priceCents * ids.length,
          playerIds: ids,
        );
    if (existing != null) {
      for (final person in seated) {
        final payerId = _payerId(person);
        final known = reservation.shares.any(
          (share) => share.playerId == payerId,
        );
        if (!known) {
          reservation = payments.addShare(
            reservationId: group.id,
            playerId: payerId,
            amountCents: group.priceCents,
          );
        }
      }
    }
    for (final person in seated) {
      if (person.payment != PaymentStatus.paid) {
        continue;
      }
      final share = _shareFor(reservation, person);
      if (share.status != ShareStatus.pending &&
          share.status != ShareStatus.failed) {
        continue;
      }
      reservation = await payments.payShare(
        reservationId: group.id,
        shareId: share.id,
        kind: PaymentMethodKind.pix,
        idempotencyKey: 'seed-${group.id}-${_payerId(person)}',
      );
      reservation = await payments.captureReservation(
        reservationId: group.id,
        idempotencyKey: 'seed-capture-${group.id}-${_payerId(person)}',
        onlyPlayerIds: [_payerId(person)],
      );
    }
    return reservation;
  }

  /// Captura quem já reservou quando o mínimo foi atingido.
  ///
  /// Quem entra depois paga e a parte dele é capturada na hora.
  /// Quem pagou antes não é reajustado.
  Future<Group> _confirmIfReady(Group group) async {
    if (group.isCancelled) {
      return group;
    }
    final ready =
        group.confirmedAt != null || group.filledSpots >= group.minimumSpots;
    if (!ready) {
      return group;
    }
    final captured = await _captureClosed(group);
    if (captured.confirmedAt != null) {
      return captured;
    }
    return captured.copyWith(confirmedAt: clock.now());
  }

  Future<Group> _captureClosed(Group group) async {
    final seated = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];
    if (seated.isEmpty) {
      return group;
    }
    final reservation = await _ensureReservation(group, seated);
    if (reservation.shares.any(
      (share) => share.status == ShareStatus.reserved,
    )) {
      await payments.captureReservation(
        reservationId: group.id,
        idempotencyKey: 'capture-${group.id}',
      );
    }
    return group.copyWith(
      participants: [
        for (final person in group.participants)
          if (person.occupiesSeat && person.payment == PaymentStatus.reserved)
            person.copyWith(payment: PaymentStatus.paid)
          else
            person,
      ],
    );
  }

  Future<Participant> _closeSeat({
    required Group group,
    required Participant person,
    required RefundOutcome outcome,
  }) async {
    if (!person.occupiesSeat) {
      return person;
    }
    if (person.payment == PaymentStatus.reserved) {
      final seated = [
        for (final member in group.participants)
          if (member.occupiesSeat) member,
      ];
      final reservation = await _ensureReservation(group, seated);
      final share = _shareFor(reservation, person);
      if (share.status == ShareStatus.reserved ||
          share.status == ShareStatus.awaitingConfirmation) {
        await payments.releaseShare(
          reservationId: group.id,
          shareId: share.id,
          idempotencyKey: 'release-${share.id}',
        );
      }
      return person.copyWith(
        attendance: AttendanceStatus.cancelled,
        payment: PaymentStatus.released,
        refundReason: outcome.reason == RefundReason.groupDidNotClose
            ? RefundReason.groupDidNotClose
            : RefundReason.holdReleased,
      );
    }
    if (person.payment != PaymentStatus.paid ||
        outcome.status != RefundStatus.refunded) {
      return person.copyWith(
        attendance: AttendanceStatus.cancelled,
        refund: person.payment == PaymentStatus.paid
            ? outcome.status
            : RefundStatus.none,
        refundReason: person.payment == PaymentStatus.paid
            ? outcome.reason
            : RefundReason.none,
      );
    }
    final seated = [
      for (final member in group.participants)
        if (member.occupiesSeat) member,
    ];
    final reservation = await _ensureReservation(group, seated);
    final share = _shareFor(reservation, person);
    if (share.status == ShareStatus.paid) {
      await payments.refundShare(
        reservationId: group.id,
        shareId: share.id,
        idempotencyKey: 'refund-${share.id}',
      );
    }
    return person.copyWith(
      attendance: AttendanceStatus.cancelled,
      refund: outcome.status,
      refundReason: outcome.reason,
    );
  }

  Future<List<Participant>> _closeOccupants(
    Group group,
    RefundOutcome outcome,
  ) async {
    final next = <Participant>[];
    for (final person in group.participants) {
      if (!person.occupiesSeat) {
        next.add(person);
        continue;
      }
      next.add(
        await _closeSeat(group: group, person: person, outcome: outcome),
      );
    }
    return next;
  }

  /// Quem não pagou até o prazo de fechar perde a vaga. Não há o que estornar.
  Future<Group> _releaseUnpaid(int index, Group group, DateTime now) async {
    if (group.isCancelled || !now.isBefore(group.startsAt)) {
      return group;
    }
    if (now.isBefore(group.closesAtResolved)) {
      return group;
    }
    final next = <Participant>[];
    var changed = false;
    for (final person in group.participants) {
      if (person.occupiesSeat && person.payment == PaymentStatus.pending) {
        changed = true;
        next.add(person.copyWith(attendance: AttendanceStatus.cancelled));
      } else {
        next.add(person);
      }
    }
    if (!changed) {
      return group;
    }
    final updated = group.copyWith(
      participants: next,
      filledSpots: _occupied(next),
    );
    _database.groups[index] = updated;
    return updated;
  }

  Group _replaceMember(Group group, Participant member) {
    return group.copyWith(
      participants: [
        for (final person in group.participants)
          if (person.id == member.id) member else person,
      ],
    );
  }

  int _occupied(List<Participant> people) {
    return people.where((person) => person.occupiesSeat).length;
  }

  Group? _find(String id) {
    final index = _indexOf(id);
    if (index < 0) {
      return null;
    }
    return _database.groups[index];
  }

  int _indexOf(String id) {
    return _database.groups.indexWhere((group) => group.id == id);
  }

  Future<void> _pause() {
    if (latency == Duration.zero) {
      return Future<void>.value();
    }
    return Future<void>.delayed(latency);
  }
}

enum _SeatKind { notFound, cancelled, ended, notMember }

sealed class _SeatLookup {
  const _SeatLookup();
}

class _SeatProblem extends _SeatLookup {
  const _SeatProblem(this.kind);

  final _SeatKind kind;
}

class _SeatFound extends _SeatLookup {
  const _SeatFound(this.index, this.group, this.member);

  final int index;
  final Group group;
  final Participant member;
}
