import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/auth_redirect.dart';
import 'package:scapematch/features/auth/data/password_recovery.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/new_password_screen.dart';
import 'package:scapematch/features/auth/presentation/password_change_dialog.dart';
import 'package:scapematch/features/auth/presentation/password_recovery_gate.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o link de recuperação marca a troca de senha', () {
    addTearDown(passwordRecoverySignal.clear);
    passwordRecoverySignal.clear();
    final recovery = Uri.parse(
      'https://app.escapematch.com.br/#access_token=aaa&type=recovery',
    );
    expect(passwordRecoveryLink(recovery), isTrue);
    notePasswordRecoveryLink(recovery);
    expect(passwordRecoverySignal.pending, isTrue);

    passwordRecoverySignal.clear();
    notePasswordRecoveryEvent(AuthChangeEvent.signedIn);
    expect(passwordRecoverySignal.pending, isFalse);
    notePasswordRecoveryEvent(AuthChangeEvent.passwordRecovery);
    expect(passwordRecoverySignal.pending, isTrue);

    passwordRecoverySignal.clear();
    notePasswordRecoveryLink(
      Uri.parse('https://app.escapematch.com.br/#access_token=aaa&type=signup'),
    );
    expect(passwordRecoverySignal.pending, isFalse);
    expect(
      webAuthRedirect(
        Uri.parse('https://parceiro.escapematch.com.br/login'),
        '/',
      ),
      'https://parceiro.escapematch.com.br/',
    );
    expect(passwordResetHidesAccount(Exception('user not found')), isTrue);
    expect(passwordResetSentMessage.contains('@'), isFalse);
  });

  testWidgets('cadastro bloqueia senhas diferentes', (tester) async {
    await _pump(tester, const SignupScreen());
    await tester.enterText(find.byKey(AppKeys.signupPassword), 'senha1234');
    await tester.enterText(
      find.byKey(AppKeys.signupConfirmPassword),
      'senha5678',
    );
    await tester.pump();

    expect(find.text(passwordMismatchMessage), findsOneWidget);
    expect(_submit(tester, AppKeys.signupSubmit).onPressed, isNull);

    await tester.enterText(
      find.byKey(AppKeys.signupConfirmPassword),
      'senha1234',
    );
    await tester.pump();
    expect(find.text(passwordMismatchMessage), findsNothing);
    expect(_submit(tester, AppKeys.signupSubmit).onPressed, isNotNull);
  });

  testWidgets('o olho do login mostra e esconde a senha', (tester) async {
    await _pump(tester, const LoginScreen());
    await _toggle(tester, AppKeys.loginPassword);
  });

  testWidgets('o diálogo de trocar senha tem o olho', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showPasswordChangeDialog(
                    context: context,
                    changePassword: (_) async => null,
                  );
                },
                child: const Text('abrir'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await _toggle(tester, AppKeys.changePasswordField);
  });

  testWidgets('esqueci a senha abre o diálogo', (tester) async {
    await _pump(tester, const LoginScreen());
    await tester.ensureVisible(find.byKey(AppKeys.forgotPassword));
    await tester.tap(find.byKey(AppKeys.forgotPassword));
    await tester.pumpAndSettle();

    expect(find.text('Nova senha'), findsOneWidget);
    expect(find.byKey(AppKeys.resetEmail), findsOneWidget);
    await tester.enterText(find.byKey(AppKeys.resetEmail), 'ana@exemplo.com');
    await tester.tap(find.byKey(AppKeys.resetSubmit));
    await tester.pumpAndSettle();
    expect(find.text(passwordResetDemoMessage), findsOneWidget);
  });

  testWidgets('o retorno do link pede a senha nova', (tester) async {
    addTearDown(passwordRecoverySignal.clear);
    passwordRecoverySignal.mark();
    String? saved;
    await tester.pumpWidget(
      _app(
        PasswordRecoveryGate(
          savePassword: (password) async {
            saved = password;
            return null;
          },
          child: const Text('app do jogador'),
        ),
      ),
    );
    expect(find.byType(NewPasswordScreen), findsOneWidget);
    expect(find.text('app do jogador'), findsNothing);

    await tester.enterText(find.byKey(AppKeys.newPassword), 'senha1234');
    await tester.enterText(find.byKey(AppKeys.confirmNewPassword), 'senha5678');
    await tester.pump();
    expect(find.text(passwordMismatchMessage), findsOneWidget);
    expect(_submit(tester, AppKeys.newPasswordSubmit).onPressed, isNull);
    await _toggle(tester, AppKeys.newPassword);

    await tester.enterText(find.byKey(AppKeys.confirmNewPassword), 'senha1234');
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.newPasswordSubmit));
    await tester.pumpAndSettle();
    expect(saved, 'senha1234');
    expect(find.text('app do jogador'), findsOneWidget);
    expect(passwordRecoverySignal.pending, isFalse);
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
