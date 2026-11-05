import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/data/signup_confirmation.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_success_view.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('the check, the address and the resend wait', (tester) async {
    var logins = 0;
    var resent = 0;
    _wide(tester);
    await tester.pumpWidget(
      _host(
        SignupSuccessView(
          email: 'ana@exemplo.com',
          cooldown: const Duration(seconds: 2),
          onLogin: () => logins += 1,
          onResend: () async {
            resent += 1;
            return null;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(AppKeys.signupSuccessCheck), findsOneWidget);
    expect(find.text('Conta criada'), findsOneWidget);
    expect(
      find.textContaining(
        'Confirme o e-mail que enviamos para ana@exemplo.com e depois entre.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ir para o login'), findsOneWidget);
    expect(find.text('Reenviar e-mail'), findsOneWidget);
    expect(find.text('Você pode reenviar em 2s.'), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);

    await tester.tap(find.byKey(AppKeys.signupGoToLogin));
    expect(logins, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(_resend(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(AppKeys.signupResendEmail));
    await tester.pump();
    expect(resent, 1);
    expect(find.textContaining(signupResendNeutralMessage), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);
    expect(find.textContaining('Você pode reenviar em 2s.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed resend stays on the screen', (tester) async {
    _wide(tester);
    await tester.pumpWidget(
      _host(
        SignupSuccessView(
          email: 'ana@exemplo.com',
          cooldown: Duration.zero,
          onLogin: () {},
          onResend: () async => 'Sem conexão. Tente de novo.',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.signupResendEmail));
    await tester.pump();
    expect(find.text('Sem conexão. Tente de novo.'), findsOneWidget);
    expect(_resend(tester).onPressed, isNotNull);
  });

  testWidgets('player signup opens the success screen and then login', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      signedIn: null,
      awaitEmailConfirmation: true,
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 4, 15))),
      ],
    );
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/cadastro');
    await tester.pumpAndSettle();
    await _fillPlayer(tester, 'ana@exemplo.invalid');
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(AppKeys.signupSuccess), findsOneWidget);
    expect(find.textContaining('ana@exemplo.invalid'), findsOneWidget);
    expect(auth.signedInUser, isNull);
    expect(_resend(tester).onPressed, isNull);

    await tester.tap(find.byKey(AppKeys.signupGoToLogin));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('player resend asks the repository and then waits again', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      signedIn: null,
      awaitEmailConfirmation: true,
    );
    _wide(tester);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 11, 4, 15)),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const SignupScreen(resendCooldown: Duration(seconds: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillPlayer(tester, 'ana@exemplo.invalid');
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(_resend(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(AppKeys.signupResendEmail));
    await tester.pump();
    expect(auth.resentSignupEmails, ['ana@exemplo.invalid']);
    expect(find.textContaining(signupResendNeutralMessage), findsOneWidget);
    expect(_resend(tester).onPressed, isNull);

    auth.resendSignupError =
        'Muitas tentativas. Espere um pouco e tente de novo.';
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(AppKeys.signupResendEmail));
    await tester.pump();
    expect(find.textContaining('Muitas tentativas'), findsOneWidget);
  });

  test('resend does not reveal whether the account exists', () {
    expect(
      resendFailureMessage(const AuthException('User already registered')),
      isNull,
    );
    expect(resendFailureMessage(const AuthException('user not found')), isNull);
    expect(
      resendFailureMessage(Exception('signup failed for this address')),
      isNull,
    );
    expect(
      resendFailureMessage(const AuthException('email rate limit exceeded')),
      signupResendRateLimitMessage,
    );
    expect(
      resendFailureMessage(
        const AuthException(
          'For security purposes, you can only request this after 60 seconds',
        ),
      ),
      signupResendRateLimitMessage,
    );
    expect(
      resendFailureMessage(Exception('SocketException: failed host lookup')),
      signupResendOfflineMessage,
    );
    expect(signupResendNeutralMessage, isNot(contains('@')));
  });

  test('the sentinel is not a signed-in account', () async {
    final auth = FakeAuthRepository(
      signedIn: null,
      awaitEmailConfirmation: true,
    );
    final error = await auth.signUp(
      name: 'Ana',
      email: 'ana@exemplo.invalid',
      password: 'senha',
      birthDate: DateTime(1990, 1, 1),
      now: DateTime(2026, 11, 4, 15),
      acceptedTerms: true,
    );
    expect(error, signupAwaitingEmailConfirmation);
    expect(auth.signedInUser, isNull);
    expect(auth.acceptances, isEmpty);
  });
}

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

OutlinedButton _resend(WidgetTester tester) {
  return tester.widget<OutlinedButton>(find.byKey(AppKeys.signupResendEmail));
}

Future<void> _fillPlayer(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(AppKeys.signupName), 'Ana');
  await tester.enterText(find.byKey(AppKeys.signupEmail), email);
  await tester.enterText(find.byKey(AppKeys.signupPassword), 'senha');
  await tester.enterText(find.byKey(AppKeys.signupBirthDay), '1');
  await tester.enterText(find.byKey(AppKeys.signupBirthMonth), '1');
  await tester.enterText(find.byKey(AppKeys.signupBirthYear), '1990');
  await tester.ensureVisible(find.byKey(AppKeys.signupTerms));
  await tester.tap(find.byKey(AppKeys.signupTerms));
  await tester.pump();
  await tester.ensureVisible(find.byKey(AppKeys.signupSubmit));
}

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(body: child),
  );
}
