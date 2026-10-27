import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('finds a group in the chosen city, filters, and joins', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    expect(find.text('Escolha uma cidade'), findsOneWidget);
    expect(find.text('Curitiba'), findsNothing);
    expect(find.text('Encontrar grupo'), findsOneWidget);
    expect(find.text('Criar grupo'), findsOneWidget);
    expect(find.textContaining('Dados de exemplo'), findsOneWidget);

    await _selectCity(tester, SampleIds.saoPaulo);
    expect(find.text('São Paulo'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.findGroup));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroOpen)),
      300,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroOpen)),
      findsOneWidget,
    );
    expect(find.text('O Cofre do Café'), findsNothing);

    await tester.tap(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpIzakayaAlmost)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroOpen)),
      findsNothing,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaFull)),
      findsNothing,
    );

    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrar no grupo'), findsOneWidget);
    expect(_spotSummary(tester), '5 de 6 vagas');

    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();

    expect(_spotSummary(tester), '6 de 6 vagas');
    expect(find.text('Você está neste grupo'), findsOneWidget);
    expect(find.text('Entrar no grupo'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaFull)),
      300,
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaFull)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grupo cheio'), findsOneWidget);
    final joinButton = tester.widget<FilledButton>(
      find.byKey(AppKeys.joinButton),
    );
    expect(joinButton.onPressed, isNull);
  });

  testWidgets('changing the city changes which groups are listed', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.tap(find.byKey(AppKeys.findGroup));
    await tester.pumpAndSettle();
    expect(find.text('Metrô Perdido'), findsWidgets);
    expect(find.text('O Cofre do Café'), findsNothing);

    await _selectCity(tester, SampleIds.curitiba);
    expect(find.text('O Cofre do Café'), findsWidgets);
    expect(find.text('Metrô Perdido'), findsNothing);

    await _selectCity(tester, SampleIds.rioDeJaneiro);
    expect(find.text('O Apartamento da Avenida'), findsWidgets);
    expect(find.text('Metrô Perdido'), findsNothing);
    expect(find.text('O Cofre do Café'), findsNothing);
  });

  testWidgets('create group blocks a size above the room capacity', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.selectionField('house')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.houseSpAugusta)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.selectionField('room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.roomSpMetro)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppKeys.selectionField('slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.slotSpMetroSun)));
    await tester.pumpAndSettle();

    expect(find.textContaining('até 6 pessoas'), findsOneWidget);
    expect(_submitEnabled(tester), isTrue);

    final formScroll = find.descendant(
      of: find.byType(CreateGroupScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.extraSpotsIncrement),
      200,
      scrollable: formScroll,
    );
    for (var tap = 0; tap < 3; tap++) {
      await tester.tap(find.byKey(AppKeys.extraSpotsIncrement));
      await tester.pump();
    }

    expect(find.byKey(AppKeys.extraSpotsValue), findsOneWidget);
    expect(_extraSpots(tester), '5');
    expect(
      tester
          .widget<IconButton>(find.byKey(AppKeys.extraSpotsIncrement))
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.selectionField('room')),
      -200,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(AppKeys.selectionField('room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.roomSpCobertura)));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.capacityError),
      200,
      scrollable: formScroll,
    );
    expect(find.textContaining('ultrapassa a capacidade'), findsOneWidget);
    expect(_submitEnabled(tester), isFalse);

    await tester.tap(find.byKey(AppKeys.extraSpotsDecrement));
    await tester.pump();

    expect(_extraSpots(tester), '3');
    expect(find.byKey(AppKeys.capacityError), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.selectionField('slot')),
      -200,
      scrollable: formScroll,
    );
    await tester.tap(find.byKey(AppKeys.selectionField('slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.option(SampleIds.slotSpCoberturaFri)));
    await tester.pumpAndSettle();

    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('shows an error with retry when the group list fails', (
    tester,
  ) async {
    final database = buildSampleDatabase();
    await pumpScapeMatch(
      tester,
      overrides: [
        groupRepositoryProvider.overrideWithValue(
          FakeGroupRepository(database, latency: Duration.zero, failList: true),
        ),
      ],
    );

    await _selectCity(tester, SampleIds.beloHorizonte);
    await tester.tap(find.byKey(AppKeys.findGroup));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar os grupos.'), findsOneWidget);
    expect(find.byKey(AppKeys.retry), findsOneWidget);
  });
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

String _spotSummary(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(AppKeys.spotSummary)).data!;
}

bool _submitEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(AppKeys.createSubmit))
          .onPressed !=
      null;
}

String _extraSpots(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(AppKeys.extraSpotsValue)).data!;
}
