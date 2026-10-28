import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('creating a group shows the current user and the new card', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        currentUserProvider.overrideWithValue(
          const CurrentUser(id: 'user-ana', displayName: 'Ana Teste'),
        ),
      ],
    );

    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.housePoaRedencao);
    await _pick(tester, 'room', SampleIds.roomPoaEstufa);
    await _pick(tester, 'slot', SampleIds.slotPoaEstufaFree);

    expect(_submitEnabled(tester), isTrue);
    await tester.tap(find.byKey(AppKeys.createSubmit));
    await tester.pumpAndSettle();

    expect(find.text('Ana Teste'), findsOneWidget);
    expect(find.text('Você'), findsNothing);
    expect(find.text('Você está neste grupo'), findsOneWidget);
    expect(find.text('1 de 3 vagas'), findsOneWidget);
    expect(find.byType(CreateGroupScreen), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupScreen), findsNothing);
    expect(find.byKey(AppKeys.createSubmit), findsNothing);

    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Estufa');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 de 3 vagas'),
      300,
      scrollable: verticalScrollable,
    );
    expect(find.text('1 de 3 vagas'), findsOneWidget);
    expect(find.text('A Estufa'), findsWidgets);
  });

  testWidgets('creating a duplicate session explains it in Portuguese', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.housePoaRedencao);
    await _pick(tester, 'room', SampleIds.roomPoaEstufa);
    await _pick(tester, 'slot', SampleIds.slotPoaEstufaTaken);

    await tester.tap(find.byKey(AppKeys.createSubmit));
    await tester.pumpAndSettle();

    final formScroll = find.descendant(
      of: find.byType(CreateGroupScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.createFailure),
      200,
      scrollable: formScroll,
    );
    expect(
      find.text(
        'Já existe um grupo nessa sala nesse horário. Escolha outro horário.',
      ),
      findsOneWidget,
    );
    expect(find.text('Você está neste grupo'), findsNothing);
    expect(find.text('Criar grupo'), findsWidgets);
  });

  testWidgets('the slot sheet lists several times for the same room', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.houseSpAugusta);
    await _pick(tester, 'room', SampleIds.roomSpMetro);
    await tester.tap(find.byKey(AppKeys.selectionField('slot')));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsAtLeastNWidgets(4));
    expect(
      find.byKey(AppKeys.option(SampleIds.slotSpMetroSun)),
      findsOneWidget,
    );
  });
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String field, String id) async {
  await tester.tap(find.byKey(AppKeys.selectionField(field)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.option(id)));
  await tester.pumpAndSettle();
}

bool _submitEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(AppKeys.createSubmit))
          .onPressed !=
      null;
}
