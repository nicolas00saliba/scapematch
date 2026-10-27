import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('a group created after opening Meus grupos shows up there', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum grupo marcado'), findsOneWidget);
    expect(find.text('A Estufa'), findsNothing);

    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();

    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.housePoaRedencao);
    await _pick(tester, 'room', SampleIds.roomPoaEstufa);
    await _pick(tester, 'slot', SampleIds.slotPoaEstufaFree);
    await tester.tap(find.byKey(AppKeys.createSubmit));
    await tester.pumpAndSettle();

    expect(find.text('A Estufa'), findsWidgets);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum grupo marcado'), findsNothing);
    expect(find.text('A Estufa'), findsOneWidget);
    expect(find.text('Próximos'), findsOneWidget);
  });

  testWidgets('joining and leaving refresh the Meus grupos tab', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum grupo marcado'), findsOneWidget);
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsNothing,
    );

    await tester.tap(find.byKey(AppKeys.homeTab));
    await tester.pumpAndSettle();
    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      300,
      scrollable: verticalScrollable,
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsOneWidget,
    );
    expect(find.text('Cobertura da Paulista'), findsOneWidget);
    expect(find.text('Nenhum grupo marcado'), findsNothing);

    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.leaveGroup));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reembolsado'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // A aba retoma a escuta ao voltar e espera o repositório (280 ms).
    // Sem animação, pumpAndSettle encerra antes disso.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsNothing,
    );
    await tester.tap(find.text('Cancelados'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsOneWidget,
    );
    expect(find.textContaining('Reembolsado'), findsWidgets);
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
