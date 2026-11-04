import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/legal/legal_documents.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the invoice and the terms acceptance', (tester) async {
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
      await pumpScapeMatch(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go('/groups/${SampleIds.groupCwbClosed}');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(AppKeys.serviceInvoice),
        400,
        scrollable: verticalScrollable,
      );
      await tester.ensureVisible(find.byKey(AppKeys.serviceInvoice));
      await tester.pumpAndSettle();
      await _shot(
        tester,
        dir,
        'jogador-nota-$width.png',
        size,
        find.byKey(AppKeys.serviceInvoice),
      );

      router.go('/cadastro');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(AppKeys.signupTerms),
        400,
        scrollable: verticalScrollable,
      );
      await tester.ensureVisible(find.byKey(AppKeys.signupTermsBanner));
      await tester.pumpAndSettle();
      await _shot(
        tester,
        dir,
        'jogador-aceite-$width.png',
        size,
        find.text(LegalDocuments.reviewBanner),
      );
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
