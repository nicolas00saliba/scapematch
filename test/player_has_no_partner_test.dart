import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the phone account has no partner entry', (tester) async {
    await _openAccount(tester, const Size(390, 844));
  });

  testWidgets('the desktop account menu has no partner entry', (tester) async {
    await _openAccount(tester, const Size(1440, 900));
  });

  testWidgets('an old /parceiro address does not open the house', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/parceiro');
    await tester.pumpAndSettle();
    expect(find.text('Entrar como casa'), findsNothing);
    expect(find.text('EscapeMatch Parceiro'), findsNothing);
    expect(find.text('xv@scapematch.exemplo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAccount(WidgetTester tester, Size size) async {
  await pumpScapeMatch(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  expect(find.text('Conta'), findsWidgets);
  expect(find.text('EscapeMatch Parceiro'), findsNothing);
  expect(find.text('xv@scapematch.exemplo'), findsNothing);
  expect(find.byKey(const Key('partner-entry')), findsNothing);
  expect(find.text('Meus parceiros de jogo'), findsOneWidget);
}
