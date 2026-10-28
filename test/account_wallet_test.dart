import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/wallet/presentation/add_balance_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the account list order drops the gift card and adds cards', (
    tester,
  ) async {
    await _openAccount(tester, const Size(390, 844));

    const titles = <String>[
      'Perfil',
      'Meus parceiros de jogo',
      'Indique e ganhe',
      'Cartões cadastrados',
      'Ajuda',
    ];
    final scrollable = find.descendant(
      of: find.byType(AccountScreen),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    Finder? previous;
    for (final title in titles) {
      final current = find.text(title);
      await tester.scrollUntilVisible(current, 120, scrollable: scrollable);
      if (previous != null && previous.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(previous).dy,
          lessThan(tester.getTopLeft(current).dy),
          reason: title,
        );
      }
      if (title == 'Cartões cadastrados') {
        expect(find.text('Formas de pagamento da sua conta'), findsOneWidget);
      }
      previous = current;
    }
    expect(find.text('Resgatar vale-presente'), findsNothing);
    expect(tester.takeException(), isNull);

    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('40,00'), findsWidgets);
    final wallet = tester.getRect(find.byKey(AppKeys.accountWallet));
    final button = tester.getRect(find.byKey(AppKeys.accountAddBalance));
    expect(button.top, greaterThan(wallet.top));
    expect(button.bottom, lessThanOrEqualTo(wallet.bottom + 1));
    expect(button.left, greaterThanOrEqualTo(wallet.left));
    expect(button.right, lessThanOrEqualTo(wallet.right + 1));
    final style = tester
        .widget<FilledButton>(find.byKey(AppKeys.accountAddBalance))
        .style;
    expect(style?.backgroundColor?.resolve({}), Colors.white);
    expect(style?.foregroundColor?.resolve({}), isNot(Colors.white));
  });

  testWidgets('account, cards and top-up fit a phone and a wide window', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      await _openAccount(tester, size);
      expect(tester.takeException(), isNull, reason: '$size account');
      await tester.tap(find.byKey(AppKeys.accountDestination('cards')));
      await tester.pumpAndSettle();
      expect(find.text('Nenhum cartão cadastrado'), findsOneWidget);
      expect(find.byKey(AppKeys.addCard), findsOneWidget);
      expect(find.textContaining('número'), findsNothing);
      await tester.tap(find.byKey(AppKeys.addCard));
      await tester.pumpAndSettle();
      expect(find.byKey(AppKeys.addCardNotice), findsOneWidget);
      expect(find.textContaining('não pede número'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull, reason: '$size cards');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.accountAddBalance));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar saldo'), findsWidgets);
      expect(find.text(formatPrice(2000)), findsOneWidget);
      expect(find.text(formatPrice(5000)), findsOneWidget);
      expect(find.text(formatPrice(10000)), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.byKey(AppKeys.payWithCard)).enabled,
        isFalse,
      );
      expect(
        tester.widget<ListTile>(find.byKey(AppKeys.payWithPix)).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(AppKeys.addBalanceConfirm))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(AppKeys.topUpAmount(5000)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.topUpOtherAmount));
      await tester.pumpAndSettle();
      expect(find.text('Outro valor (R\$)'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(AppKeys.addBalanceConfirm))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull, reason: '$size top-up');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('40,00'), findsWidgets);
    }
  });
}

Future<void> _openAccount(WidgetTester tester, Size size) async {
  await pumpScapeMatch(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  expect(find.byType(AccountScreen), findsOneWidget);
  expect(find.byType(AddBalanceScreen), findsNothing);
}
