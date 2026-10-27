import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('confirms attendance and copies the group link', (tester) async {
    await pumpScapeMatch(tester);
    await _openGroup(
      tester,
      SampleIds.saoPaulo,
      SampleIds.groupSpCoberturaOpen,
    );

    expect(find.byKey(AppKeys.deleteGroup), findsNothing);
    expect(_spotSummary(tester), '1 de 4 vagas');
    expect(find.text('1 presença confirmada'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
    expect(find.byKey(AppKeys.confirmAttendance), findsOneWidget);
    expect(find.byKey(AppKeys.deleteGroup), findsNothing);

    await tester.tap(find.byKey(AppKeys.confirmAttendance));
    await tester.pumpAndSettle();

    expect(_text(tester, AppKeys.confirmedCount), '2 presenças confirmadas');
    expect(find.textContaining('Você'), findsWidgets);
    expect(find.byKey(AppKeys.confirmAttendance), findsNothing);

    // flutter_tester never answers Clipboard.getData, so the test records
    // the setData call instead of reading the clipboard back.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.tap(find.byKey(AppKeys.shareGroup));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, contains('/groups/${SampleIds.groupSpCoberturaOpen}'));
  });

  testWidgets('leaving at least two hours ahead explains the refund first', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openGroup(
      tester,
      SampleIds.saoPaulo,
      SampleIds.groupSpCoberturaOpen,
    );
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();
    expect(_spotSummary(tester), '2 de 4 vagas');

    await tester.tap(find.byKey(AppKeys.leaveGroup));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.leaveWithRefundBody), findsOneWidget);
    expect(_spotSummary(tester), '2 de 4 vagas');

    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();

    expect(_spotSummary(tester), '1 de 4 vagas');
    expect(find.textContaining('Reembolsado'), findsWidgets);
    expect(find.byKey(AppKeys.joinButton), findsNothing);

    await _home(tester);
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passados/Cancelados'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Reembolsado'), findsWidgets);
    expect(
      find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
      findsOneWidget,
    );
  });

  testWidgets('leaving inside two hours warns that there is no refund', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openGroup(tester, SampleIds.saoPaulo, SampleIds.groupSpMetroAlmost);
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();
    expect(_spotSummary(tester), '6 de 6 vagas');

    await tester.tap(find.byKey(AppKeys.leaveGroup));
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.leaveWithoutRefundBody), findsOneWidget);
    expect(_spotSummary(tester), '6 de 6 vagas');

    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();

    expect(_spotSummary(tester), '5 de 6 vagas');
    expect(find.textContaining('Sem reembolso'), findsWidgets);

    await _home(tester);
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passados/Cancelados'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem reembolso'), findsWidgets);
  });

  testWidgets('the creator deletes the group after a confirmation', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _selectCity(tester, SampleIds.portoAlegre);
    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.housePoaRedencao);
    await _pick(tester, 'room', SampleIds.roomPoaEstufa);
    await _pick(tester, 'slot', SampleIds.slotPoaEstufaFree);
    await tester.tap(find.byKey(AppKeys.createSubmit));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
    expect(_spotSummary(tester), '1 de 3 vagas');
    expect(find.byKey(AppKeys.deleteGroup), findsOneWidget);
    expect(find.byKey(AppKeys.leaveGroup), findsNothing);

    await tester.tap(find.byKey(AppKeys.deleteGroup));
    await tester.pumpAndSettle();
    expect(find.text(GroupMessages.deleteBody), findsOneWidget);
    expect(_spotSummary(tester), '1 de 3 vagas');

    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.cancelledBanner), findsOneWidget);
    expect(find.textContaining('reembolso integral'), findsWidgets);
    expect(find.byKey(AppKeys.deleteGroup), findsNothing);

    await _home(tester);
    await tester.tap(find.byKey(AppKeys.findGroup));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3 vagas'), findsNothing);

    await _home(tester);
    await tester.tap(find.byKey(AppKeys.myGroups));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3 vagas'), findsNothing);
    await tester.tap(find.text('Passados/Cancelados'));
    await tester.pumpAndSettle();
    expect(find.text('A Estufa'), findsWidgets);
    expect(find.textContaining('Reembolsado'), findsWidgets);
  });

  testWidgets('a past slot and an overlapping booking explain themselves', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openGroup(tester, SampleIds.saoPaulo, SampleIds.groupSpMetroAlmost);
    await tester.tap(find.byKey(AppKeys.joinButton));
    await tester.pumpAndSettle();
    await _home(tester);

    await tester.tap(find.byKey(AppKeys.createGroup));
    await tester.pumpAndSettle();
    await _pick(tester, 'house', SampleIds.houseSpLiberdade);
    await _pick(tester, 'room', SampleIds.roomSpIzakaya);
    await _pick(tester, 'slot', SampleIds.slotSpIzakayaOverlap);
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
        GroupMessages.createFailure(
          CreateGroupFailureReason.overlapsAnotherGroup,
        ),
      ),
      findsOneWidget,
    );

    await _pick(tester, 'house', SampleIds.houseSpAugusta);
    await _pick(tester, 'room', SampleIds.roomSpMetro);
    await _pick(tester, 'slot', SampleIds.slotSpMetroPast);
    final startedScroll = find.descendant(
      of: find.byType(CreateGroupScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text(GroupMessages.alreadyStartedHint),
      200,
      scrollable: startedScroll,
    );
    expect(find.text(GroupMessages.alreadyStartedHint), findsOneWidget);
    expect(_submitEnabled(tester), isFalse);
  });
}

Future<void> _openGroup(
  WidgetTester tester,
  String cityId,
  String groupId,
) async {
  await _selectCity(tester, cityId);
  await tester.tap(find.byKey(AppKeys.findGroup));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(AppKeys.groupCard(groupId)), 300);
  await tester.tap(find.byKey(AppKeys.groupCard(groupId)));
  await tester.pumpAndSettle();
}

Future<void> _home(WidgetTester tester) async {
  while (find.byType(BackButton).evaluate().isNotEmpty) {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }
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

String _spotSummary(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(AppKeys.spotSummary)).data!;
}

String _text(WidgetTester tester, Key key) {
  return tester.widget<Text>(find.byKey(key)).data!;
}

bool _submitEnabled(WidgetTester tester) {
  return tester
          .widget<FilledButton>(find.byKey(AppKeys.createSubmit))
          .onPressed !=
      null;
}
