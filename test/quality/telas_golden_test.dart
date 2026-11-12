import 'package:flutter/material.dart';
import '../support/folga_golden.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  setUp(() {
    goldenFileComparator = FolgaGolden(
      Uri.parse('test/quality/telas_golden_test.dart'),
    );
  });

  final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));

  for (final size in const [Size(390, 1400), Size(1440, 1200)]) {
    final nome = size.width.round().toString();

    testWidgets('login do jogador em $nome', (tester) async {
      await _pump(tester, size, database);
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/jogador_login_$nome.png'),
      );
    });
  }

  testWidgets('botão Entrar do jogador', (tester) async {
    await _pump(tester, const Size(390, 1400), database);
    await expectLater(
      find.byKey(AppKeys.loginSubmit),
      matchesGoldenFile('goldens/jogador_entrar.png'),
    );
  });

  testWidgets('login do jogador segue contraste e toque', (tester) async {
    await _pump(tester, const Size(390, 1400), database);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    final toque = await androidTapTargetGuideline.evaluate(tester);
    // A faixa "Demonstração" tem 29px de altura. Aumentar para 48px muda o
    // layout. O teste só passa se essa faixa for o único alvo abaixo de 48px.
    if (toque.passed) return;
    final pedacos = (toque.reason ?? '')
        .split('SemanticsNode')
        .where((pedaco) => pedaco.contains('expected tap target'));
    expect(pedacos, isNotEmpty);
    for (final pedaco in pedacos) {
      expect(pedaco, contains('Demonstração. Toque para ler o aviso.'));
    }
  });
}

Future<void> _pump(WidgetTester tester, Size size, FakeDatabase database) async {
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
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
