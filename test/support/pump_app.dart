import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/scapematch_app.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';

/// The page scroll. A single-line search field also owns a horizontal
/// scrollable, and the group window has its own vertical one.
final Finder verticalScrollable = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      widget.axis == Axis.vertical &&
      widget.controller is! GroupWindowController,
);

Future<void> pumpScapeMatch(
  WidgetTester tester, {
  List<Override> overrides = const [],
  bool showOnboarding = false,
}) async {
  tester.view.physicalSize = const Size(400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        // A suíte abre na Home. Quem testa a introdução passa o store
        // e liga [showOnboarding], porque o mesmo provider não pode
        // ser sobrescrito duas vezes.
        if (!showOnboarding)
          onboardingStoreProvider.overrideWithValue(
            OnboardingStore(seen: true),
          ),
        ...overrides,
      ],
      child: const ScapeMatchApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Traz um quadro do carrossel para a faixa visível, um passo por vez.
Future<void> revealCarouselItem(
  WidgetTester tester,
  String carouselId,
  Finder target,
) async {
  final frame = find.byKey(AppKeys.carouselFrame(carouselId));
  await tester.scrollUntilVisible(frame, 500, scrollable: verticalScrollable);
  final horizontal = find.descendant(
    of: frame,
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
  tester.state<ScrollableState>(horizontal).position.jumpTo(0);
  await tester.pumpAndSettle();
  for (var step = 0; step < 40; step++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target.first);
      final view = tester.getRect(horizontal);
      if (rect.left >= view.left - 1 && rect.right <= view.right + 1) {
        return;
      }
    }
    final next = find.byKey(AppKeys.carouselNext(carouselId));
    if (next.evaluate().isEmpty) {
      break;
    }
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
  expect(target, findsWidgets);
}
