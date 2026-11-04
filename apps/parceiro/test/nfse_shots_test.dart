import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('saves the partner invoice tab', (tester) async {
    if (Platform.environment['SCAPEMATCH_NFSE_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/nfse')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const shots = [
      Size(1440, 900),
      Size(390, 844),
    ];
    for (final size in shots) {
      final width = size.width.toInt();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpParceiro(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
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
      final tab = find.text(PartnerMessages.invoices);
      await tester.ensureVisible(tab.first);
      await tester.pumpAndSettle();
      await tester.tap(tab.first);
      await tester.pumpAndSettle();
      final note = find.textContaining('Nota de teste');
      await tester.ensureVisible(note.first);
      await tester.pumpAndSettle();
      await _shot(tester, dir, 'parceiro-notas-$width.png', size, note);
    }
  });
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();
  const candidates = [
    '/home/ubuntu/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? dir;
  for (final candidate in candidates) {
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
      dir = candidate;
      break;
    }
  }
  if (dir == null) return;
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
