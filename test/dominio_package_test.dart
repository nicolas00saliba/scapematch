import 'package:dominio/dominio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app reads the domain package and its opening commission', () {
    expect(PlatformSettings.openingCommissionBps, 1000);
    final book = PaymentBook(provider: SimulatedPaymentProvider());
    expect(book.settings.rateFor('casa'), 1000);

    final reservation = book.createReservation(
      id: 'res-app',
      groupId: 'grupo',
      houseId: 'casa',
      totalCents: 100,
      playerIds: const ['ana'],
    );
    expect(reservation.commissionCents, 10);
    expect(reservation.netCents, 90);
  });
}
