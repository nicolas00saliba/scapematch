import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/memory_tiles.dart';
import 'support/pump_app.dart';

void main() {
  testWidgets('the phone keeps the bottom bar and the group window', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(AppKeys.groupWindow), findsOneWidget);
    expect(find.byType(ScapeLogo), findsOneWidget);
    expect(
      tester.getSize(find.byKey(AppKeys.groupSearch)).width,
      lessThan(520),
    );

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(find.text('O Cofre do Café'));
    final action = tester.getTopLeft(
      find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre)),
    );
    expect(action.dy, greaterThan(title.dy + 40));
  });

  testWidgets('desktop opens a site with a top nav, a grid and a side column', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [
        mapTileProvider.overrideWithValue(MemoryTileProvider()),
        userLocationSourceProvider.overrideWithValue(
          FixedUserLocation.device(cityCenters[SampleIds.curitiba]!),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(ScapeLogo), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(AppKeys.homeTab)).dy, lessThan(72));
    expect(
      tester.getCenter(find.byKey(AppKeys.homeTab)).dx,
      lessThan(tester.getCenter(find.byKey(AppKeys.nearTab)).dx),
    );
    expect(find.byKey(AppKeys.groupWindow), findsNothing);
    expect(
      tester.getSize(find.byKey(AppKeys.groupSearch)).width,
      greaterThan(700),
    );

    final cards = find.descendant(
      of: find.byType(HomeScreen),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('group-card-');
      }),
    );
    expect(cards, findsWidgets);
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect((first.top - second.top).abs(), lessThan(2));
    expect((first.left - second.left).abs(), greaterThan(200));

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();

    final title = tester.getTopLeft(find.text('O Cofre do Café'));
    final action = tester.getTopLeft(
      find.byKey(AppKeys.roomFindGroup(SampleIds.roomCwbCofre)),
    );
    expect(action.dx, greaterThan(title.dx + 200));

    await tester.tap(find.byKey(AppKeys.nearTab));
    await tester.pumpAndSettle();

    final sheet = tester.getRect(find.byKey(AppKeys.mapSheet));
    final map = tester.getRect(find.byType(FlutterMap));
    expect(sheet.right, lessThanOrEqualTo(map.left + 1));
    expect(map.right, closeTo(1280, 2));
  });

  testWidgets('desktop news is one card with an arrow that hides at the ends', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(AppKeys.carouselFrame('news')),
      500,
      scrollable: verticalScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.carouselPrevious('news')), findsNothing);
    final next = find.byKey(AppKeys.carouselNext('news'));
    expect(next, findsOneWidget);
    final frame = tester.getRect(find.byKey(AppKeys.carouselFrame('news')));
    final first = tester.getRect(find.byKey(AppKeys.carouselItem('news', 0)));
    expect(first.width, closeTo(frame.width, 2));
    expect(first.left, closeTo(frame.left, 2));

    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.carouselPrevious('news')), findsOneWidget);

    for (var step = 0; step < 24; step++) {
      final forward = find.byKey(AppKeys.carouselNext('news'));
      if (forward.evaluate().isEmpty) {
        break;
      }
      await tester.ensureVisible(forward);
      await tester.tap(forward);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(AppKeys.carouselNext('news')), findsNothing);
    expect(find.byKey(AppKeys.carouselPrevious('news')), findsOneWidget);
  });

  testWidgets('desktop home cards are shorter and the phone card stays wide', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();

    final phoneCard = find.byKey(
      AppKeys.groupCard(SampleIds.groupCwbCofreAlmost),
    );
    final phoneCover = tester.getSize(
      find.descendant(of: phoneCard, matching: find.byType(ScapePhoto)).first,
    );
    final phoneHeight = tester.getSize(phoneCard).height;
    expect(phoneCover.width, closeTo(groupCardCoverWidth, 1));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Convidar'), findsWidgets);
    expect(find.textContaining('para fechar'), findsWidgets);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();

    final webCard = find.byKey(
      AppKeys.groupCard(SampleIds.groupCwbCofreAlmost),
    );
    final webCover = tester.getSize(
      find.descendant(of: webCard, matching: find.byType(ScapePhoto)).first,
    );
    final webHeight = tester.getSize(webCard).height;
    expect(find.byType(NavigationBar), findsNothing);
    expect(webCover.width, closeTo(groupCardDenseCoverWidth, 1));
    expect(webHeight, lessThan(phoneHeight - 24));
    expect(
      find.descendant(of: webCard, matching: find.text('Convidar')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: webCard,
        matching: find.textContaining('para fechar'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(of: webCard, matching: find.textContaining('mín.')),
      findsOneWidget,
    );

    final promos = tester.getTopLeft(find.byKey(AppKeys.promoCarousel)).dy;
    final news = tester.getTopLeft(find.byKey(AppKeys.newsFeed)).dy;
    expect((promos - news).abs(), lessThan(8));
    expect(promos, greaterThan(tester.getBottomLeft(webCard).dy));
  });
}
