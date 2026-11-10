import 'package:dominio/dominio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

import 'support/sample_clock.dart';

void main() {
  test('confirma no mínimo, aceita quem paga depois e trava o máximo', () async {
    final database = buildSampleDatabase(now: sampleNow);
    final slot = TimeSlot(
      id: 'slot-faixa',
      roomId: SampleIds.roomPoaEstufa,
      startsAt: sampleNow.add(const Duration(days: 3)),
    );
    database.slots.add(slot);
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(sampleNow),
      latency: Duration.zero,
    );
    final created = await groups.create(
      CreateGroupRequest(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: slot.id,
        extraSpots: 2,
        minimumPlayers: 2,
        creatorUserId: 'user-faixa-host',
        creatorDisplayName: 'Host',
      ),
    );
    final opened = (created as CreateGroupSuccess).group;
    expect(opened.minimumSpots, 2);
    expect(opened.totalSpots, 3);
    expect(opened.isConfirmed, isFalse);
    expect(opened.filledSpots, 1);

    final hostPaid = await groups.payShare(
      opened.id,
      userId: 'user-faixa-host',
      kind: PaymentMethodKind.pix,
    );
    expect(hostPaid, isA<PayShareSuccess>());
    final hostBefore = (hostPaid as PayShareSuccess).group.participantForUser(
      'user-faixa-host',
    );
    expect(hostBefore!.payment, PaymentStatus.reserved);
    final price = opened.priceCents;

    final joined = await groups.join(
      opened.id,
      participantUserId: 'user-faixa-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    );
    final confirmed = (joined as JoinSuccess).group;
    expect(confirmed.isConfirmed, isTrue);
    expect(confirmed.isFull, isFalse);
    expect(confirmed.confirmedAt, isNotNull);
    expect(
      confirmed.participantForUser('user-faixa-host')!.payment,
      PaymentStatus.paid,
    );
    expect(
      groups.payments.reservation(opened.id).shares
          .firstWhere((share) => share.playerId == 'user-faixa-host')
          .amountCents,
      price,
    );

    final biaPaid = await groups.payShare(
      opened.id,
      userId: 'user-faixa-bia',
      kind: PaymentMethodKind.pix,
    );
    final withBia = (biaPaid as PayShareSuccess).group;
    expect(
      withBia.participantForUser('user-faixa-bia')!.payment,
      PaymentStatus.paid,
    );
    expect(
      groups.payments.reservation(opened.id).shares
          .firstWhere((share) => share.playerId == 'user-faixa-host')
          .amountCents,
      price,
    );

    final third = await groups.join(
      opened.id,
      participantUserId: 'user-faixa-caio',
      participantName: 'Caio',
      markAsLocalUser: false,
    );
    expect((third as JoinSuccess).group.isFull, isTrue);
    final caioPaid = await groups.payShare(
      opened.id,
      userId: 'user-faixa-caio',
      kind: PaymentMethodKind.pix,
    );
    expect(
      (caioPaid as PayShareSuccess).group.participantForUser('user-faixa-caio')!
          .payment,
      PaymentStatus.paid,
    );

    final blocked = await groups.join(
      opened.id,
      participantUserId: 'user-faixa-duda',
      participantName: 'Duda',
      markAsLocalUser: false,
    );
    expect(blocked, isA<JoinFailure>());
    expect((blocked as JoinFailure).reason, JoinFailureReason.full);
  });

  test('prazo sem o mínimo cancela e não confirma', () async {
    final now = sampleNow;
    final database = buildSampleDatabase(now: now);
    final slot = TimeSlot(
      id: 'slot-prazo',
      roomId: SampleIds.roomPoaEstufa,
      startsAt: now.add(const Duration(days: 3)),
    );
    database.slots.add(slot);
    final groups = FakeGroupRepository(
      database,
      clock: FixedClock(now),
      latency: Duration.zero,
    );
    final created = await groups.create(
      CreateGroupRequest(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: slot.id,
        extraSpots: 3,
        minimumPlayers: 3,
        creatorUserId: 'user-faixa-host',
        creatorDisplayName: 'Host',
      ),
    );
    final opened = (created as CreateGroupSuccess).group;
    expect(opened.isConfirmed, isFalse);
    final index = database.groups.indexWhere((group) => group.id == opened.id);
    database.groups[index] = opened.copyWith(
      closesAt: now.subtract(const Duration(hours: 1)),
    );

    final missed = await groups.getById(opened.id);
    expect(missed!.isCancelled, isTrue);
    expect(missed.confirmedAt, isNull);
    expect(
      GroupRules.missedMinimum(
        alreadyCancelled: false,
        portalOwned: false,
        filledSpots: 1,
        minimumSpots: 3,
        closesAt: now.subtract(const Duration(hours: 1)),
        startsAt: opened.startsAt,
        now: now,
      ),
      isTrue,
    );
  });
}
