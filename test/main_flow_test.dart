import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('finds a group in the chosen city, filters, and joins', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    expect(find.text('Escolha uma cidade'), findsNothing);
    expect(find.text('Curitiba'), findsWidgets);
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.groupSearch), findsOneWidget);
    expect(find.text('Criar grupo'), findsWidgets);
    expect(find.textContaining('Dados de exemplo'), findsOneWidget);

    await _selectCity(tester, SampleIds.saoPaulo);
    expect(find.text('São Paulo'), findsWidgets);

    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Augusta');
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      300,
      scrollable: verticalScrollable,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsOneWidget,
    );
    expect(find.text('Metrô Perdido'), findsWidgets);
    expect(find.text('O Cofre do Café'), findsNothing);
    // A sala entra no carrossel mesmo sem grupo na lista.
    expect(find.text('O Izakaya Secreto'), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();

    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
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
    await tester.ensureVisible(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.almostFullFilter));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
      300,
      scrollable: verticalScrollable,
    );
    expect(find.text('Cheio'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      300,
      scrollable: verticalScrollable,
    );
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Entrar no grupo'), findsOneWidget);
    expect(find.text('1 de 4 vagas'), findsOneWidget);
    expect(_joinEnabled(tester), isTrue);
  });

  testWidgets('a filled group shows Grupo cheio and blocks entry', (
    tester,
  ) async {
    final database = loadSampleDatabase();
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupSpMetroAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(filledSpots: current.totalSpots);

    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        fakeDatabaseProvider.overrideWithValue(database),
      ],
    );

    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Metrô');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpMetroAlmost)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grupo cheio'), findsOneWidget);
    expect(_spotSummary(tester), '6 de 6 vagas');
    expect(_joinEnabled(tester), isFalse);
  });

  testWidgets('changing the city changes which groups are listed', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await _selectCity(tester, SampleIds.saoPaulo);
    await tester.ensureVisible(find.byKey(AppKeys.groupSearch));
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
    final database = loadSampleDatabase();
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(sampleNow)),
        groupRepositoryProvider.overrideWithValue(
          FakeGroupRepository(
            database,
            clock: FixedClock(sampleNow),
            latency: Duration.zero,
            failList: true,
          ),
        ),
      ],
    );

    await _selectCity(tester, SampleIds.beloHorizonte);
    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Bar');
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar os grupos.'), findsOneWidget);
    expect(find.byKey(AppKeys.retry), findsOneWidget);
  });
}

Future<void> _selectCity(WidgetTester tester, String cityId) async {
  await tester.ensureVisible(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(cityId)));
  await tester.pumpAndSettle();
}

String _spotSummary(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(AppKeys.spotSummary)).data!;
}

bool _joinEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(find.byKey(AppKeys.joinButton));
  return button.onPressed != null;
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
