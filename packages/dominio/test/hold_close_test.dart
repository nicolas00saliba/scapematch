import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('reserving a share does not pay the house until the group closes', () async {
    final book = _book();
    final reservation = _open(book);
    await _reserveAll(book, reservation);

    expect(book.reservation(reservation.id).status, ReservationStatus.held);
    expect(book.entries, isEmpty);
    expect(book.houseBalance('house-1'), 0);

    await book.captureReservation(
      reservationId: reservation.id,
      idempotencyKey: 'capture-close',
    );

    expect(book.reservation(reservation.id).status, ReservationStatus.paid);
    expect(book.houseBalance('house-1'), 90);
    expect(book.platformBalance, 10);
  });

  test('a group that does not close releases every hold', () async {
    final book = _book();
    final reservation = _open(book);
    await _reserveAll(book, reservation);

    final released = await book.releaseReservation(
      reservationId: reservation.id,
      idempotencyKey: 'release-deadline',
    );

    expect(released.status, ReservationStatus.released);
    expect(
      released.shares.every((share) => share.status == ShareStatus.released),
      isTrue,
    );
    expect(book.entries, isEmpty);
    expect(book.houseBalance('house-1'), 0);
  });

  test('closing with fewer people keeps each per-person share', () async {
    expect(
      canCloseWithFewer(seated: 3, roomMinimum: 2, planned: 5),
      isTrue,
    );
    expect(
      canCloseWithFewer(seated: 1, roomMinimum: 2, planned: 5),
      isFalse,
    );
    expect(
      () => requireCloseWithFewer(seated: 1, roomMinimum: 2, planned: 5),
      throwsA(
        isA<PaymentException>().having(
          (error) => error.message,
          'message',
          'Mínimo da sala: 2',
        ),
      ),
    );

    final book = _book();
    final reservation = book.createReservation(
      id: 'res-people',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 300,
      playerIds: const ['ana', 'bia', 'caio'],
    );
    await _reserveAll(book, reservation);
    final before = [
      for (final share in book.reservation(reservation.id).shares)
        share.amountCents,
    ];

    await book.captureReservation(
      reservationId: reservation.id,
      idempotencyKey: 'capture-fewer',
    );

    expect(
      book.reservation(reservation.id).shares.map((share) => share.amountCents),
      before,
    );
    expect(book.houseBalance('house-1'), 270);
  });

  test('a fixed group price waits for confirmation before capture', () async {
    final book = _book();
    final reservation = book.createReservation(
      id: 'res-fixed',
      groupId: 'group-1',
      houseId: 'house-1',
      totalCents: 300,
      playerIds: const ['ana', 'bia', 'caio'],
      priceMode: PriceMode.fixedGroup,
    );
    await _reserveAll(book, reservation);

    final repriced = book.repriceFixedClose(
      reservationId: reservation.id,
      playerIds: const ['ana', 'bia'],
      roomMinimum: 2,
      planned: 3,
    );
    final ana = repriced.shares.first;
    expect(ana.status, ShareStatus.awaitingConfirmation);
    expect(ana.proposedAmountCents, 150);
    expect(
      () => book.captureReservation(
        reservationId: reservation.id,
        idempotencyKey: 'too-soon',
      ),
      throwsA(isA<PaymentException>()),
    );
    expect(book.entries, isEmpty);

    book.confirmAdjustedShare(reservationId: reservation.id, shareId: ana.id);
    final bia = book.reservation(reservation.id).shares[1];
    book.confirmAdjustedShare(reservationId: reservation.id, shareId: bia.id);
    await book.captureReservation(
      reservationId: reservation.id,
      idempotencyKey: 'capture-fixed',
      onlyPlayerIds: const ['ana', 'bia'],
    );

    final closed = book.reservation(reservation.id);
    expect(closed.shares[0].status, ShareStatus.paid);
    expect(closed.shares[0].amountCents, 150);
    expect(closed.shares[1].amountCents, 150);
    expect(closed.shares[2].status, ShareStatus.reserved);
    expect(book.houseBalance('house-1'), 270);
  });

  test('the host can delete until two hours before the start', () {
    final start = DateTime.utc(2026, 11, 7, 18);
    expect(
      canDeleteGroup(startsAt: start, now: start.subtract(const Duration(hours: 2))),
      isTrue,
    );
    expect(
      canDeleteGroup(
        startsAt: start,
        now: start.subtract(const Duration(hours: 2, minutes: -1)),
      ),
      isFalse,
    );
  });

  test('the first absence warns and the third blocks', () {
    final book = AbsenceBook();
    expect(
      book.markAbsent(playerId: 'ana', groupId: 'g1', houseId: 'house'),
      AbsenceStanding.warned,
    );
    book.markAbsent(playerId: 'ana', groupId: 'g1', houseId: 'house');
    expect(book.countOf('ana'), 1);

    book.markAbsent(playerId: 'ana', groupId: 'g2', houseId: 'house');
    expect(book.standingOf('ana'), AbsenceStanding.warned);
    book.markAbsent(playerId: 'ana', groupId: 'g3', houseId: 'house');
    expect(book.standingOf('ana'), AbsenceStanding.blocked);

    final softer = AbsenceBook(
      policy: AbsencePolicy(warningAt: 2, blockAt: 4),
    );
    softer.markAbsent(playerId: 'bia', groupId: 'g1', houseId: 'house');
    expect(softer.standingOf('bia'), AbsenceStanding.clear);
    softer.markAbsent(playerId: 'bia', groupId: 'g2', houseId: 'house');
    expect(softer.standingOf('bia'), AbsenceStanding.warned);
  });
}

PaymentBook _book() => PaymentBook(provider: SimulatedPaymentProvider());

Reservation _open(PaymentBook book) {
  return book.createReservation(
    id: 'res-1',
    groupId: 'group-1',
    houseId: 'house-1',
    totalCents: 100,
    playerIds: const ['ana', 'bia', 'caio'],
  );
}

Future<void> _reserveAll(PaymentBook book, Reservation reservation) async {
  for (final share in reservation.shares) {
    await book.payShare(
      reservationId: reservation.id,
      shareId: share.id,
      kind: PaymentMethodKind.pix,
      idempotencyKey: 'pay-${share.id}',
    );
  }
}
