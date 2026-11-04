import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/sharing/site_links.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/home_grid_slots.dart';

import 'support/fixed_groups.dart';
import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test('slot count fills three rows and then only the last one', () {
    expect(homeGridSlotCount(itemCount: 0, columns: 4), 12);
    expect(homeGridSlotCount(itemCount: 3, columns: 4), 12);
    expect(homeGridSlotCount(itemCount: 12, columns: 4), 12);
    expect(homeGridSlotCount(itemCount: 13, columns: 4), 16);
    expect(homeGridSlotCount(itemCount: 0, columns: 3), 9);
    expect(homeGridSlotCount(itemCount: 0, columns: 2), 6);
    expect(homeGridSlotCount(itemCount: 5, columns: 1), 5);
    expect(homeGroupGridColumns(windowWidth: 1440, gridWidth: 1200), 4);
    expect(homeGroupGridColumns(windowWidth: 1200, gridWidth: 1104), 3);
  });

  test('the phone highlight keeps a session that still needs one or two', () {
    final source = curitibaSampleGroups().first;
    final now = sampleNow;
    final open = liveClosing(source, missing: 1);
    final two = liveClosing(source, missing: 2);
    final closed = liveClosing(source, missing: 0);
    final loose = liveClosing(source, missing: 3);
    final started = liveClosing(
      source,
      missing: 1,
      startsAt: now.subtract(const Duration(minutes: 20)),
    );
    final ended = liveClosing(
      source,
      missing: 1,
      startsAt: now.subtract(const Duration(hours: 5)),
    );

    expect(open.isAlmostFull, isTrue);
    expect(now.isBefore(open.startsAt), isTrue);
    expect(
      filterGroupsHappeningAndClosing([
        open,
        two,
        closed,
        loose,
        started,
        ended,
      ], now),
      [open, two],
    );
    expect(GroupRules.almostFullMaxOpenSeats, 2);
  });

  test('the partner card points at the house app', () {
    final uri = partnerAppUri(
      page: Uri.parse('https://exemplo.test/scapematch/'),
    );
    expect(uri.toString(), 'https://exemplo.test/scapematch/parceiro/');
  });

  testWidgets('phone with no forming group drops the window and lifts promos', (
    tester,
  ) async {
    final source = curitibaSampleGroups();
    await pumpScapeMatch(
      tester,
      overrides: fixedGroups([
        liveClosing(source[0], missing: 4),
        liveClosing(
          source[1],
          missing: 1,
          startsAt: sampleNow.subtract(const Duration(minutes: 20)),
        ),
      ]),
    );
    await _phone(tester);

    expect(find.byKey(AppKeys.groupWindow), findsNothing);
    expect(_slots, findsNothing);
    expect(find.textContaining('Ainda não há grupos'), findsNothing);
    expect(find.text('Promoções'), findsOneWidget);
    expect(find.text('Novidades'), findsOneWidget);
    expect(find.text('Sessão já começou'), findsNothing);
    final searchBottom = tester
        .getBottomLeft(find.byKey(AppKeys.groupSearch))
        .dy;
    final promosTop = tester.getTopLeft(find.text('Promoções')).dy;
    expect(promosTop, greaterThan(searchBottom));
    expect(promosTop, lessThan(searchBottom + 80));
  });

  testWidgets('phone shows one live group and no filler card', (tester) async {
    final source = curitibaSampleGroups();
    final live = liveClosing(source[0], missing: 1);
    final waiting = source[1];
    final crowded = liveClosing(source[2], missing: 3);
    await pumpScapeMatch(
      tester,
      overrides: fixedGroups([live, waiting, crowded]),
    );
    await _phone(tester);

    expect(_cards, findsOneWidget);
    expect(find.byKey(AppKeys.groupCard(live.id)), findsOneWidget);
    expect(find.text('Falta 1 para fechar'), findsWidgets);
    expect(find.text('Sessão já começou'), findsNothing);
    expect(find.byKey(AppKeys.groupCard(waiting.id)), findsNothing);
    expect(find.byKey(AppKeys.groupCard(crowded.id)), findsNothing);
    expect(_slots, findsNothing);
    expect(find.byKey(AppKeys.groupWindow), findsOneWidget);
  });

  testWidgets('phone shows every live group that still needs one or two', (
    tester,
  ) async {
    final source = curitibaSampleGroups();
    final live = [
      liveClosing(source[0], missing: 1),
      liveClosing(source[1], missing: 2),
      liveClosing(source[2], missing: 1),
      liveClosing(source[3], missing: 2, gameType: GameTypes.rpg),
    ];
    final ignored = liveClosing(source[4], missing: 4);
    await pumpScapeMatch(tester, overrides: fixedGroups([...live, ignored]));
    await _phone(tester);

    expect(_cards, findsNWidgets(4));
    expect(_slots, findsNothing);
    expect(
      tester.getSize(find.byKey(AppKeys.groupWindow)).height,
      closeTo(groupWindowMaxHeight, 1),
    );

    await tester.tap(find.byKey(AppKeys.gameTypeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
    await tester.pumpAndSettle();

    expect(_cards, findsOneWidget);
    expect(find.byKey(AppKeys.groupCard(live[3].id)), findsOneWidget);
    expect(_slots, findsNothing);
    expect(find.byKey(AppKeys.groupWindow), findsOneWidget);
  });

  testWidgets('phone search still lists a session that already started', (
    tester,
  ) async {
    final source = curitibaSampleGroups();
    final forming = liveClosing(source[0], missing: 1);
    final started = liveClosing(
      source[1],
      missing: 1,
      startsAt: sampleNow.subtract(const Duration(minutes: 30)),
    );
    await pumpScapeMatch(tester, overrides: fixedGroups([forming, started]));
    await _phone(tester);
    expect(find.byKey(AppKeys.groupCard(forming.id)), findsOneWidget);
    expect(find.byKey(AppKeys.groupCard(started.id)), findsNothing);
    expect(find.text('Sessão já começou'), findsNothing);

    await tester.enterText(find.byKey(AppKeys.groupSearch), started.roomName);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.groupCard(started.id)), findsOneWidget);
    expect(find.text('Sessão já começou'), findsNothing);
    expect(_slots, findsNothing);
  });

  testWidgets('desktop with zero groups fills three rows of slots', (
    tester,
  ) async {
    await pumpScapeMatch(tester, overrides: fixedGroups(const []));
    await _desktop(tester, const Size(1440, 900));

    expect(_cards, findsNothing);
    expect(_slots, findsNWidgets(12));
    expect(find.text(homeGridCreateMessage), findsOneWidget);
    expect(
      find.textContaining('Novas salas chegando em breve'),
      findsOneWidget,
    );
    expect(find.text(homeGridPartnerMessage), findsOneWidget);
    expect(find.text(homeGridInviteMessage), findsOneWidget);
    expect(find.textContaining('Ainda não há grupos'), findsNothing);
    _expectSameRow(tester, 0, 3);
    expect(
      tester.getTopLeft(find.byKey(AppKeys.homeGridSlot(4))).dy,
      greaterThan(tester.getBottomLeft(find.byKey(AppKeys.homeGridSlot(0))).dy),
    );

    await _desktop(tester, const Size(1200, 900));
    expect(_slots, findsNWidgets(9));
  });

  testWidgets('desktop with three groups fills the rest of the grid', (
    tester,
  ) async {
    final groups = curitibaSampleGroups().take(3).toList();
    await pumpScapeMatch(tester, overrides: fixedGroups(groups));
    await _desktop(tester, const Size(1440, 900));

    expect(_cards, findsNWidgets(3));
    expect(_slots, findsNWidgets(9));
    expect(find.text(homeGridCreateMessage), findsOneWidget);
    expect(find.text(homeGridInviteMessage), findsOneWidget);
    final card = tester.getSize(_cards.first);
    final slot = tester.getSize(find.byKey(AppKeys.homeGridSlot(0)));
    expect(slot.width, closeTo(card.width, 2));
    expect(slot.height, closeTo(card.height, 8));
    expect(
      tester.getTopLeft(find.byKey(AppKeys.homeGridSlot(0))).dy,
      closeTo(tester.getTopLeft(_cards.first).dy, 2),
    );

    await tester.ensureVisible(find.text(homeGridCreateMessage).first);
    await tester.tap(find.text(homeGridCreateMessage).first);
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupScreen), findsOneWidget);
  });

  testWidgets('desktop with thirteen groups only completes the last row', (
    tester,
  ) async {
    final groups = curitibaSampleGroups().take(13).toList();
    await pumpScapeMatch(tester, overrides: fixedGroups(groups));
    await _desktop(tester, const Size(1440, 900));

    expect(_cards, findsNWidgets(13));
    expect(_slots, findsNWidgets(3));
    expect(find.text(homeGridCreateMessage), findsOneWidget);
    expect(
      find.textContaining('Novas salas chegando em breve'),
      findsOneWidget,
    );
    expect(find.text(homeGridPartnerMessage), findsOneWidget);
    expect(find.text(homeGridInviteMessage), findsNothing);
  });

  testWidgets('filtering the desktop grid still fills the holes', (
    tester,
  ) async {
    final groups = [
      for (final group in curitibaSampleGroups().take(3))
        group.copyWith(gameType: GameTypes.escapeRoom),
    ];
    await pumpScapeMatch(tester, overrides: fixedGroups(groups));
    await _desktop(tester, const Size(1440, 900));
    expect(_cards, findsNWidgets(3));

    await tester.tap(find.byKey(AppKeys.gameTypeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.gameTypeOption(GameTypes.rpg)));
    await tester.pumpAndSettle();

    expect(_cards, findsNothing);
    expect(_slots, findsNWidgets(12));
    expect(find.textContaining('Novas salas de RPG'), findsWidgets);
  });

  testWidgets('a desktop slot invites friends and opens the partner app', (
    tester,
  ) async {
    await pumpScapeMatch(tester, overrides: fixedGroups(const []));
    await _desktop(tester, const Size(1440, 900));

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.ensureVisible(find.byKey(AppKeys.homeGridSlot(3)));
    await tester.tap(find.byKey(AppKeys.homeGridSlot(3)));
    await tester.pumpAndSettle();
    expect(
      find.text('Convite copiado. Manda para os seus amigos.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(AppKeys.homeGridSlot(2)));
    await tester.tap(find.byKey(AppKeys.homeGridSlot(2)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

final Finder _cards = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('group-card-');
});

final Finder _slots = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('home-grid-slot-');
});

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
}

Future<void> _desktop(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
}

void _expectSameRow(WidgetTester tester, int start, int end) {
  final top = tester.getTopLeft(find.byKey(AppKeys.homeGridSlot(start))).dy;
  for (var index = start + 1; index <= end; index++) {
    expect(
      (tester.getTopLeft(find.byKey(AppKeys.homeGridSlot(index))).dy - top)
          .abs(),
      lessThan(2),
      reason: 'vaga $index',
    );
  }
}
