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
  testWidgets('Curitiba carousels show a room card with the city pin', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.roomCarousel('mystery')),
      400,
      scrollable: verticalScrollable,
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
      300,
      scrollable: find.descendant(
        of: find.byKey(AppKeys.roomCarousel('mystery')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
    );

    expect(find.byKey(AppKeys.roomCarousel('terror')), findsOneWidget);
    expect(find.byKey(AppKeys.roomCarousel('mystery')), findsOneWidget);
    expect(find.byKey(AppKeys.roomSeeAll('mystery')), findsOneWidget);
    expect(find.text('Ver tudo'), findsWidgets);
    expect(
      find.byKey(AppKeys.roomCard(SampleIds.roomCwbCofre)),
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

  testWidgets('the bar order is Home, Meus grupos, Conta', (tester) async {
    await pumpScapeMatch(tester);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect((bar.destinations[0] as NavigationDestination).label, 'Home');
    expect((bar.destinations[1] as NavigationDestination).label, 'Meus grupos');
    expect((bar.destinations[2] as NavigationDestination).label, 'Conta');
    expect(
      tester.getCenter(find.byKey(AppKeys.homeTab)).dx,
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
      2,
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

  testWidgets('each Curitiba carousel scrolls past the first card', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    for (final category in const [
      'terror',
      'mystery',
      'adventure',
      'scienceFiction',
      'steampunk',
      'egypt',
    ]) {
      final carousel = find.byKey(AppKeys.roomCarousel(category));
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
      expect(position.maxScrollExtent, greaterThan(0), reason: category);
      final before = position.pixels;
      await tester.drag(scrollable, const Offset(-140, 0));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before), reason: category);
    }
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

    final carousel = find.byKey(AppKeys.roomCarousel('mystery'));
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

    final button = find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    final label = find.descendant(
      of: button,
      matching: find.text('Achar grupo'),
    );
    final natural = TextPainter(
      text: const TextSpan(
        text: 'Achar grupo',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
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
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.roomCarousel('egypt')),
      400,
      scrollable: verticalScrollable,
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.roomCard('room-cwb-tumba')),
      300,
      scrollable: find.descendant(
        of: find.byKey(AppKeys.roomCarousel('egypt')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Nícolas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openRoomAction(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.roomCarousel('mystery')),
    400,
    scrollable: verticalScrollable,
  );
  final target = find.byKey(key);
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.descendant(
      of: find.byKey(AppKeys.roomCarousel('mystery')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    ),
  );
  // O centro do botão precisa caber na tela. Um pedaço visível não basta.
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}
