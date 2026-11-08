import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/scape_points_view.dart';

void main() {
  test('o extrato lê o saldo que o servidor devolve', () {
    final wallet = ScapeWallet.fromJson({
      'referral_code': 'AB12CD34',
      'available_points': 10,
      'pending_points': 4,
      'point_value_cents': 1,
      'attributed': true,
      'can_claim': false,
      'entries': [
        {'kind': 'accrual', 'program': 'c2c', 'points': 4, 'amount_cents': 4},
        {
          'kind': 'accrual',
          'program': 'cashback',
          'points': 10,
          'amount_cents': 10,
        },
        {
          'kind': 'accrual',
          'program': 'c2c',
          'points': 4,
          'amount_cents': 4,
          'review_status': 'em_revisao',
        },
      ],
    });
    expect(wallet.referralCode, 'AB12CD34');
    expect(wallet.availableCents, 10);
    expect(wallet.entries.first.title, 'Indicação de jogador');
    expect(wallet.entries[1].title, 'Cashback');
    expect(wallet.entries.last.title, 'Indicação em revisão');
    expect(formatPoints(1800), '1.800');
  });

  testWidgets('a tela mostra disponível, pendente e o código', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ScapePointsBody(preview: ScapeWallet.sample)),
      ),
    );
    expect(find.byKey(AppKeys.scapePointsBalance), findsOneWidget);
    expect(find.textContaining('disponíveis'), findsOneWidget);
    expect(find.textContaining('250 pendentes'), findsOneWidget);
    expect(find.textContaining('SCAPEDEMO'), findsOneWidget);
    expect(find.text('Cashback'), findsOneWidget);
    expect(find.text('Indicação de jogador'), findsOneWidget);
    expect(
      find.text('Números de exemplo. Nada aqui é uma carteira real.'),
      findsOneWidget,
    );
  });
}
