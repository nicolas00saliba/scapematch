import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/complete_signup_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/scape_points/data/reward_rules_store.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch/features/scape_points/presentation/scape_points_view.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  setUpAll(() async {
    const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
    const alt = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
    final root = Directory(dir).existsSync() ? dir : alt;
    if (!File('$root/Roboto-Regular.ttf').existsSync()) return;
    Future<ByteData> bytes(String name) async {
      final data = File('$root/$name').readAsBytesSync();
      return ByteData.view(Uint8List.fromList(data).buffer);
    }

    final roboto = FontLoader('Roboto')
      ..addFont(bytes('Roboto-Regular.ttf'))
      ..addFont(bytes('Roboto-Medium.ttf'));
    await roboto.load();
  });
  test('o lembrete usa a regra, não um número solto', () {
    const rules = PublicRewardRules(
      firstBookingDiscountBps: 1800,
      organicFirstBookingDiscountBps: 800,
      c2cHighBps: 400,
      c2bBps: 300,
    );
    expect(referralCodeHint(rules), contains('18%'));
    expect(referralCodeHint(rules), contains('8%'));
    expect(referralCodeHint(rules), isNot(contains('20%')));
    expect(ownReferralHint(rules), contains('4%'));
    expect(ownReferralHint(rules), contains('3%'));
  });

  testWidgets('o cadastro mostra o desconto da primeira sessão', (
    tester,
  ) async {
    final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));
    const rules = PublicRewardRules(
      firstBookingDiscountBps: 2000,
      organicFirstBookingDiscountBps: 1000,
    );
    await _pump(tester, database, const SignupScreen(), rules, signedIn: null);
    await tester.ensureVisible(find.byKey(AppKeys.signupReferral));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Com o código, 20% de desconto na primeira sessão. Sem código, 10%.',
      ),
      findsOneWidget,
    );
    await _shot(tester, find.byKey(AppKeys.signupReferral), 'cadastro-jogador');

    await _pump(
      tester,
      database,
      const CompleteSignupScreen(),
      rules,
      signedIn: const CurrentUser(
        id: 'google-1',
        displayName: 'Ana',
        googleProfilePending: true,
      ),
    );
    await tester.ensureVisible(find.byKey(AppKeys.signupReferral));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Com o código, 20% de desconto na primeira sessão. Sem código, 10%.',
      ),
      findsOneWidget,
    );
    await _shot(
      tester,
      find.byKey(AppKeys.signupReferral),
      'cadastro-jogador-google',
    );

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: ScapePointsBody(preview: ScapeWallet.sample)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Ganhe até 5%'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ganhe até 5%'), findsOneWidget);
    await _shot(tester, find.textContaining('Ganhe até 5%'), 'codigo-do-jogador');
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeDatabase database,
  Widget home,
  PublicRewardRules rules, {
  required CurrentUser? signedIn,
}) async {
  tester.view.physicalSize = const Size(390, 1800);
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
          FakeAuthRepository(signedIn: signedIn),
        ),
        rewardRulesStoreProvider.overrideWithValue(
          RewardRulesStore(current: rules),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, Finder anchor, String name) async {
  final boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  ) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  final file = File('/opt/cursor/artifacts/$name.png');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
  });
  expect(anchor, findsOneWidget);
}
