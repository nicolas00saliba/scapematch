import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('half a cent of commission rounds up', () {
    // 50 centavos a 15% = 7,5 centavos. O meio sobe para 8.
    expect(commissionCents(50, 1500), 8);
    // 4 centavos a 10% = 0,4. Fica 0.
    expect(commissionCents(4, 1000), 0);
    // 5 centavos a 10% = 0,5. Sobe para 1.
    expect(commissionCents(5, 1000), 1);
  });

  test('the rate is an argument, and the opening rate is 25 percent', () {
    expect(commissionCents(10000, 0), 0);
    expect(commissionCents(10000, 1000), 1000);
    expect(commissionCents(10000, PlatformSettings.openingCommissionBps), 2500);
    expect(commissionCents(10000, 1234), 1234);
    expect(commissionCents(10000, 10000), 10000);
    expect(commissionCents(100000000, 1000), 10000000);
  });

  test('a rate outside 0 to 10000 is refused', () {
    expect(() => commissionCents(100, -1), throwsA(isA<PaymentException>()));
    expect(() => commissionCents(100, 10001), throwsA(isA<PaymentException>()));
  });

  test('share quotes keep the total, the commission and the house net', () {
    final quotes = quoteShares(
      totalCents: 100,
      playerCount: 3,
      commissionBps: 1000,
    );

    expect(quotes.map((quote) => quote.amountCents), [34, 33, 33]);
    expect(quotes.map((quote) => quote.commissionCents), [4, 3, 3]);
    expect(quotes.map((quote) => quote.netCents), [30, 30, 30]);
    expect(_sum(quotes, (quote) => quote.amountCents), 100);
    expect(_sum(quotes, (quote) => quote.commissionCents), 10);
    expect(_sum(quotes, (quote) => quote.netCents), 90);
  });

  test('quotes stay exact across totals, players and rates', () {
    const rates = [0, 1, 500, 1000, 3333, 5000, 9999, 10000];
    for (var total = 0; total <= 80; total++) {
      for (var players = 1; players <= 7; players++) {
        for (final rate in rates) {
          final quotes = quoteShares(
            totalCents: total,
            playerCount: players,
            commissionBps: rate,
          );
          final reason = '$total / $players @ $rate';
          expect(
            _sum(quotes, (quote) => quote.amountCents),
            total,
            reason: reason,
          );
          expect(
            _sum(quotes, (quote) => quote.commissionCents),
            commissionCents(total, rate),
            reason: reason,
          );
          expect(
            _sum(quotes, (quote) => quote.netCents),
            total - commissionCents(total, rate),
            reason: reason,
          );
          for (final quote in quotes) {
            expect(quote.commissionCents + quote.netCents, quote.amountCents);
            expect(quote.netCents, greaterThanOrEqualTo(0));
          }
        }
      }
    }
  });
}

int _sum(List<ShareQuote> quotes, int Function(ShareQuote quote) pick) {
  return quotes.fold(0, (sum, quote) => sum + pick(quote));
}
