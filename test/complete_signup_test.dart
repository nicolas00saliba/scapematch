import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/complete_signup_screen.dart';
import 'package:scapematch/features/legal/legal_documents.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  testWidgets('Google sem aceite ou menor de idade não conclui', (tester) async {
    final auth = FakeAuthRepository(
      signedIn: const CurrentUser(
        id: 'google-1',
        displayName: 'Ana',
        googleProfilePending: true,
      ),
    );
    await _pump(tester, auth);
    await tester.enterText(find.byKey(AppKeys.signupBirthDay), '1');
    await tester.enterText(find.byKey(AppKeys.signupBirthMonth), '1');
    await tester.enterText(find.byKey(AppKeys.signupBirthYear), '2010');
    await tester.tap(find.byKey(AppKeys.completeSignup));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.termsRequired), findsOneWidget);
    expect(auth.signedInUser?.googleProfilePending, isTrue);

    await tester.tap(find.byKey(AppKeys.signupTerms));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.completeSignup));
    await tester.pumpAndSettle();
    expect(find.text(LegalDocuments.under18), findsOneWidget);
    expect(find.text('home-ok'), findsNothing);
  });

  testWidgets('Google adulto com aceite entra', (tester) async {
    final auth = FakeAuthRepository(
      signedIn: const CurrentUser(
        id: 'google-1',
        displayName: 'Ana',
        googleProfilePending: true,
      ),
    );
    await _pump(tester, auth);
    await tester.enterText(find.byKey(AppKeys.signupBirthDay), '2');
    await tester.enterText(find.byKey(AppKeys.signupBirthMonth), '2');
    await tester.enterText(find.byKey(AppKeys.signupBirthYear), '1990');
    await tester.tap(find.byKey(AppKeys.signupTerms));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.completeSignup));
    await tester.pumpAndSettle();
    expect(find.text('home-ok'), findsOneWidget);
    expect(auth.signedInUser?.googleProfilePending, isFalse);
    expect(auth.signedInUser?.birthDate, DateTime(1990, 2, 2));
    expect(auth.acceptances, isNotEmpty);
  });
}

Future<void> _pump(WidgetTester tester, FakeAuthRepository auth) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/cadastro/completar',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Text('home-ok'),
      ),
      GoRoute(
        path: '/cadastro/completar',
        builder: (context, state) => const CompleteSignupScreen(),
      ),
      GoRoute(
        path: '/legal/:document',
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Text('login-ok'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 4, 15))),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
