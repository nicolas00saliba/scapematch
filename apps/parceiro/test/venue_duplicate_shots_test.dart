import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('salva o aviso, a reivindicação e a aprovação', (tester) async {
    if (Platform.environment['SCAPEMATCH_DUPLICATE_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/duplicatas')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const shots = [Size(1440, 900), Size(390, 844)];
    for (final size in shots) {
      final width = size.width.toInt();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _warning(tester, dir, size, width);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _claim(tester, dir, size, width);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _approval(tester, dir, size, width);
    }
  });
}

Future<void> _warning(
  WidgetTester tester,
  Directory dir,
  Size size,
  int width,
) async {
  await pumpParceiro(tester, size: size);
  await _tap(tester, find.byKey(PartnerKeys.partnerSignup));
  await tester.enterText(find.byKey(PartnerKeys.venueName), 'Ninja Centro');
  await tester.enterText(find.byKey(PartnerKeys.venuePostalCode), '80010-000');
  await tester.enterText(find.byKey(PartnerKeys.venueNumber), '120');
  await tester.enterText(find.byKey(PartnerKeys.venueDocument), '10987654321');
  await _tap(tester, find.byKey(PartnerKeys.venueCheck));
  await _shot(
    tester,
    dir,
    'aviso-duplicata-$width.png',
    size,
    find.byKey(PartnerKeys.venueDuplicateBanner),
  );
}

Future<void> _claim(
  WidgetTester tester,
  Directory dir,
  Size size,
  int width,
) async {
  await pumpParceiro(tester, size: size);
  await _tap(tester, find.byKey(PartnerKeys.partnerSignup));
  await tester.enterText(find.byKey(PartnerKeys.venueName), 'Ninja Centro');
  await tester.enterText(find.byKey(PartnerKeys.venuePostalCode), '80010-000');
  await tester.enterText(find.byKey(PartnerKeys.venueNumber), '120');
  await tester.enterText(find.byKey(PartnerKeys.venueDocument), '10987654321');
  await _tap(tester, find.byKey(PartnerKeys.venueCheck));
  await _tap(tester, find.byKey(PartnerKeys.venueClaim));
  await tester.enterText(
    find.byKey(PartnerKeys.venueClaimNote),
    'Eu respondo pela Ninja desde a abertura.',
  );
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'esta-casa-e-minha-$width.png',
    size,
    find.text(PartnerMessages.claimTitle),
  );
}

Future<void> _approval(
  WidgetTester tester,
  Directory dir,
  Size size,
  int width,
) async {
  await pumpParceiro(tester, size: size);
  await _tap(tester, find.byKey(PartnerKeys.partnerAdminDemo));
  await _shot(
    tester,
    dir,
    'aprovacao-$width.png',
    size,
    find.byKey(PartnerKeys.venuePending),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  final scrollable = find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axis == Axis.vertical,
  );
  if (scrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable.last);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  const dir = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
  if (!File('$dir/Roboto-Regular.ttf').existsSync()) {
    return;
  }
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name,
  Size expected,
  Finder anchor,
) async {
  expect(anchor, findsWidgets, reason: name);
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
