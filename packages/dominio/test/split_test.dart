import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('the remainder cents go to the first shares', () {
    expect(splitCents(100, 3), [34, 33, 33]);
    expect(splitCents(10, 3), [4, 3, 3]);
    expect(splitCents(1, 3), [1, 0, 0]);
    expect(splitCents(0, 4), [0, 0, 0, 0]);
    expect(splitCents(8, 1), [8]);
  });

  test('every split adds back to the total', () {
    for (var total = 0; total <= 50; total++) {
      for (var parts = 1; parts <= 9; parts++) {
        final shares = splitCents(total, parts);
        expect(shares.length, parts, reason: '$total among $parts');
        expect(shares.reduce((a, b) => a + b), total);
      }
    }
  });

  test('a split without players or with a negative total is refused', () {
    expect(() => splitCents(10, 0), throwsA(isA<PaymentException>()));
    expect(() => splitCents(-1, 2), throwsA(isA<PaymentException>()));
  });
}
