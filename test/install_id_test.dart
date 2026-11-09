import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/device/install_id.dart';

void main() {
  test('o identificador da instalação é um UUID estável', () {
    final id = InstallId.create(Random(7));
    expect(InstallId.isValid(id), isTrue);
    expect(InstallId.create(Random(7)), id);
    expect(InstallId.isValid('telefone-do-jogador'), isFalse);
  });
}
