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
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  test('22,5 vira 2250 pontos-base e passa de 30% não entra', () {
    expect(bpsFromPercent('22,5'), 2250);
    expect(bpsFromPercent('22.5'), 2250);
    expect(bpsFromPercent('30'), 3000);
    expect(bpsFromPercent('30,01'), isNull);
    expect(bpsFromPercent('22,555'), isNull);
    expect(percentBps(2250), '22,5%');
    expect(percentInput(2000), '20');
  });

  testWidgets('login mostra o EscapeMatch Admin', (tester) async {
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(SignedOutAdminSession.new),
        ],
        child: const AdminApp(),
      ),
    );
    await _frames(tester);
    expect(find.byKey(const Key('admin-login')), findsOneWidget);
    expect(find.text('EscapeMatch Admin'), findsOneWidget);
    await _shot(tester, 'admin-login-desktop');
    _size(tester, const Size(390, 844));
    await _frames(tester);
    await _shot(tester, 'admin-login-mobile');
    _size(tester, const Size(1280, 900));
    await _frames(tester);
    await tester.enterText(
      find.byKey(const Key('admin-email')),
      'admin@scapematch.exemplo',
    );
    await _frames(tester);
  });

  testWidgets('a verificação pede o código antes do painel', (tester) async {
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(VerifyAdminSession.new),
        ],
        child: const AdminApp(),
      ),
    );
    await _frames(tester);
    expect(find.byKey(const Key('admin-mfa')), findsOneWidget);
    expect(find.text('Código do autenticador'), findsOneWidget);
    expect(find.byKey(const Key('admin-casas')), findsNothing);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '482193');
    await _frames(tester);
    await _shot(tester, 'admin-mfa');
  });

  testWidgets('painel mostra casas, ganhos e a taxa só quando existe', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    _size(tester, const Size(1280, 900));
    await _pump(tester, api);
    expect(find.byKey(const Key('admin-casas')), findsOneWidget);
    await _shot(tester, 'admin-header-desktop');
    expect(find.text('Ninja Escape'), findsOneWidget);
    expect(find.text('Casa da Fila'), findsOneWidget);
    await _shot(tester, 'admin-casas');

    await tester.tap(find.text('Casa da Fila'));
    await _frames(tester);
    expect(find.byKey(const Key('admin-aprovar')), findsOneWidget);
    expect(find.text('25% oficial'), findsNothing);
    expect(find.text('20% Ninja'), findsNothing);
    expect(find.byKey(const Key('admin-comissao')), findsOneWidget);
    await _shot(tester, 'admin-casa');
    await tester.enterText(find.byKey(const Key('admin-comissao')), '22,5');
    await _frames(tester);
    await _shot(tester, 'admin-comissao');
    await tester.tap(find.byKey(const Key('admin-gravar-comissao')));
    await _frames(tester);
    expect(find.text('Confirmar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await _frames(tester);
    expect(find.textContaining('Comissão gravada'), findsNothing);
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
    expect(find.byKey(const Key('admin-passivo')), findsOneWidget);
    expect(
      find.textContaining('2.000 pontos ainda não usados'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Crédito de casa ainda pendente'),
      findsOneWidget,
    );
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
    await _shot(tester, 'admin-header-mobile');
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

class SignedOutAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(phase: AdminPhase.signedOut);
  }
}

class VerifyAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.verify,
      email: 'admin@scapematch.exemplo',
    );
  }
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
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
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
  });
}
