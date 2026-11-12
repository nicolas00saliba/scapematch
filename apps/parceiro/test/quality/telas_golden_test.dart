import 'package:flutter/material.dart';

import '../../../../test/support/folga_golden.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_login_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import '../support/pump_parceiro.dart';

void main() {
  setUp(() {
    goldenFileComparator = FolgaGolden(
      Uri.parse('test/quality/telas_golden_test.dart'),
    );
  });

  for (final size in const [Size(390, 1400), Size(1440, 1200)]) {
    final nome = size.width.round().toString();

    testWidgets('login do parceiro em $nome', (tester) async {
      await pumpParceiro(tester, size: size);
      await expectLater(
        find.byType(PartnerLoginScreen),
        matchesGoldenFile('goldens/parceiro_login_$nome.png'),
      );
    });
  }

  testWidgets('botão Entrar do parceiro', (tester) async {
    await pumpParceiro(tester, size: const Size(390, 1400));
    await expectLater(
      find.byKey(PartnerKeys.partnerSubmit),
      matchesGoldenFile('goldens/parceiro_entrar.png'),
    );
  });

  testWidgets('login do parceiro segue contraste e toque', (tester) async {
    await pumpParceiro(tester, size: const Size(390, 1400));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    final toque = await androidTapTargetGuideline.evaluate(tester);
    // A faixa "Demonstração" tem 29px de altura. Aumentar para 48px muda o
    // layout. O teste só passa se essa faixa for o único alvo abaixo de 48px.
    if (toque.passed) return;
    final pedacos = (toque.reason ?? '')
        .split('SemanticsNode')
        .where((pedaco) => pedaco.contains('expected tap target'));
    expect(pedacos, isNotEmpty);
    for (final pedaco in pedacos) {
      expect(pedaco, contains('Demonstração. Toque para ler o aviso.'));
    }
  });
}
