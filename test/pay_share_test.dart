import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('joining leaves the share pending until the person pays', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _open(tester);

    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.payMyShare), findsOneWidget);
    expect(find.textContaining('Pagar minha parte (R\$'), findsOneWidget);
    expect(find.text('Pendente'), findsWidgets);
    expect(find.text('Reservado'), findsWidgets);
    expect(find.text('Pago'), findsNothing);
    expect(find.textContaining('de '), findsWidgets);
    expect(find.textContaining('comissão'), findsNothing);
    expect(find.textContaining('10%'), findsNothing);
    expect(find.textContaining(GroupMessages.chargeOnlyIfCloses), findsWidgets);

    await tester.tap(find.byKey(AppKeys.payMyShare));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.payMethodPix), findsOneWidget);
    expect(find.byKey(AppKeys.playerCpf), findsNothing);
    expect(find.text(GroupMessages.simulatedPixNotice), findsOneWidget);
    expect(find.text(GroupMessages.simulatePayment), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.payMethodCard));
    await tester.pumpAndSettle();
    expect(find.text('Nome no cartão'), findsOneWidget);
    expect(find.text('CPF do titular'), findsNothing);
    expect(find.text('O cartão é meu'), findsNothing);
    expect(find.textContaining('Cartão de teste'), findsOneWidget);
    expect(find.textContaining('4242'), findsOneWidget);
    expect(find.textContaining('CVV'), findsNothing);
    expect(find.textContaining('Código de segurança'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.payMethodPix));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.paySimulate));
    await tester.pumpAndSettle();
    expect(find.text('Valor reservado'), findsOneWidget);
    expect(find.byKey(AppKeys.payConfirmed), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.payDone));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.payMyShare), findsNothing);
    expect(find.text(GroupMessages.yourShareReserved), findsOneWidget);
    expect(find.text('Pendente'), findsNothing);
  });

  testWidgets('a card payment uses the test card and stays simulated', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _open(tester);
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payMyShare));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payMethodCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.payTestCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.paySimulate));
    await tester.pumpAndSettle();
    expect(find.text('Valor reservado'), findsOneWidget);
    expect(find.text(GroupMessages.simulatedNotice), findsOneWidget);
  });
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AppKeys.groupSearch), 'Cobertura');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    300,
    scrollable: verticalScrollable,
  );
  await tester.tap(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
  );
  await tester.pumpAndSettle();
}
