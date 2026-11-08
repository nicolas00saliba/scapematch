import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch_parceiro/parceiro_app.dart';

final Finder verticalScrollable = find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axis == Axis.vertical,
);

Future<void> pumpParceiro(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = const Size(400, 1800),
  bool settle = true,
  AssetBundle? bundle,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const app = ParceiroApp();
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: overrides,
      child: bundle == null
          ? app
          : DefaultAssetBundle(bundle: bundle, child: app),
    ),
  );
  // O PNG do pin passa pelo codec, que no teste só termina fora do
  // relógio falso. O frame seguinte monta o lockup com o relógio em zero.
  await flushSplashArt(tester);
  final phone = tester.view.physicalSize.width < 960;
  if (phone && find.byType(ScapePinBox).evaluate().isEmpty) {
    await flushSplashArt(tester);
  }
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// Deixa o codec do pin terminar e pinta o frame em que o lockup entra.
Future<void> flushSplashArt(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump();
}
