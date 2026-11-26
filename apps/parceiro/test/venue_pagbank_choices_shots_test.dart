import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_signup_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_pagbank_signup_card.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('salva as escolhas da conta PagBank', (tester) async {
    if (Platform.environment['SCAPEMATCH_PARTNER_SHOTS'] != '1') return;
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await _pump(tester, MemoryPagbankSignupRepository(), const Size(390, 560));
    await _shot(tester, dir, 'receber-escolhas.png');

    await tester.tap(find.byKey(PartnerKeys.pagbankHaveAccount));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'receber-entrar.png');

    await tester.tap(find.byKey(PartnerKeys.pagbankSignupBack));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.pagbankNoAccount));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'receber-criar.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pump(
      tester,
      MemoryPagbankSignupRepository(apiEnabled: true),
      const Size(390, 640),
    );
    await tester.tap(find.byKey(PartnerKeys.pagbankNoAccount));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'receber-passos.png');
  });
}

Future<void> _pump(
  WidgetTester tester,
  MemoryPagbankSignupRepository repo,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [pagbankSignupRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              VenuePagbankSignupCard(
                venueId: 'casa',
                onOpen: (_) {},
                today: () => DateTime.utc(2026, 11, 24),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, Directory dir, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) throw StateError(name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}

Future<void> _loadFonts() async {
  final dir = _fontDir();
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

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
