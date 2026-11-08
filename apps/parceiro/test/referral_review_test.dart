import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch_parceiro/features/partner/presentation/scape_liability_panel.dart';

void main() {
  test('a revisão lê o lançamento em conferência', () {
    final review = ReferralReview.fromJson({
      'id': 'rev-1',
      'entry_kind': 'points',
      'program': 'c2c',
      'points': 250,
      'amount_cents': 250,
    });
    expect(review.label, 'Indicação de jogador');
    expect(review.entryKind, 'points');
  });

  testWidgets('o admin aprova ou recusa a indicação em revisão', (
    tester,
  ) async {
    final decisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferralReviewList(
            reviews: const [
              ReferralReview(
                id: 'rev-1',
                entryKind: 'points',
                program: 'c2c',
                points: 250,
                amountCents: 250,
              ),
            ],
            onDecide: (review, decision) async {
              decisions.add('${review.id}:$decision');
            },
          ),
        ),
      ),
    );
    expect(find.text('Em revisão'), findsOneWidget);
    expect(find.text('Indicação de jogador'), findsOneWidget);
    await tester.tap(find.text('Aprovar'));
    await tester.pump();
    await tester.tap(find.text('Recusar'));
    await tester.pump();
    expect(decisions, ['rev-1:approve', 'rev-1:reject']);
  });
}
