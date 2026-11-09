import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('the entry lockup carries the same seal as the top bar', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    await pumpParceiro(tester, size: const Size(390, 844));
    _expectLockupSeal(tester);
    await _saveShot(tester, 'parceiro-selo-mobile.png');

    await pumpParceiro(tester, size: const Size(1280, 900));
    _expectLockupSeal(tester);
    await _saveShot(tester, 'parceiro-selo-desktop.png');

    final lockup = _decoration(tester, PartnerSeal.lockupKey);
    await tester.enterText(
      find.byKey(PartnerKeys.partnerEmail),
      partnerDemoAccount.email,
    );
    await tester.enterText(
      find.byKey(PartnerKeys.partnerPassword),
      partnerDemoPassword,
    );
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();

    expect(find.byKey(PartnerSeal.lockupKey), findsNothing);
    final mark = _decoration(tester, PartnerSeal.markKey);
    expect(mark.color, lockup.color);
    expect(mark.borderRadius, lockup.borderRadius);
    expect(mark.borderRadius, BorderRadius.circular(999));
    final markBorder = mark.border! as Border;
    final lockupBorder = lockup.border! as Border;
    expect(markBorder.top.width, lockupBorder.top.width);
    expect(markBorder.top.width, PartnerSeal.borderWidth);
    expect(markBorder.top.color, ScapeLogo.copper);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(PartnerSeal.markKey),
        matching: find.text(PartnerSeal.label),
      ),
    );
    expect(text.style!.color, ScapeLogo.copper);
    expect(text.style!.fontWeight, FontWeight.w700);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dark page keeps the peach seal readable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: Center(child: PartnerLockup(height: 72))),
      ),
    );
    final decoration = _decoration(tester, PartnerSeal.lockupKey);
    expect(decoration.color, PartnerSeal.peach);
    final border = decoration.border! as Border;
    expect(border.top.color, ScapeLogo.copper);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(PartnerSeal.lockupKey),
        matching: find.text(PartnerSeal.label),
      ),
    );
    expect(text.style!.color, ScapeLogo.copper);
  });
}

void _expectLockupSeal(WidgetTester tester) {
  expect(find.text('EscapeMatch Parceiro'), findsOneWidget);
  expect(find.text(PartnerSeal.label), findsOneWidget);
  final logo = tester.getRect(find.byType(ScapeLogo));
  final seal = tester.getRect(find.byKey(PartnerSeal.lockupKey));
  final height = tester.widget<ScapeLogo>(find.byType(ScapeLogo)).height;
  expect(seal.top, greaterThanOrEqualTo(logo.bottom - 1));
  expect(seal.center.dx, closeTo(logo.center.dx, 2));
  expect(seal.top - logo.bottom, closeTo(PartnerSeal.gapFor(height), 1));
  final decoration = _decoration(tester, PartnerSeal.lockupKey);
  expect(
    decoration.color,
    ScapeLogo.copper.withValues(alpha: PartnerSeal.fillAlpha),
  );
  final border = decoration.border! as Border;
  expect(border.top.color, ScapeLogo.copper);
  expect(border.top.width, PartnerSeal.borderWidth);
  expect(decoration.borderRadius, BorderRadius.circular(999));
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byKey(PartnerSeal.lockupKey),
      matching: find.text(PartnerSeal.label),
    ),
  );
  expect(text.style!.fontWeight, FontWeight.w700);
  expect(text.style!.color, ScapeLogo.copper);
  expect(tester.takeException(), isNull);
}

BoxDecoration _decoration(WidgetTester tester, Key key) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)),
  );
  return box.decoration as BoxDecoration;
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
  await loader.load();
  final roots = [
    Platform.environment['FLUTTER_ROOT'],
    '${Platform.environment['HOME']}/sdk/flutter',
    '/home/ubuntu/flutter',
    '/opt/flutter',
  ].whereType<String>();
  for (final root in roots) {
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (!dir.existsSync()) {
      continue;
    }
    Future<ByteData> bytes(String name) async {
      final data = File('${dir.path}/$name').readAsBytesSync();
      return ByteData.view(Uint8List.fromList(data).buffer);
    }

    final roboto = FontLoader('Roboto')
      ..addFont(bytes('Roboto-Regular.ttf'))
      ..addFont(bytes('Roboto-Medium.ttf'))
      ..addFont(bytes('Roboto-Bold.ttf'));
    await roboto.load();
    return;
  }
}

Future<void> _saveShot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) {
    return;
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>());
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}
