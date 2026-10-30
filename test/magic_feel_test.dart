import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/presentation/room_detail_screen.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';

import 'support/pump_app.dart';

void main() {
  test('each room theme has a cover and two more gallery photos', () {
    for (final category in RoomCategory.values) {
      final photos = roomGallery(category);
      expect(photos, hasLength(3));
      expect(photos.toSet(), hasLength(3));
      expect(photos.first, roomCategoryImage(category));
    }
  });

  testWidgets('the intro opens on the full-bleed invitation', (tester) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    expect(find.text(OnboardingMessages.findTitle), findsOneWidget);
    expect(find.text('Encontre pessoas para jogar'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'onboarding/encontrar.jpg',
            ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the room photo opens a gallery', (tester) async {
    await pumpScapeMatch(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();
    expect(find.byType(RoomDetailScreen), findsOneWidget);
    expect(find.byKey(AppKeys.roomGallery), findsOneWidget);
    expect(find.text('O Cofre do Café'), findsWidgets);
  });

  testWidgets('reduce motion keeps the press scale at rest', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const MaterialApp(
          home: PressableScale(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
  });
}
