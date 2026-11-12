import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('a flag nasce desligada e o admin consegue ligar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MemoryAdminApi();
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [adminApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: adminTheme(),
          home: const Scaffold(body: RegrasPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final flag = find.byKey(const Key('admin-passaporte-flag'));
    await _reveal(tester, flag);
    expect(tester.widget<SwitchListTile>(flag).value, isFalse);
    expect(api.passport['passport_enabled'], isFalse);
    await tester.tap(flag);
    await tester.pump();
    await _reveal(tester, find.byKey(const Key('admin-salvar-passaporte')));
    await tester.tap(find.byKey(const Key('admin-salvar-passaporte')));
    await tester.pump();
    await tester.pump();
    expect(api.passport['passport_enabled'], isTrue);
    expect(api.passport['passport_points_5'], 500);
    expect(api.passport['passport_house_points'], 300);
    expect(find.text('Passaporte gravado.'), findsOneWidget);
    await _reveal(tester, flag);
    expect(tester.widget<SwitchListTile>(flag).value, isTrue);
    await _shot(tester, 'passaporte-admin');
  });

  testWidgets('marco fora de ordem não grava', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MemoryAdminApi();
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [adminApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: adminTheme(),
          home: const Scaffold(body: RegrasPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final field = find.byKey(const Key('admin-passaporte-passport_rooms_10'));
    await _reveal(tester, field);
    await tester.enterText(field, '5');
    await _reveal(tester, find.byKey(const Key('admin-salvar-passaporte')));
    await tester.tap(find.byKey(const Key('admin-salvar-passaporte')));
    await tester.pump();
    await tester.pump();
    expect(api.passport['passport_rooms_10'], 10);
    expect(find.text('os marcos de salas precisam crescer'), findsOneWidget);
  });
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final list = find.byType(ListView);
  for (var i = 0; i < 20; i++) {
    final top = tester.getTopLeft(target).dy;
    if (top > 80 && top < 640) return;
    await tester.drag(list, Offset(0, top > 640 ? -320 : 320));
    await tester.pump();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  try {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('/opt/cursor/artifacts/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  } on Object {
    // O CI não tem a pasta de artefatos do agente.
  }
}
