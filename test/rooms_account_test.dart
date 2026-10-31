import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/catalog/presentation/room_groups_screen.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/my_groups_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the room carousel shows a card with the city pin', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _revealRoom(
      tester,
      find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
    );

    expect(find.byKey(AppKeys.roomsCarousel), findsOneWidget);
    expect(find.byKey(AppKeys.roomCarousel('terror')), findsNothing);
    expect(find.byKey(AppKeys.roomSeeAll('mystery')), findsNothing);
    expect(find.text('Salas mais procuradas'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.roomsCarousel),
        matching: find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
      ),
      findsOneWidget,
    );
    expect(find.text('Mistério da Rua XV'), findsWidgets);
    expect(find.text('Curitiba'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('Achar grupo opens only the groups of that room', (tester) async {
    await pumpScapeMatch(tester);
    await _openRoomAction(
      tester,
      AppKeys.roomFindGroup(SampleIds.roomCwbCofre),
    );

    expect(find.byType(RoomGroupsScreen), findsOneWidget);
    expect(find.text('O Cofre do Café'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(RoomGroupsScreen),
        matching: find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(RoomGroupsScreen),
        matching: find.byKey(AppKeys.groupCard('grp-cwb-opera-open')),
      ),
      findsNothing,
    );
    expect(
      find.byKey(AppKeys.roomGroupsCreate(SampleIds.roomCwbCofre)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(RoomGroupsScreen),
        matching: find.byKey(AppKeys.roomCreateGroup(SampleIds.roomCwbCofre)),
      ),
      findsNothing,
    );
  });

  testWidgets('Criar grupo opens the form with the room already chosen', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openRoomAction(
      tester,
      AppKeys.roomCreateGroup(SampleIds.roomCwbCofre),
    );

    expect(find.byType(CreateGroupScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CreateGroupScreen),
        matching: find.textContaining('Mistério da Rua XV'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(CreateGroupScreen),
        matching: find.textContaining('O Cofre do Café'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(CreateGroupScreen),
        matching: find.text('Escolha o horário'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the bar order is Home, Perto de você, Meus grupos, Conta', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect((bar.destinations[0] as NavigationDestination).label, 'Home');
    expect(
      (bar.destinations[1] as NavigationDestination).label,
      'Perto de você',
    );
    expect((bar.destinations[2] as NavigationDestination).label, 'Meus grupos');
    expect((bar.destinations[3] as NavigationDestination).label, 'Conta');
    expect(
      tester.getCenter(find.byKey(AppKeys.homeTab)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.nearTab)).dx),
    );
    expect(
      tester.getCenter(find.byKey(AppKeys.nearTab)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.myGroups)).dx),
    );
    expect(
      tester.getCenter(find.byKey(AppKeys.myGroups)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.accountTab)).dx),
    );

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(MyGroupsScreen), findsNothing);
    expect(find.byKey(AppKeys.accountGreeting), findsOneWidget);
    expect(find.text('Olá, Nícolas'), findsOneWidget);
    expect(find.byKey(AppKeys.accountWallet), findsOneWidget);
    expect(find.text('Carteira ScapeMatch'), findsOneWidget);
    expect(find.text('Meus parceiros de jogo'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );

    await tester.tap(find.byKey(AppKeys.accountDestination('partners')));
    await tester.pumpAndSettle();
    expect(find.text('Marina'), findsOneWidget);
    expect(
      find.textContaining('Ainda não há uma lista real de parceiros'),
      findsOneWidget,
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountSettings));
    await tester.pumpAndSettle();
    expect(find.text('Configurações'), findsWidgets);
    expect(
      find.textContaining('Nada nesta tela altera o app de verdade.'),
      findsOneWidget,
    );
  });

  testWidgets('the room carousel snaps one whole card at a time', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    final carousel = find.byKey(AppKeys.roomsCarousel);
    await tester.scrollUntilVisible(
      carousel,
      400,
      scrollable: verticalScrollable,
    );
    final scrollable = find.descendant(
      of: carousel,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final before = position.pixels;
    final next = find.byKey(AppKeys.carouselNext('rooms'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before + 40));
    final stride = position.pixels - before;
    final view = tester.getRect(scrollable);
    final item = find.byKey(AppKeys.carouselItem('rooms', 1));
    final rect = tester.getRect(item);
    expect(rect.left, closeTo(view.left, 2));
    expect(rect.right, lessThanOrEqualTo(view.right + 1));
    expect(position.pixels, closeTo(stride, 1));
  });

  testWidgets('room carousel matches the card and stays tappable at 1.6x', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    final carousel = find.byKey(AppKeys.roomsCarousel);
    await tester.scrollUntilVisible(
      carousel,
      400,
      scrollable: verticalScrollable,
    );
    final cards = find.descendant(of: carousel, matching: find.byType(Card));
    var tallest = 0.0;
    for (final element in cards.evaluate()) {
      final box = element.renderObject! as RenderBox;
      tallest = math.max(tallest, box.size.height);
    }
    final listHeight = tester
        .getSize(find.descendant(of: carousel, matching: find.byType(ListView)))
        .height;
    expect(listHeight - tallest, inInclusiveRange(-1, 4));

    final button = await _revealRoom(
      tester,
      find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre)),
    );
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    final label = find.descendant(
      of: button,
      matching: find.text('Achar grupo'),
    );
    final labelStyle = tester.widget<Text>(label).style;
    final natural = TextPainter(
      text: TextSpan(text: 'Achar grupo', style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(tester.element(button)),
    )..layout();
    expect(
      tester.getSize(label).width,
      greaterThanOrEqualTo(natural.width - 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home and Conta fit a 360 wide phone', (tester) async {
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    await _revealRoom(tester, find.byKey(AppKeys.roomCard('room-cwb-tumba')));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Nícolas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openRoomAction(WidgetTester tester, Key key) async {
  final target = await _revealRoom(tester, find.byKey(key));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<Finder> _revealRoom(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.roomsCarousel),
    400,
    scrollable: verticalScrollable,
  );
  final scrollable = find.descendant(
    of: find.byKey(AppKeys.roomsCarousel),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  for (var step = 0; step < 30; step++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target.first);
      final view = tester.getRect(scrollable);
      if (rect.left >= view.left - 1 && rect.right <= view.right + 1) {
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        return target.first;
      }
    }
    final next = find.byKey(AppKeys.carouselNext('rooms'));
    expect(next, findsOneWidget, reason: 'o cartão não entrou no carrossel');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
  fail('não achei o cartão no carrossel de salas');
}
