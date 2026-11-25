import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
    final icons = _fontDir();
    if (icons == null) return;
    final iconBytes = File('$icons/MaterialIcons-Regular.otf').readAsBytesSync();
    final iconData = ByteData.sublistView(Uint8List.fromList(iconBytes));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(iconData));
    await iconLoader.load();
  });

  testWidgets('ganhos separa recompensa e a auditoria filtra a regra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(_Ready.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Ganhos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-recompensas-partes')), findsOneWidget);
    expect(find.textContaining('Subsídio'), findsOneWidget);
    expect(find.textContaining('pontos usados'), findsOneWidget);
    expect(find.byKey(const Key('admin-ganhos-teste')), findsOneWidget);
    await _shot(tester, 'admin-ganhos-recompensa');

    await tester.tap(find.text('Auditoria'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-auditoria-acao')), findsOneWidget);
    expect(find.text('Histórico de comissão'), findsOneWidget);
    expect(find.textContaining('plataforma:'), findsOneWidget);
    expect(find.textContaining('SQL direto'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('admin-regra-historico')));
    await tester.pump();
    await _shot(tester, 'admin-auditoria-regras');

    await tester.tap(find.text('Regras'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('admin-checkout-aviso'))),
      alignment: 0.2,
    );
    await tester.pump();
    expect(find.textContaining('até 3x sem juros'), findsOneWidget);
    expect(find.textContaining('não altera essa função'), findsOneWidget);
    await _shot(tester, 'admin-checkout');
  });
}

class _Ready extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
}

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/opt/cursor/artifacts/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
