import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/presentation/room_detail_screen.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';

import 'support/pump_app.dart';

/// Sala "A Biblioteca" nos arredores de Curitiba.
const _biblioteca = 'room-curitiba-near-8';

void main() {
  testWidgets('desktop thumbs swap the cover and the phone strip does not', (
    tester,
  ) async {
    final gallery = roomGallery(RoomCategory.adventure);
    await pumpScapeMatch(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/sala/$_biblioteca');
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsOneWidget);
    expect(find.text('A Biblioteca'), findsOneWidget);
    expect(_heroAsset(tester), gallery.first);
    expect(find.byKey(AppKeys.roomGalleryPhoto(0)), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.roomGallery),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(_heroAsset(tester), gallery.first);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.roomGalleryPhoto(0)),
        matching: find.byKey(AppKeys.roomGallerySelected),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(AppKeys.roomGalleryPhoto(1)))
          .mouseCursor,
      SystemMouseCursors.click,
    );

    await tester.ensureVisible(find.byKey(AppKeys.roomGalleryPhoto(1)));
    await tester.tap(find.byKey(AppKeys.roomGalleryPhoto(1)));
    await tester.pumpAndSettle();
    expect(_heroAsset(tester), gallery[1]);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.roomGalleryPhoto(1)),
        matching: find.byKey(AppKeys.roomGallerySelected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AppKeys.roomGalleryPhoto(0)),
        matching: find.byKey(AppKeys.roomGallerySelected),
      ),
      findsNothing,
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(_heroAsset(tester), gallery.first);
    expect(find.byKey(AppKeys.roomGalleryPhoto(1)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _heroAsset(WidgetTester tester) {
  return tester
      .widget<ScapePhoto>(
        find.descendant(
          of: find.byKey(AppKeys.roomHero),
          matching: find.byType(ScapePhoto),
        ),
      )
      .asset;
}
