import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/features/catalog/domain/player_range.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/features/onboarding/presentation/city_landmarks.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test('every sample room has a realistic player range', () {
    final database = buildSampleDatabase(now: sampleNow);
    expect(database.rooms, isNotEmpty);
    for (final room in database.rooms) {
      expect(room.minimumPlayers, inInclusiveRange(2, 6), reason: room.id);
      expect(room.minimumPlayers, lessThanOrEqualTo(room.capacity));
      expect(room.minimumPlayers, isNot(9));
    }
    final cofre = database.roomById(SampleIds.roomCwbCofre)!;
    expect(
      playerRangeLabel(minimum: cofre.minimumPlayers, maximum: cofre.capacity),
      '4–6 jogadores',
    );
    final almost = database.groups.singleWhere(
      (group) => group.id == SampleIds.groupCwbCofreAlmost,
    );
    expect(almost.roomMinimum, 4);
    expect(almost.minimumSpots, 6);
    expect(almost.spotsUntilClose, 1);
    for (final group in database.groups) {
      expect(group.minimumSpots, greaterThanOrEqualTo(group.roomMinimum));
      expect(group.minimumSpots, lessThanOrEqualTo(group.roomCapacity));
      expect(group.totalSpots, greaterThanOrEqualTo(group.minimumSpots));
    }
  });

  testWidgets('the light home card shows portrait photos', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpScapeMatch(tester);
    await tester.pumpAndSettle();
    final portraits = [
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        if (image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('/people/'))
          (image.image as AssetImage).assetName,
    ];
    expect(portraits, isNotEmpty);
    expect(portraits.toSet(), containsAll(PersonPortraits.assets.take(4)));
  });

  test('an unknown city falls back to the Curitiba landmark', () {
    expect(landmarkFor(SampleIds.saoPaulo).name, 'MASP');
    expect(
      landmarkFor('cidade-nova').asset,
      landmarkFor(SampleIds.curitiba).asset,
    );
    expect(cityLandmarks, hasLength(SampleIds.cities.length));
  });

  testWidgets('the near intro crossfades to the selected city', (tester) async {
    await pumpScapeMatch(tester, showOnboarding: true);
    await tester.tap(find.byKey(AppKeys.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(OnboardingMessages.nearTitle), findsOneWidget);
    expect(_assets(tester), contains('assets/images/landmarks/curitiba.jpg'));

    await tester.tap(find.byKey(AppKeys.citySelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
    await tester.pumpAndSettle();

    expect(_assets(tester), contains('assets/images/landmarks/sao-paulo.jpg'));
    expect(
      _assets(tester),
      isNot(contains('assets/images/landmarks/curitiba.jpg')),
    );
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('account groups the old pages and keeps their routes', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.go('/account');
    await tester.pumpAndSettle();
    expect(find.text('Termos de uso'), findsNothing);
    expect(find.text('Pedir exclusão da conta'), findsNothing);
    expect(find.text('Avisos'), findsNothing);

    await tester.ensureVisible(
      find.byKey(AppKeys.accountDestination('policies')),
    );
    await tester.tap(find.byKey(AppKeys.accountDestination('policies')));
    await tester.pumpAndSettle();
    expect(find.text('Termos de uso'), findsOneWidget);
    expect(find.text('Privacidade'), findsOneWidget);
    expect(find.text('Reembolso'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.accountLegal));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.termsTitle), findsOneWidget);

    router.go('/legal/privacidade');
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.privacyTitle), findsOneWidget);

    router.go('/account/dataPrivacy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountDelete));
    await tester.pumpAndSettle();
    expect(find.text('Pedir exclusão da conta'), findsWidgets);

    router.go('/account/settings');
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.accountNotices), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.accountNotices));
    await tester.pumpAndSettle();
    expect(find.text('Avisos'), findsWidgets);

    router.go('/account/notices');
    await tester.pumpAndSettle();
    expect(find.text('Avisos'), findsWidgets);
  });
}

List<String> _assets(WidgetTester tester) {
  return [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image is AssetImage) (image.image as AssetImage).assetName,
  ];
}
