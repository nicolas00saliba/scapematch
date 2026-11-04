import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  test('a comissão de 10% deixa 90% com a casa', () {
    expect(houseSplitPercent(1000), 90);
    expect(houseSplitPercent(0), 100);
    expect(houseSplitPercent(1500), 85);
    expect(houseSplitPercent(10000), 0);
  });

  test('comissão inválida não vira split', () {
    expect(() => houseSplitPercent(-1), throwsArgumentError);
    expect(() => houseSplitPercent(10001), throwsArgumentError);
  });
}