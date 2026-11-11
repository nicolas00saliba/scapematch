import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:scapematch_admin/admin_reward_fields.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  test('pontos-base, pontos do jogador e contagens', () {
    expect(
      rewardEquivalence(
        field: rewardFieldById('c2c_bps'),
        raw: '250',
        pointValueCents: 1,
      ),
      '250 pontos-base = 2,5% da reserva',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('empty_slot_house_share_bps'),
        raw: '5000',
        pointValueCents: 1,
      ),
      '5.000 pontos-base = 50% do extra',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('redeem_max_bps'),
        raw: '3000',
        pointValueCents: 1,
      ),
      '3.000 pontos-base = 30% da reserva',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('welcome_points'),
        raw: '100',
        pointValueCents: 1,
      ),
      '100 pontos = R\$ 1,00',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('redeem_min_points'),
        raw: '1000',
        pointValueCents: 1,
      ),
      '1.000 pontos = R\$ 10,00',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('welcome_points'),
        raw: '100',
        pointValueCents: 2,
      ),
      '100 pontos = R\$ 2,00',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('tier_silver_active'),
        raw: '5',
        pointValueCents: 1,
      ),
      '5 indicações',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('tier_active_days'),
        raw: '90',
        pointValueCents: 1,
      ),
      '90 dias',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('payer_referred_account_cap'),
        raw: '0',
        pointValueCents: 1,
      ),
      'desligado',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('point_value_cents'),
        raw: '1',
        pointValueCents: 1,
      ),
      '1 ponto = R\$ 0,01',
    );
    expect(
      rewardEquivalence(
        field: rewardFieldById('c2c_bps'),
        raw: '',
        pointValueCents: 1,
      ),
      '—',
    );
  });

  testWidgets('a tela mostra a leitura e atualiza enquanto digita', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    _size(tester, const Size(1280, 4600));
    await _pump(tester, api);
    expect(find.textContaining('referral_program_settings'), findsNothing);
    expect(find.byKey(const Key('admin-regras-intro')), findsOneWidget);
    expect(_equiv(tester, 'c2c_bps'), '250 pontos-base = 2,5% da reserva');
    expect(_equiv(tester, 'b2b_bps'), '500 pontos-base = 5% da reserva');
    expect(
      _equiv(tester, 'cashback_bps'),
      '100 pontos-base = 1% do valor pago',
    );
    expect(
      _equiv(tester, 'redeem_max_bps'),
      '3.000 pontos-base = 30% da reserva',
    );
    expect(
      _equiv(tester, 'empty_slot_house_share_bps'),
      '5.000 pontos-base = 50% do extra',
    );
    expect(_equiv(tester, 'welcome_points'), '100 pontos = R\$ 1,00');
    expect(_equiv(tester, 'redeem_min_points'), '1.000 pontos = R\$ 10,00');
    expect(
      _equiv(tester, 'tier_silver_bonus_bps'),
      '50 pontos-base = 0,5% a mais',
    );
    expect(_equiv(tester, 'tier_silver_active'), '5 indicações');
    expect(_equiv(tester, 'tier_silver_active').contains('%'), isFalse);
    expect(_equiv(tester, 'tier_active_days'), '90 dias');
    expect(_equiv(tester, 'payer_referred_account_cap'), '3 contas');
    expect(_equiv(tester, 'point_value_cents'), '1 ponto = R\$ 0,01');
    expect(find.textContaining('Cada ponto vale R\$ 0,01'), findsWidgets);
    await _shot(tester, 'admin-regras-desktop');

    await tester.enterText(
      find.byKey(const Key('admin-regra-c2c_bps')),
      '1000',
    );
    await tester.pump();
    expect(_equiv(tester, 'c2c_bps'), '1.000 pontos-base = 10% da reserva');

    await tester.enterText(
      find.byKey(const Key('admin-regra-point_value_cents')),
      '2',
    );
    await tester.pump();
    expect(_equiv(tester, 'welcome_points'), '100 pontos = R\$ 2,00');
    expect(_equiv(tester, 'redeem_min_points'), '1.000 pontos = R\$ 20,00');
    expect(_equiv(tester, 'point_value_cents'), '1 ponto = R\$ 0,02');
    expect(find.textContaining('Cada ponto vale R\$ 0,02'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('admin-regra-payer_referred_account_cap')),
      '0',
    );
    await tester.pump();
    expect(_equiv(tester, 'payer_referred_account_cap'), 'desligado');
    expect(_equiv(tester, 'payer_referred_account_cap').contains('%'), isFalse);

    await tester.tap(find.byKey(const Key('admin-salvar-regras')));
    await tester.pump();
    await tester.pump();
    expect(api.settings['c2c_bps'], 1000);
    expect(api.settings['welcome_points'], 100);
    expect(api.settings['point_value_cents'], 2);
    expect(api.settings['redeem_max_bps'], 3000);
    expect(api.settings['payer_referred_account_cap'], 0);
    expect(find.text('Regras gravadas.'), findsOneWidget);

    _size(tester, const Size(390, 5200));
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, MemoryAdminApi());
    expect(_equiv(tester, 'c2c_bps'), '250 pontos-base = 2,5% da reserva');
    expect(_equiv(tester, 'welcome_points'), '100 pontos = R\$ 1,00');
    await _shot(tester, 'admin-regras-celular');
  });
}

String _equiv(WidgetTester tester, String id) {
  return tester.widget<Text>(find.byKey(Key('admin-regra-equiv-$id'))).data!;
}

void _size(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logical;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, MemoryAdminApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [adminApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: adminTheme(),
        home: const Scaffold(body: RegrasPage()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _shot(WidgetTester tester, String name) async {
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
