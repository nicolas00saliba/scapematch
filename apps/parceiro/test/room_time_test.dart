import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/room_time_gateway.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_ranking_screen.dart';

void main() {
  testWidgets('lançar tempo valida o cronômetro e o nome', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RoomTimeDraft? saved;
    await tester.pumpWidget(
      _app(
        RoomTimeLaunchForm(
          durationMinutes: 60,
          initialName: 'Os Ninjas',
          members: const [
            RoomTimeMemberDraft(userId: 'ana', label: 'Ana'),
            RoomTimeMemberDraft(userId: 'bruno', label: 'Bruno'),
          ],
          onSubmit: (draft) async {
            saved = draft;
            return null;
          },
        ),
      ),
    );
    expect(find.text('Lançar tempo'), findsWidgets);
    expect(find.text('Ana'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('partner-time-name')), 'porra');
    await tester.enterText(find.byKey(const Key('partner-time-minutes')), '38');
    await tester.enterText(find.byKey(const Key('partner-time-seconds')), '12');
    await tester.tap(find.byKey(const Key('partner-time-submit')));
    await tester.pump();
    expect(find.text('Escolha outro nome para o grupo.'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(find.byKey(const Key('partner-time-name')), 'Os Ninjas');
    await tester.enterText(find.byKey(const Key('partner-time-minutes')), '70');
    await tester.tap(find.byKey(const Key('partner-time-submit')));
    await tester.pump();
    expect(
      find.text('O tempo fica entre 1 segundo e a duração da sala.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('partner-time-minutes')), '38');
    await tester.tap(find.byKey(const Key('partner-time-submit')));
    await tester.pump();
    expect(saved?.elapsedSeconds, 38 * 60 + 12);
    expect(saved?.escaped, isTrue);
    expect(saved?.groupName, 'Os Ninjas');
    expect(saved?.members.map((member) => member.label), ['Ana', 'Bruno']);
  });

  testWidgets('o ranking completo separa quem não escapou', (tester) async {
    final lines = _house();
    await tester.pumpWidget(
      _app(
        RoomTimeHousePanel(
          lines: lines,
          showPublic: true,
          showMembers: false,
          onShowPublic: (_) {},
          onShowMembers: (_) {},
          onRemove: (_) async {},
          onEdit: (_, _) async => null,
        ),
      ),
    );
    expect(find.text('Ranking completo'), findsOneWidget);
    expect(find.text('Mostrar o ranking público da sala'), findsOneWidget);
    expect(find.text('Mostrar os integrantes'), findsOneWidget);
    expect(find.text('Não escaparam'), findsOneWidget);
    expect(find.text('Quase'), findsOneWidget);
    expect(find.text('Remover'), findsNWidgets(lines.length));
    expect(find.text('Editar'), findsNWidgets(lines.length));
    await tester.tap(find.byKey(const Key('partner-time-edit-t1')));
    await tester.pump();
    expect(find.text('Editar tempo'), findsOneWidget);
    expect(find.text('38'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byKey(const Key('partner-ranking-off')), findsNothing);
  });

  testWidgets('corrigir nome não é o mesmo que editar o tempo', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? corrected;
    await tester.pumpWidget(
      _app(
        RoomTimeHousePanel(
          lines: [
            RoomTimeLine(
              entryId: 't1',
              groupId: 'g1',
              place: 1,
              groupName: 'Os Ninjas',
              elapsedSeconds: 38 * 60 + 12,
              remainingSeconds: 21 * 60 + 48,
              playedOn: DateTime(2026, 11, 2),
              members: const ['Ana'],
              escaped: true,
              nameChosen: true,
            ),
          ],
          showPublic: true,
          showMembers: true,
          onShowPublic: (_) {},
          onShowMembers: (_) {},
          onRemove: (_) async {},
          onEdit: (_, _) async => null,
          onCorrectName: (_, name) async {
            corrected = name;
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('partner-time-correct-t1')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('partner-time-correct-name-t1')),
      'Casa Mandou',
    );
    await tester.tap(find.byKey(const Key('partner-time-correct-save-t1')));
    await tester.pump();
    expect(corrected, 'Casa Mandou');

    await tester.tap(find.byKey(const Key('partner-time-edit-t1')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('partner-time-edit-name')),
    );
    expect(field.enabled, isFalse);
    expect(find.textContaining('O grupo escolheu este nome'), findsOneWidget);
  });

  testWidgets('a aba desligada não mostra tempos', (tester) async {
    await tester.pumpWidget(_app(const PartnerRankingOff()));
    expect(find.textContaining('desligado'), findsOneWidget);
    expect(find.text('Ranking completo'), findsNothing);
  });
}

Widget _app(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [child],
      ),
    ),
  );
}

List<RoomTimeLine> _house() {
  return [
    RoomTimeLine(
      entryId: 't1',
      place: 1,
      groupName: 'Os Ninjas',
      elapsedSeconds: 38 * 60 + 12,
      remainingSeconds: 21 * 60 + 48,
      playedOn: DateTime(2026, 11, 2),
      members: const ['Ana', 'Bruno'],
      escaped: true,
    ),
    RoomTimeLine(
      entryId: 't2',
      place: 2,
      groupName: 'Equipe Leste',
      elapsedSeconds: 41 * 60 + 5,
      remainingSeconds: 18 * 60 + 55,
      playedOn: DateTime(2026, 11, 2),
      members: const ['Marina'],
      escaped: true,
    ),
    RoomTimeLine(
      entryId: 't3',
      place: 3,
      groupName: 'Sem Pressa',
      elapsedSeconds: 49 * 60 + 40,
      remainingSeconds: 10 * 60 + 20,
      playedOn: DateTime(2026, 10, 20),
      members: const ['Caio'],
      escaped: true,
    ),
    RoomTimeLine(
      entryId: 't4',
      groupName: 'Quase',
      elapsedSeconds: 60 * 60,
      remainingSeconds: 0,
      playedOn: DateTime(2026, 10, 18),
      members: const ['Lia'],
      escaped: false,
    ),
  ];
}
