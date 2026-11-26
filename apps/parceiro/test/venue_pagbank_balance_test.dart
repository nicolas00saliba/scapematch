import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_pagbank_balance.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_home_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  final shots = Platform.environment['SCAPEMATCH_PARTNER_SHOTS'] == '1';

  setUpAll(() async {
    if (shots) await _loadFonts();
  });

  testWidgets('saldo PagBank mostra disponível, bloqueado e retido', (
    tester,
  ) async {
    await _pump(
      tester,
      const VenuePagbankBalance.live(
        availableCents: 1250,
        blockedCents: 300,
        heldCents: 50,
      ),
      shot: shots ? 'saldo-pagbank.png' : null,
    );

    expect(find.text(PartnerMessages.pagbankBalanceTitle), findsOneWidget);
    expect(find.text(formatPrice(1250)), findsOneWidget);
    expect(find.text(PartnerMessages.pagbankBalanceBlocked), findsOneWidget);
    expect(find.text(formatPrice(300)), findsOneWidget);
    expect(find.text(PartnerMessages.pagbankBalanceHeld), findsOneWidget);
    expect(find.text(formatPrice(50)), findsOneWidget);
    expect(find.byKey(PartnerKeys.reservationsLedger), findsOneWidget);
    expect(find.text(formatPrice(18000)), findsOneWidget);
    expect(find.text(PartnerMessages.pagbankBalanceUnavailable), findsNothing);
    expect(
      find.text(PartnerMessages.reservationsLedgerEstimated),
      findsNothing,
    );
  });

  testWidgets('403 vira aviso e o livro fica como estimativa', (tester) async {
    await _pump(
      tester,
      const VenuePagbankBalance.unavailable(),
      shot: shots ? 'saldo-pagbank-indisponivel.png' : null,
    );

    expect(
      find.text(PartnerMessages.pagbankBalanceUnavailable),
      findsOneWidget,
    );
    expect(
      find.text(PartnerMessages.pagbankBalanceUnavailableBody),
      findsOneWidget,
    );
    expect(
      find.text(PartnerMessages.reservationsLedgerEstimated),
      findsOneWidget,
    );
    expect(find.byKey(PartnerKeys.pagbankBalanceAvailable), findsNothing);
    expect(find.text(formatPrice(18000)), findsOneWidget);
    expect(find.text('R\$ 0,00'), findsNothing);
  });

  testWidgets('sem consulta PagBank o livro não é chamado de saldo PagBank', (
    tester,
  ) async {
    await _pump(tester, const VenuePagbankBalance.absent());

    expect(find.byKey(PartnerKeys.pagbankBalance), findsNothing);
    expect(find.text(PartnerMessages.pagbankBalanceUnavailable), findsNothing);
    expect(find.text(PartnerMessages.reservationsLedgerTitle), findsOneWidget);
    expect(
      find.text(PartnerMessages.reservationsLedgerEstimated),
      findsNothing,
    );
    expect(find.text(formatPrice(18000)), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  VenuePagbankBalance balance, {
  String? shot,
}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        venueWithdrawalRepositoryProvider.overrideWithValue(
          MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
        ),
        venuePagbankBalanceRepositoryProvider.overrideWithValue(
          MemoryVenuePagbankBalanceRepository(balance),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: PartnerHome(snapshot: _snapshot()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (shot != null) await _shot(tester, shot);
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name').writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}

Future<void> _loadFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  String? fonts;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
      fonts = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (fonts == null) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$fonts/$name').readAsBytesSync();
    return ByteData.view(data.buffer);
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

PartnerSnapshot _snapshot() {
  return PartnerSnapshot(
    house: const EscapeHouse(
      id: 'casa-1',
      cityId: 'curitiba',
      name: 'Casa do Saldo',
      neighborhood: 'Centro',
      latitude: -25.4,
      longitude: -49.2,
      receivesPayments: true,
    ),
    now: DateTime(2026, 11, 12, 12),
    grossCents: 20000,
    commissionCents: 2000,
    netCents: 18000,
    reservedCents: 4000,
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
