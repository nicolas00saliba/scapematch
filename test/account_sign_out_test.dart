import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('staying in the dialog keeps the sample session', (tester) async {
    await _openAccount(tester);
    await _scrollToSignOut(tester);
    await tester.tap(find.byKey(AppKeys.accountSignOut));
    await tester.pumpAndSettle();
    expect(find.text(AccountMessages.signOutTitle), findsOneWidget);
    expect(find.text(AccountMessages.signOutBody), findsOneWidget);

    await tester.tap(find.text(AccountMessages.signOutStay));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(AccountScreen),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(find.text('Olá, Nícolas'), findsOneWidget);
    expect(find.text(AccountMessages.signedOutTitle), findsNothing);
    final context = tester.element(find.byType(AccountScreen));
    expect(
      ProviderScope.containerOf(context).read(authSessionProvider)?.displayName,
      'Nícolas',
    );
  });

  testWidgets('sign out clears the fake session and login restores it', (
    tester,
  ) async {
    await _openAccount(tester);
    await _scrollToSignOut(tester);
    await tester.tap(find.byKey(AppKeys.accountSignOut));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();

    expect(find.text(AccountMessages.signedOutTitle), findsOneWidget);
    expect(find.text('Olá, Nícolas'), findsNothing);
    expect(find.byKey(AppKeys.accountWallet), findsNothing);
    final signedOut = tester.element(find.text(AccountMessages.signedOutTitle));
    final container = ProviderScope.containerOf(signedOut);
    expect(container.read(authSessionProvider), isNull);
    expect(container.read(authRepositoryProvider).signedInUser, isNull);

    await tester.tap(find.byKey(AppKeys.accountSignIn));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(AppKeys.loginEmail),
      'nicolas@exemplo.invalid',
    );
    await tester.enterText(find.byKey(AppKeys.loginPassword), 'senha-exemplo');
    await tester.tap(find.byKey(AppKeys.loginSubmit));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Olá, Nícolas'), findsOneWidget);
    final back = tester.element(find.text('Olá, Nícolas'));
    final restored = ProviderScope.containerOf(back);
    expect(restored.read(authSessionProvider)?.id, 'user-local');
    expect(
      restored.read(authRepositoryProvider).signedInUser?.displayName,
      'Nícolas',
    );
  });

  testWidgets('sign out fits a phone width', (tester) async {
    await _openAccount(tester, const Size(390, 844));
    await _scrollToSignOut(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(AppKeys.accountSignOut));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAccount(
  WidgetTester tester, [
  Size size = const Size(390, 844),
]) async {
  await pumpScapeMatch(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
}

Future<void> _scrollToSignOut(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byType(AccountScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    ),
  );
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.accountSignOut),
    200,
    scrollable: scrollable,
  );
  final button = find.byKey(AppKeys.accountSignOut);
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isNotEmpty &&
      tester.getCenter(button).dy >= tester.getTopLeft(bar).dy - 8) {
    await tester.drag(scrollable, const Offset(0, -160));
    await tester.pumpAndSettle();
  }
}
