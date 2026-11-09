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
  });

  testWidgets('painel mostra casas, ganhos e a taxa só quando existe', (tester) async {
    final api = MemoryAdminApi();
    _size(tester, const Size(1280, 900));
    await _pump(tester, api);
    expect(find.byKey(const Key('admin-casas')), findsOneWidget);
    expect(find.text('Ninja Escape'), findsOneWidget);
    expect(find.text('Casa da Fila'), findsOneWidget);
    await _shot(tester, 'admin-casas');

    await tester.tap(find.text('Casa da Fila'));
    await _frames(tester);
    expect(find.byKey(const Key('admin-aprovar')), findsOneWidget);
    await _shot(tester, 'admin-casa');
    await tester.tap(find.byKey(const Key('admin-aprovar')));
    await _frames(tester);
    expect(find.byKey(const Key('admin-casa-aviso')), findsOneWidget);

    await tester.tap(find.text('Jogadores'));
    await _frames(tester);
    expect(find.text('Conta em revisão'), findsOneWidget);
    await _shot(tester, 'admin-jogadores');
    await tester.tap(find.text('Ana Jogadora'));
    await _frames(tester);
    expect(find.textContaining('Scape Points'), findsWidgets);
    await _shot(tester, 'admin-jogador');

    await tester.tap(find.text('Regras'));
    await _frames(tester);
    expect(find.text('Salvar regras'), findsOneWidget);
    await _shot(tester, 'admin-regras');

    await tester.tap(find.text('Ganhos'));
    await _frames(tester);
    expect(find.byKey(const Key('admin-taxa-asaas')), findsOneWidget);
    expect(find.textContaining('dívida tudo ou nada'), findsOneWidget);
    await _shot(tester, 'admin-ganhos');

    api.feeCents = null;
    await tester.tap(find.text('30 dias'));
    await _frames(tester);
    expect(find.byKey(const Key('admin-taxa-ausente')), findsOneWidget);

    await tester.tap(find.text('Destaques'));
    await _frames(tester);
    expect(find.text('O Cofre'), findsOneWidget);
    expect(find.text('Noite de estreia'), findsOneWidget);
    await _shot(tester, 'admin-destaques');

    _size(tester, const Size(390, 844));
    await _frames(tester);
    expect(find.byKey(const Key('admin-shell')), findsOneWidget);
    await _shot(tester, 'admin-celular');
  });
}

void _size(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, AdminApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        adminApiProvider.overrideWithValue(api),
        adminSessionProvider.overrideWith(ReadyAdminSession.new),
      ],
      child: const AdminApp(),
    ),
  );
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

class ReadyAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _frames(tester);
  final boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/opt/cursor/artifacts/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
