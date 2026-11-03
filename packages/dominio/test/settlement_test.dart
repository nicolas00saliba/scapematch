import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'each paid share credits the house net and the platform commission',
    () async {
      final book = _book();
      final reservation = book.createReservation(
        id: 'res-1',
        groupId: 'group-1',
        houseId: 'house-1',
        totalCents: 100,
        playerIds: const ['ana', 'bia', 'caio'],
      );

      expect(reservation.commissionBps, 1000);
      expect(reservation.grossCents, 100);
      expect(reservation.commissionCents, 10);
      expect(reservation.netCents, 90);

      for (final share in reservation.shares) {
        await book.payShare(
          reservationId: reservation.id,
          shareId: share.id,
          kind: PaymentMethodKind.pix,
          idempotencyKey: 'pay-${share.id}',
        );
      }

      final paid = book.reservation(reservation.id);
      expect(paid.status, ReservationStatus.paid);
      expect(book.houseBalance('house-1'), 90);
      expect(book.platformBalance, 10);
      expect(
        book.entries.where((entry) => entry.kind == LedgerKind.houseNet).length,
        3,
      );
      expect(
        book.entries
            .where((entry) => entry.kind == LedgerKind.commission)
            .length,
        3,
      );
    },
  );

  test('a card payment of one player uses the simulated provider', () async {
    final seen = <int>[];
    final book = PaymentBook(provider: _RecordingProvider(seen));
    final reservation = book.createReservation(
      id: 'res-card',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 200,
      playerIds: const ['ana'],
    );

    await book.payShare(
      reservationId: reservation.id,
      shareId: reservation.shares.single.id,
      kind: PaymentMethodKind.card,
      idempotencyKey: 'card-1',
    );

    expect(seen, [200]);
    expect(book.houseBalance('house-1'), 180);
    expect(book.platformBalance, 20);
  });

  test('a refund adds new ledger lines and leaves the payment lines', () async {
    final book = _book();
    final reservation = book.createReservation(
      id: 'res-2',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 100,
      playerIds: const ['ana', 'bia', 'caio'],
    );
    for (final share in reservation.shares) {
      await book.payShare(
        reservationId: reservation.id,
        shareId: share.id,
        kind: PaymentMethodKind.pix,
        idempotencyKey: 'pay-${share.id}',
      );
    }
    final beforeRefund = List<LedgerEntry>.of(book.entries);
    final firstShare = reservation.shares.first;

    await book.refundShare(
      reservationId: reservation.id,
      shareId: firstShare.id,
      idempotencyKey: 'refund-${firstShare.id}',
    );

    expect(book.entries.sublist(0, beforeRefund.length), beforeRefund);
    expect(book.entries.length, beforeRefund.length + 2);
    expect(book.entries.last.kind, LedgerKind.commissionRefund);
    expect(book.entries[book.entries.length - 2].kind, LedgerKind.houseRefund);
    expect(book.entries.last.direction, LedgerDirection.debit);
    expect(book.houseBalance('house-1'), 60);
    expect(book.platformBalance, 6);
    expect(
      book.reservation(reservation.id).shares.first.status,
      ShareStatus.refunded,
    );
    expect(book.reservation(reservation.id).status, ReservationStatus.partial);

    await book.refundShare(
      reservationId: reservation.id,
      shareId: reservation.shares[1].id,
      idempotencyKey: 'refund-b',
    );
    await book.refundShare(
      reservationId: reservation.id,
      shareId: reservation.shares[2].id,
      idempotencyKey: 'refund-c',
    );
    expect(book.houseBalance('house-1'), 0);
    expect(book.platformBalance, 0);
    expect(book.reservation(reservation.id).status, ReservationStatus.refunded);
  });

  test(
    'changing the stored rate does not rewrite an open reservation',
    () async {
      final book = _book();
      final first = book.createReservation(
        id: 'res-old',
        groupId: 'group-1',
        houseId: 'house-1',
        totalCents: 100,
        playerIds: const ['ana'],
      );

      final audit = book.settings.setPlatformCommission(
        actorId: 'nico',
        role: PlatformRole.platformAdmin,
        commissionBps: 2000,
        at: DateTime.utc(2026, 11, 3),
      );

      final again = book.reservation(first.id);
      expect(again.commissionBps, 1000);
      expect(again.commissionCents, 10);
      expect(again.netCents, 90);
      expect(audit.beforeBps, 1000);
      expect(audit.afterBps, 2000);
      expect(audit.action, 'set_platform_commission');
      expect(audit.houseId, isNull);
      expect(book.audit, [audit]);

      final second = book.createReservation(
        id: 'res-new',
        groupId: 'group-2',
        houseId: 'house-1',
        totalCents: 100,
        playerIds: const ['bia'],
      );
      expect(second.commissionBps, 2000);
      expect(second.commissionCents, 20);
      expect(second.netCents, 80);
      expect(book.reservation(first.id).commissionBps, 1000);
    },
  );

  test('a house override is snapshotted and the other houses stay on the platform rate', () {
    final book = _book();
    book.settings.setHouseCommission(
      actorId: 'nico',
      role: PlatformRole.platformAdmin,
      houseId: 'house-a',
      commissionBps: 2500,
      at: DateTime.utc(2026, 11, 3),
    );
    final pinned = book.createReservation(
      id: 'res-a',
      groupId: 'group-a',
      houseId: 'house-a',
      totalCents: 100,
      playerIds: const ['ana'],
    );
    final other = book.createReservation(
      id: 'res-b',
      groupId: 'group-b',
      houseId: 'house-b',
      totalCents: 100,
      playerIds: const ['bia'],
    );

    book.settings.setPlatformCommission(
      actorId: 'nico',
      role: PlatformRole.platformAdmin,
      commissionBps: 500,
      at: DateTime.utc(2026, 11, 3, 1),
    );

    expect(pinned.commissionBps, 2500);
    expect(book.reservation(pinned.id).commissionCents, 25);
    expect(other.commissionBps, 1000);
    expect(book.reservation(other.id).commissionCents, 10);
    expect(book.settings.rateFor('house-a'), 2500);
    expect(book.settings.rateFor('house-b'), 500);
    expect(book.audit.first.action, 'set_house_commission');
    expect(book.audit.first.houseId, 'house-a');
    expect(book.audit, hasLength(2));
  });

  test('only a platform admin can change the rate', () {
    final book = _book();
    for (final role in [PlatformRole.player, PlatformRole.houseStaff]) {
      expect(
        () => book.settings.setPlatformCommission(
          actorId: 'someone',
          role: role,
          commissionBps: 500,
          at: DateTime.utc(2026, 11, 3),
        ),
        throwsA(isA<PlatformPermissionException>()),
      );
      expect(
        () => book.settings.setHouseCommission(
          actorId: 'someone',
          role: role,
          houseId: 'house-1',
          commissionBps: 500,
          at: DateTime.utc(2026, 11, 3),
        ),
        throwsA(isA<PlatformPermissionException>()),
      );
    }
    expect(book.settings.rateFor('house-1'), 1000);
    expect(book.audit, isEmpty);
  });

  test('the same payment key does not write the ledger twice', () async {
    final book = _book();
    final reservation = book.createReservation(
      id: 'res-key',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 100,
      playerIds: const ['ana', 'bia'],
    );
    final share = reservation.shares.first;
    await book.payShare(
      reservationId: reservation.id,
      shareId: share.id,
      kind: PaymentMethodKind.pix,
      idempotencyKey: 'same-key',
    );
    await book.payShare(
      reservationId: reservation.id,
      shareId: share.id,
      kind: PaymentMethodKind.pix,
      idempotencyKey: 'same-key',
    );

    expect(book.entries.length, 2);
    expect(book.houseBalance('house-1'), share.netCents);
    expect(
      () => book.payShare(
        reservationId: reservation.id,
        shareId: reservation.shares[1].id,
        kind: PaymentMethodKind.pix,
        idempotencyKey: 'same-key',
      ),
      throwsA(isA<IdempotencyConflictException>()),
    );
    expect(book.houseBalance('house-1'), share.netCents);
  });

  test(
    'a failed charge writes no ledger and a new key can try again',
    () async {
      final provider = _FailingProvider();
      final book = PaymentBook(provider: provider);
      final reservation = book.createReservation(
        id: 'res-fail',
        groupId: 'group-1',
        houseId: 'house-1',
        totalCents: 80,
        playerIds: const ['ana'],
      );
      final shareId = reservation.shares.single.id;

      await book.payShare(
        reservationId: reservation.id,
        shareId: shareId,
        kind: PaymentMethodKind.card,
        idempotencyKey: 'try-1',
      );
      expect(
        book.reservation(reservation.id).shares.single.status,
        ShareStatus.failed,
      );
      expect(book.entries, isEmpty);
      expect(book.houseBalance('house-1'), 0);

      provider.failCharges = false;
      await book.payShare(
        reservationId: reservation.id,
        shareId: shareId,
        kind: PaymentMethodKind.card,
        idempotencyKey: 'try-2',
      );
      expect(book.reservation(reservation.id).status, ReservationStatus.paid);
      expect(book.houseBalance('house-1'), 72);
      expect(book.platformBalance, 8);
    },
  );

  test(
    'the simulated provider returns the same charge for the same key',
    () async {
      final provider = SimulatedPaymentProvider();
      final first = await provider.chargeShare(
        shareId: 'share-1',
        amountCents: 10,
        kind: PaymentMethodKind.pix,
        idempotencyKey: 'key-1',
      );
      final second = await provider.chargeShare(
        shareId: 'share-1',
        amountCents: 10,
        kind: PaymentMethodKind.pix,
        idempotencyKey: 'key-1',
      );

      expect(first.succeeded, isTrue);
      expect(first.provider, SimulatedPaymentProvider.name);
      expect(second.providerRef, first.providerRef);
      expect(
        () => provider.chargeShare(
          shareId: 'share-1',
          amountCents: 11,
          kind: PaymentMethodKind.pix,
          idempotencyKey: 'key-1',
        ),
        throwsA(isA<IdempotencyConflictException>()),
      );
    },
  );

  test('a player who joins later gets a share at the snapshotted rate', () {
    final book = _book();
    final first = book.createReservation(
      id: 'res-grow',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 100,
      playerIds: const ['ana'],
    );
    book.settings.setPlatformCommission(
      actorId: 'nico',
      role: PlatformRole.platformAdmin,
      commissionBps: 5000,
      at: DateTime.utc(2026, 11, 3),
    );

    final grown = book.addShare(
      reservationId: first.id,
      playerId: 'bia',
      amountCents: 100,
    );

    expect(grown.shares.first.commissionCents, 10);
    expect(grown.shares.last.playerId, 'bia');
    expect(grown.shares.last.amountCents, 100);
    expect(grown.shares.last.commissionCents, 10);
    expect(grown.shares.last.netCents, 90);
    expect(grown.commissionBps, 1000);
    expect(
      book
          .addShare(reservationId: first.id, playerId: 'bia', amountCents: 100)
          .shares
          .length,
      2,
    );
  });

  test('an unpaid share cannot be refunded', () async {
    final book = _book();
    final reservation = book.createReservation(
      id: 'res-open',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 50,
      playerIds: const ['ana'],
    );
    expect(
      () => book.refundShare(
        reservationId: reservation.id,
        shareId: reservation.shares.single.id,
        idempotencyKey: 'too-soon',
      ),
      throwsA(isA<PaymentException>()),
    );
    expect(book.entries, isEmpty);
  });
}

PaymentBook _book() {
  return PaymentBook(provider: SimulatedPaymentProvider());
}

class _RecordingProvider implements PaymentProvider {
  _RecordingProvider(this.amounts);

  final List<int> amounts;

  @override
  Future<ChargeResult> chargeShare({
    required String shareId,
    required int amountCents,
    required PaymentMethodKind kind,
    required String idempotencyKey,
  }) async {
    amounts.add(amountCents);
    return ChargeResult(
      provider: 'recording',
      providerRef: idempotencyKey,
      succeeded: true,
      amountCents: amountCents,
    );
  }

  @override
  Future<ChargeResult> refund({
    required String chargeId,
    required int amountCents,
    required String idempotencyKey,
  }) async {
    return ChargeResult(
      provider: 'recording',
      providerRef: idempotencyKey,
      succeeded: true,
      amountCents: amountCents,
    );
  }
}

class _FailingProvider implements PaymentProvider {
  var failCharges = true;

  @override
  Future<ChargeResult> chargeShare({
    required String shareId,
    required int amountCents,
    required PaymentMethodKind kind,
    required String idempotencyKey,
  }) async {
    return ChargeResult(
      provider: 'failing',
      providerRef: idempotencyKey,
      succeeded: !failCharges,
      amountCents: amountCents,
    );
  }

  @override
  Future<ChargeResult> refund({
    required String chargeId,
    required int amountCents,
    required String idempotencyKey,
  }) async {
    return ChargeResult(
      provider: 'failing',
      providerRef: idempotencyKey,
      succeeded: true,
      amountCents: amountCents,
    );
  }
}
