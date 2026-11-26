import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/password_recovery.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_password_reset.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_login_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_signup_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_terms_screen.dart';
import 'package:scapematch_parceiro/parceiro_app.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o redirect do Parceiro cai na raiz pública', () {
    expect(
      partnerPasswordResetRedirect(
        page: Uri.parse('https://parceiro.escapematch.com.br/login'),
        baseHref: '/',
      ),
      'https://parceiro.escapematch.com.br/',
    );
    expect(
      partnerPasswordResetRedirect(
        page: Uri.parse(
          'https://nicolas00saliba.github.io/scapematch/parceiro/login',
        ),
        baseHref: '/scapematch/parceiro/',
      ),
      'https://nicolas00saliba.github.io/scapematch/parceiro/',
    );
    expect(
      partnerPasswordResetRedirect(
        page: Uri.parse('https://parceiro.escapematch.com.br/'),
        baseHref: '',
      ),
      'https://parceiro.escapematch.com.br/',
    );
  });

  test('a demonstração não chama o Supabase', () async {
    expect(scapeUsesLiveBackend, isFalse);
    expect(await requestPartnerPasswordReset('casa@exemplo.com'), isNull);
    expect(await requestPartnerPasswordReset('sem-arroba'), isNotNull);
    expect(await updatePartnerPassword('senha1234'), passwordResetDemoMessage);
  });

  testWidgets('cadastro da casa bloqueia senhas diferentes', (tester) async {
    await _pump(tester, const PartnerSignupScreen());
    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupPassword),
      'Casa1234',
    );
    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupConfirmPassword),
      'Casa5678',
    );
    await tester.pump();

    expect(find.text(passwordMismatchMessage), findsOneWidget);
    expect(_submit(tester, PartnerKeys.partnerSubmit).onPressed, isNull);

    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupConfirmPassword),
      'Casa1234',
    );
    await tester.pump();
    expect(find.text(passwordMismatchMessage), findsNothing);
    expect(_submit(tester, PartnerKeys.partnerSubmit).onPressed, isNotNull);
  });

  testWidgets('o olho do login da casa mostra e esconde a senha', (
    tester,
  ) async {
    await _pump(tester, const PartnerLoginScreen());
    await _toggle(tester, PartnerKeys.partnerPassword);
  });

  testWidgets('o olho dos termos da casa mostra e esconde a senha', (
    tester,
  ) async {
    await _pump(tester, const PartnerTermsScreen());
    await _toggle(tester, PartnerKeys.partnerSignupPassword);
  });

  testWidgets('esqueci a senha na demonstração não chama o Auth', (
    tester,
  ) async {
    expect(scapeUsesLiveBackend, isFalse);
    await _pump(tester, const PartnerLoginScreen());
    await tester.ensureVisible(find.byKey(PartnerKeys.partnerForgotPassword));
    await tester.tap(find.byKey(PartnerKeys.partnerForgotPassword));
    await tester.pumpAndSettle();

    expect(find.text('Nova senha'), findsOneWidget);
    await tester.enterText(
      find.byKey(PartnerKeys.partnerResetEmail),
      'casa@exemplo.com',
    );
    await tester.tap(find.byKey(PartnerKeys.partnerResetSubmit));
    await tester.pumpAndSettle();
    expect(find.text(passwordResetDemoMessage), findsOneWidget);
    expect(find.textContaining('casa@exemplo.com'), findsNothing);
  });

  testWidgets('o aviso não diz se o e-mail existe', (tester) async {
    addTearDown(() => scapeUsesLiveBackend = false);
    scapeUsesLiveBackend = true;
    String? asked;
    await _pump(
      tester,
      PartnerLoginScreen(
        requestReset: (email) async {
          asked = email;
          return null;
        },
      ),
    );
    await tester.ensureVisible(find.byKey(PartnerKeys.partnerForgotPassword));
    await tester.tap(find.byKey(PartnerKeys.partnerForgotPassword));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PartnerKeys.partnerResetEmail),
      'casa@exemplo.com',
    );
    await tester.tap(find.byKey(PartnerKeys.partnerResetSubmit));
    await tester.pumpAndSettle();

    expect(asked, 'casa@exemplo.com');
    expect(find.text(passwordResetSentMessage), findsOneWidget);
    expect(find.textContaining('casa@exemplo.com'), findsNothing);
  });

  testWidgets('o retorno do link pede a senha nova da casa', (tester) async {
    addTearDown(passwordRecoverySignal.clear);
    passwordRecoverySignal.mark();
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        child: _app(
          const PartnerPasswordRecovery(child: Text('painel da casa')),
        ),
      ),
    );
    expect(find.text('painel da casa'), findsNothing);
    expect(find.text('Confirmar senha'), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.newPassword), 'Casa1234');
    await tester.enterText(find.byKey(AppKeys.confirmNewPassword), 'Casa1234');
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.newPasswordSubmit));
    await tester.pumpAndSettle();

    expect(find.text(passwordResetDemoMessage), findsOneWidget);
    expect(find.text('painel da casa'), findsNothing);
    expect(scapeUsesLiveBackend, isFalse);
  });
}

FilledButton _submit(WidgetTester tester, Key key) {
  return tester.widget<FilledButton>(find.byKey(key));
}

Future<void> _toggle(WidgetTester tester, Key key) async {
  final field = find.byKey(key);
  expect(tester.widget<TextField>(field).obscureText, isTrue);
  expect(_icon(tester, field, Icons.visibility).semanticLabel, 'Mostrar senha');
  expect(_button(tester, field).tooltip, 'Mostrar senha');
  await tester.ensureVisible(_buttonFinder(field));
  await tester.tap(_buttonFinder(field));
  await tester.pump();
  expect(tester.widget<TextField>(field).obscureText, isFalse);
  expect(
    _icon(tester, field, Icons.visibility_off).semanticLabel,
    'Ocultar senha',
  );
  expect(_button(tester, field).tooltip, 'Ocultar senha');
}

Icon _icon(WidgetTester tester, Finder field, IconData data) {
  return tester.widget<Icon>(
    find.descendant(of: field, matching: find.byIcon(data)),
  );
}

IconButton _button(WidgetTester tester, Finder field) {
  return tester.widget<IconButton>(_buttonFinder(field));
}

Finder _buttonFinder(Finder field) {
  return find.descendant(of: field, matching: find.byType(IconButton));
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(retry: noAutomaticRetry, child: _app(home)),
  );
  await tester.pump();
}

Widget _app(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    home: home,
  );
}
