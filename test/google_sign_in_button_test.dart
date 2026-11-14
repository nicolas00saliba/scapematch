import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  testWidgets('login e cadastro mostram Continuar com Google', (tester) async {
    final auth = FakeAuthRepository(signedIn: null);
    final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));
    await _pump(tester, const Size(390, 1400), database, auth, const LoginScreen());

    final button = find.byKey(AppKeys.googleSignIn);
    expect(button, findsOneWidget);
    expect(find.text('Continuar com Google'), findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.googleSignInCalls, 1);
    expect(find.text(googleExampleMessage), findsOneWidget);

    await _pump(
      tester,
      const Size(390, 1600),
      database,
      auth,
      const SignupScreen(),
    );
    expect(find.byKey(AppKeys.googleSignIn), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  FakeDatabase database,
  FakeAuthRepository auth,
  Widget home,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 4, 15))),
        cityRepositoryProvider.overrideWithValue(
          FakeCityRepository(database, latency: Duration.zero),
        ),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
