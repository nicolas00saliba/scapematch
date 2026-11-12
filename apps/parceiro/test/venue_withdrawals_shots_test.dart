import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_withdrawals_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('saves the withdrawal screens', (tester) async {
    if (Platform.environment['SCAPEMATCH_PARTNER_SHOTS'] != '1') return;
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await _pump(
      tester,
      MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
      const Size(412, 2900),
      Brightness.light,
    );
    await _shot(tester, dir, 'saldo-saques-celular.png', panel: true);

    await tester.enterText(find.byKey(PartnerKeys.withdrawalAmount), '80,00');
    await tester.tap(find.byKey(PartnerKeys.withdrawalSubmit));
    await tester.pumpAndSettle();
    await _shot(
      tester,
      dir,
      'saldo-saques-senha.png',
      panel: true,
      includeDialog: true,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pump(
      tester,
      MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
      const Size(412, 3200),
      Brightness.light,
    );
    await tester.tap(find.text(PartnerMessages.withdrawalChangeBank));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'saldo-saques-conta.png', panel: true);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pump(
      tester,
      MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
      const Size(1280, 2400),
      Brightness.dark,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'saldo-saques-desktop.png', panel: true);
  });
}

Future<void> _pump(
  WidgetTester tester,
  VenueWithdrawalRepository repo,
  Size size,
  Brightness brightness,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [venueWithdrawalRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ListView(
            padding: EdgeInsets.all(16),
            children: [
              VenueWithdrawalsPanel(venueId: 'casa', email: 'casa@example.com'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  const candidates = [
    '/tmp/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? dir;
  for (final candidate in candidates) {
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
      dir = candidate;
      break;
    }
  }
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

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name, {
  required bool panel,
  bool includeDialog = false,
}) async {
  expect(find.text(PartnerMessages.withdrawalsTitle), findsOneWidget);
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>());
  var rect = Offset.zero & view.size;
  if (panel) {
    final box = tester.renderObject<RenderBox>(
      find.byKey(PartnerKeys.withdrawals),
    );
    rect = (box.localToGlobal(Offset.zero) & box.size).inflate(16);
    if (includeDialog) {
      final title = tester.getRect(find.text(PartnerMessages.withdrawalReauth));
      final button = tester.getRect(find.byKey(PartnerKeys.withdrawalConfirm));
      rect = rect.expandToInclude(title.expandToInclude(button).inflate(72));
    }
    rect = rect.intersect(Offset.zero & view.size);
  }
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(rect, pixelRatio: 2),
  );
  if (image == null) {
    throw StateError(name);
  }
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
