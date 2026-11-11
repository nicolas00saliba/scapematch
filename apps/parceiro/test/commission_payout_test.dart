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
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch_parceiro/features/partner/data/commission_admin_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_payout_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/commission_admin_panel.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_home_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_payout_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('admin grava 15% na plataforma e 8% numa casa', (tester) async {
    await tester.runAsync(_loadFonts);
    final book = PlatformSettingsBook();
    final repo = MemoryCommissionAdminRepository(
      book: book,
      houses: const {'v1': 'Casa Sem Subconta'},
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [commissionAdminRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: _shotTheme(),
          home: const Scaffold(body: CommissionAdminPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EscapeMatch'), findsOneWidget);
    expect(find.text('Casa Sem Subconta'), findsOneWidget);
    expect(find.text('25%'), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const Key('commission-field-platform')),
      '15%',
    );
    await tester.tap(find.byKey(PartnerKeys.savePlatformCommission));
    await tester.pumpAndSettle();
    expect(book.settings.commissionBps, 1500);
    expect(book.audit.single.actorId, 'admin');
    expect(book.audit.single.beforeBps, 2500);
    expect(book.audit.single.afterBps, 1500);
    expect(find.text('15%'), findsNWidgets(2));

    await tester.enterText(find.byKey(const Key('commission-field-v1')), '8');
    await tester.tap(find.byKey(PartnerKeys.saveVenueCommission('v1')));
    await tester.pumpAndSettle();
    expect(book.settings.rateFor('v1'), 800);
    expect(book.settings.rateFor('outra'), 1500);
    expect(find.text('8%'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('commission-field-platform')),
      '31%',
    );
    await tester.tap(find.byKey(PartnerKeys.savePlatformCommission));
    await tester.pumpAndSettle();
    expect(find.text('A comissão fica entre 0 e 30%.'), findsOneWidget);
    expect(book.settings.commissionBps, 1500);
    await _capture(
      tester,
      find.byKey(PartnerKeys.commissionAdmin),
      'comissao-admin',
    );
  });

  testWidgets('a casa aprovada sem subconta oferece nova tentativa', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final rows = [
      const VenuePayoutStatus(
        id: 'v1',
        name: 'Casa Sem Subconta',
        status: 'approved',
        receivesPayments: false,
      ),
      const VenuePayoutStatus(
        id: 'v2',
        name: 'Casa Pendente',
        status: 'pending',
        receivesPayments: false,
      ),
    ];
    final repo = MemoryVenuePayoutRepository(rows);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [venuePayoutRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: _shotTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: VenuePayoutPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tentar criar subconta de novo'), findsOneWidget);
    expect(find.text('Conta de recebimento pendente'), findsNWidgets(2));
    await _capture(
      tester,
      find.byKey(PartnerKeys.venuePayouts),
      'subcontas-admin',
    );

    await tester.tap(find.byKey(PartnerKeys.retryVenueWallet('v1')));
    await tester.pumpAndSettle();
    expect(repo.retried, ['v1']);
    expect(find.text('Subconta pronta'), findsOneWidget);
    expect(find.text('Tentar criar subconta de novo'), findsNothing);
  });

  testWidgets('a home da casa sem subconta avisa o recebimento', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        child: MaterialApp(
          theme: _shotTheme(),
          home: PartnerHome(snapshot: _snapshot(receivesPayments: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Conta de recebimento pendente'), findsOneWidget);
    await _capture(tester, find.byType(PartnerHome), 'parceiro-sem-subconta');

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        child: MaterialApp(
          theme: _shotTheme(),
          home: PartnerHome(snapshot: _snapshot(receivesPayments: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Conta de recebimento pendente'), findsNothing);
  });
}

PartnerSnapshot _snapshot({required bool receivesPayments}) {
  return PartnerSnapshot(
    house: EscapeHouse(
      id: 'casa-1',
      cityId: 'curitiba',
      name: 'Casa Sem Subconta',
      neighborhood: 'Centro',
      latitude: -25.4,
      longitude: -49.2,
      receivesPayments: receivesPayments,
    ),
    now: DateTime(2026, 11, 5, 12),
    grossCents: 0,
    commissionCents: 0,
    netCents: 0,
    reservedCents: 0,
    lines: const [],
    moneyByGroup: const {},
    groups: const [],
    rooms: const [],
    slotsByRoom: const {},
    absenceCounts: const {},
    absenceMarks: const {},
    standings: const {},
    invoices: const [],
    fiscal: demoHouseFiscal,
  );
}

ThemeData _shotTheme() {
  final theme = buildAppTheme(Brightness.light);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}

Future<void> _loadFonts() async {
  final dir = _fontDir();
  if (dir == null) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

Future<void> _capture(WidgetTester tester, Finder anchor, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  dir.createSync(recursive: true);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}
