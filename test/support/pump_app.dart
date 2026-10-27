import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/scapematch_app.dart';

/// The page scroll. A single-line search field also owns a horizontal
/// scrollable, so `scrollUntilVisible` needs this narrower finder.
final Finder verticalScrollable = find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axis == Axis.vertical,
);

Future<void> pumpScapeMatch(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: overrides,
      child: const ScapeMatchApp(),
    ),
  );
  await tester.pumpAndSettle();
}
