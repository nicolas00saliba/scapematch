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
import 'package:scapematch_admin/admin_otp_field.dart';
import 'package:scapematch_admin/admin_session.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
    final mono = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf')
        .readAsBytesSync();
    final monoData = ByteData.sublistView(Uint8List.fromList(mono));
    final monoLoader = FontLoader('monospace')
      ..addFont(Future<ByteData>.value(monoData));
    await monoLoader.load();
  });

  testWidgets('seis quadradinhos aceitam dígito, colar e teclado numérico', (
    tester,
  ) async {
    final controller = TextEditingController();
    String? completed;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: adminTheme(),
        home: Scaffold(
          body: AdminOtpField(
            controller: controller,
            onCompleted: (code) => completed = code,
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('admin-mfa-code')),
    );
    expect(field.keyboardType, TextInputType.number);
    expect(field.autofillHints, contains(AutofillHints.oneTimeCode));

    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '4');
    await tester.pump();
    expect(controller.text, '4');
    expect(find.byKey(const Key('admin-otp-digit-0')), findsOneWidget);
    expect(find.byKey(const Key('admin-otp-active-1')), findsOneWidget);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.byKey(const Key('admin-otp-active-0')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '12ab3');
    await tester.pump();
    expect(controller.text, '123');
    expect(find.byKey(const Key('admin-otp-digit-2')), findsOneWidget);
    expect(find.byKey(const Key('admin-otp-active-3')), findsOneWidget);
    expect(completed, isNull);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '12',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, '12');
    expect(find.byKey(const Key('admin-otp-active-2')), findsOneWidget);
    expect(find.byKey(const Key('admin-otp-digit-2')), findsNothing);

    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123 456');
    await tester.pump();
    expect(controller.text, '123456');
    expect(completed, '123456');
    for (var i = 0; i < 6; i++) {
      expect(find.byKey(Key('admin-otp-digit-$i')), findsOneWidget);
    }

    completed = null;
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('admin-mfa-code')),
      '1234567890',
    );
    await tester.pump();
    expect(controller.text, '123456');
    expect(completed, '123456');
  });

  testWidgets('leitor de tela anuncia o código de 6 dígitos', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: adminTheme(),
        home: Scaffold(
          body: AdminOtpField(controller: controller, onCompleted: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('6 dígitos')), findsWidgets);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '12');
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('6 dígitos')), findsWidgets);
    handle.dispose();
  });

  testWidgets('código inválido limpa os quadradinhos e mantém Confirmar', (
    tester,
  ) async {
    final session = RejectingAdminSession();
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(() => session),
        ],
        child: const AdminApp(),
      ),
    );
    await _frames(tester);
    expect(find.text('Código do autenticador'), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-confirm')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '123');
    await tester.pump();
    await tester.tap(find.byKey(const Key('admin-mfa-confirm')));
    await _frames(tester);
    expect(find.text('O código tem 6 dígitos.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('admin-mfa-code')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('admin-otp-digit-0')), findsNothing);

    final before = session.calls;
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '482193');
    await _frames(tester);
    expect(session.calls, before + 1);
    expect(session.lastCode, '482193');
    expect(find.text('Código não confere. Tente de novo.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('admin-mfa-code')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const Key('admin-mfa-confirm')), findsOneWidget);
    await _shot(tester, 'admin-mfa-erro-desktop');
  });

  testWidgets('verificação no celular e no desktop', (tester) async {
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(QuietVerifySession.new),
        ],
        child: const AdminApp(),
      ),
    );
    await _frames(tester);
    await tester.enterText(find.byKey(const Key('admin-mfa-code')), '482193');
    await _frames(tester);
    expect(find.text('4'), findsWidgets);
    expect(find.byKey(const Key('admin-mfa-confirm')), findsOneWidget);
    await _shot(tester, 'admin-mfa-desktop');

    _size(tester, const Size(390, 844));
    await _frames(tester);
    await _shot(tester, 'admin-mfa-celular');
  });

  testWidgets('cadastro do autenticador no celular e no desktop', (
    tester,
  ) async {
    _size(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminSessionProvider.overrideWith(EnrollAdminSession.new),
        ],
        child: const AdminApp(),
      ),
    );
    await _frames(tester);
    expect(find.text('Cadastre o autenticador'), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-qr')), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-secret')), findsOneWidget);
    expect(find.byKey(const Key('admin-mfa-code')), findsOneWidget);
    await _shot(tester, 'admin-mfa-cadastro-desktop');

    _size(tester, const Size(390, 844));
    await _frames(tester);
    await _shot(tester, 'admin-mfa-cadastro-celular');
  });
}

class RejectingAdminSession extends AdminSessionController {
  String? lastCode;
  var calls = 0;

  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.verify,
      email: 'admin@scapematch.exemplo',
    );
  }

  @override
  Future<void> confirmCode(String raw) async {
    calls += 1;
    lastCode = raw.trim();
    final current = state;
    state = AdminSession(
      phase: current.phase,
      email: current.email,
      error: lastCode!.length == 6
          ? 'Código não confere. Tente de novo.'
          : 'O código tem 6 dígitos.',
    );
  }
}

class QuietVerifySession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.verify,
      email: 'admin@scapematch.exemplo',
    );
  }

  @override
  Future<void> confirmCode(String raw) async {}
}

class EnrollAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.enroll,
      email: 'admin@scapematch.exemplo',
      qrCode:
          'data:image/svg+xml;utf-8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 21 21"><rect width="21" height="21" fill="white"/><rect width="7" height="7" fill="#0F4C4A"/><rect x="1" y="1" width="5" height="5" fill="white"/><rect x="2" y="2" width="3" height="3" fill="#0F4C4A"/><rect x="14" width="7" height="7" fill="#0F4C4A"/><rect x="15" y="1" width="5" height="5" fill="white"/><rect x="16" y="2" width="3" height="3" fill="#0F4C4A"/><rect y="14" width="7" height="7" fill="#0F4C4A"/><rect x="1" y="15" width="5" height="5" fill="white"/><rect x="2" y="16" width="3" height="3" fill="#0F4C4A"/><rect x="9" y="9" width="3" height="3" fill="#0F4C4A"/><rect x="14" y="14" width="3" height="3" fill="#0F4C4A"/></svg>',
      secret: 'JBSWY3DPEHPK3PXP',
    );
  }

  @override
  Future<void> confirmCode(String raw) async {}
}

void _size(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _frames(tester);
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
