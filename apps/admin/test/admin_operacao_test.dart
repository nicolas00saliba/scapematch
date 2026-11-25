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
import 'package:scapematch_admin/admin_ops.dart';
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

  testWidgets('operação lista o grupo e só exclui a sessão com EXCLUIR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ops = MemoryAdminOpsApi();
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminOpsProvider.overrideWithValue(ops),
          adminSessionProvider.overrideWith(_Ready.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Operação'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-operacao')), findsOneWidget);
    expect(find.textContaining('Ninja Escape · O Cofre'), findsWidgets);
    expect(find.textContaining('Nícolas'), findsWidgets);
    await tester.tap(find.textContaining('Ninja Escape · O Cofre').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-grupo')), findsOneWidget);
    expect(find.textContaining('Ana'), findsOneWidget);
    expect(find.textContaining('custódia retida'), findsWidgets);
    expect(find.byKey(const Key('admin-host-aviso')), findsOneWidget);
    expect(find.byKey(const Key('admin-remover-membro-host')), findsNothing);
    expect(find.textContaining('2 de 6 vagas'), findsOneWidget);
    await _shot(tester, 'admin-operacao-grupo');

    await tester.tap(find.byKey(const Key('admin-excluir-sessao')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byKey(const Key('admin-confirm-word')), 'nao');
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(ops.sessionCancelled, isFalse);
    expect(find.byKey(const Key('admin-confirm-word')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('admin-confirm-word')), 'EXCLUIR');
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ops.sessionCancelled, isTrue);
    expect(ops.refunds, 2);
    expect(find.textContaining('2 reembolso'), findsOneWidget);
    await _shot(tester, 'admin-operacao-excluida');
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
  final boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  ) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/opt/cursor/artifacts/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
