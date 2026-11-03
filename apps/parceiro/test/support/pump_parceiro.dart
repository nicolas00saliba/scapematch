import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_parceiro/parceiro_app.dart';

final Finder verticalScrollable = find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axis == Axis.vertical,
);

Future<void> pumpParceiro(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = const Size(400, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: overrides,
      child: const ParceiroApp(),
    ),
  );
  await tester.pumpAndSettle();
}
