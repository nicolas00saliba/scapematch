import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/create_group_view_model.dart';

/// Escolhe o primeiro horário livre da sala, em qualquer dia.
Future<void> pickFirstOpenSlotOfRoom(WidgetTester tester, String roomId) async {
  final state = _state(tester);
  final matches = state.openSlots.where((item) => item.slot.roomId == roomId);
  expect(matches, isNotEmpty, reason: 'sala $roomId sem horário livre');
  await pickOpenSlot(tester, matches.first.slot.id);
}

/// Escolhe o dia do horário e, em seguida, o chip da sala.
Future<void> pickOpenSlot(WidgetTester tester, String slotId) async {
  final state = _state(tester);
  final matches = state.openSlots.where((item) => item.slot.id == slotId);
  expect(matches, hasLength(1), reason: 'horário $slotId não está livre');
  final day = matches.single.day;
  final scroll = find.descendant(
    of: find.byType(CreateGroupScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    ),
  );
  final dayFinder = find.byKey(AppKeys.openDay(day.year, day.month, day.day));
  await tester.scrollUntilVisible(dayFinder, 300, scrollable: scroll);
  await tester.tap(dayFinder);
  await tester.pumpAndSettle();
  final slotFinder = find.byKey(AppKeys.openSlot(slotId));
  await tester.scrollUntilVisible(slotFinder, 300, scrollable: scroll);
  await tester.tap(slotFinder);
  await tester.pumpAndSettle();
}

CreateGroupState _state(WidgetTester tester) {
  final context = tester.element(find.byType(CreateGroupScreen));
  return ProviderScope.containerOf(context).read(createGroupViewModelProvider);
}
