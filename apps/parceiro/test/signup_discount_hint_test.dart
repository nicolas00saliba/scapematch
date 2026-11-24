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
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/scape_points/data/reward_rules_store.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_referral_code.dart';

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

  testWidgets('a casa mostra o desconto e o ganho do código', (tester) async {
    const rules = PublicRewardRules(
      firstBookingDiscountBps: 2000,
      organicFirstBookingDiscountBps: 1000,
      b2cBps: 500,
      b2bBps: 500,
    );
    final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 11, 4, 15)),
          ),
          cityRepositoryProvider.overrideWithValue(
            FakeCityRepository(database, latency: Duration.zero),
          ),
          partnerSessionProvider.overrideWith(_OpenSession.new),
          rewardRulesStoreProvider.overrideWithValue(
            RewardRulesStore(current: rules),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          home: const PartnerVenueScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text(
        'Com o código, 20% de desconto na primeira sessão. Sem código, 10%.',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Com o código, 20% de desconto na primeira sessão. Sem código, 10%.',
      ),
      findsOneWidget,
    );
    await _shot(tester, 'cadastro-casa');
  });

  testWidgets('o código da casa lembra o ganho', (tester) async {
    const rules = PublicRewardRules(b2cBps: 500, b2bBps: 500);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          rewardRulesStoreProvider.overrideWithValue(
            RewardRulesStore(current: rules),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: VenueReferralCode())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ganhe até 5% do que cada pessoa indicada gastar na EscapeMatch, ou 5% do faturamento de uma casa indicada.',
      ),
      findsOneWidget,
    );
    await _shot(tester, 'codigo-da-casa');
  });
}

class _OpenSession extends PartnerSessionController {
  @override
  PartnerAccount? build() {
    return const PartnerAccount(
      email: 'casa@exemplo.invalid',
      houseId: '',
      houseName: '',
      userId: 'user-1',
      venueStatus: null,
    );
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
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
}
