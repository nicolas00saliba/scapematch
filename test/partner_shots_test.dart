import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/partner/domain/partner_account.dart';
import 'package:scapematch/features/partner/presentation/partner_messages.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the partner desk', (tester) async {
    if (Platform.environment['SCAPEMATCH_PARTNER_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/parceiro')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    const shots = [
      (size: Size(412, 915), theme: 'light', suffix: '412-claro'),
      (size: Size(1280, 900), theme: 'dark', suffix: '1280-escuro'),
    ];
    for (final shot in shots) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _flow(tester, dir, shot.size, shot.theme, shot.suffix);
    }

    const balanceOnly = [
      (size: Size(412, 915), theme: 'dark', suffix: '412-escuro'),
      (size: Size(1280, 900), theme: 'light', suffix: '1280-claro'),
    ];
    for (final shot in balanceOnly) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _balance(tester, dir, shot.size, shot.theme, shot.suffix);
    }
  });
}

Future<void> _flow(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
) async {
  await _open(tester, size, theme);
  await _shot(tester, dir, 'login-$suffix.png', size, find.byType(TextField));
  await _enter(tester);
  await _shot(
    tester,
    dir,
    'saldo-$suffix.png',
    size,
    find.byKey(AppKeys.partnerNet),
  );
  await tester.tap(find.text(PartnerMessages.reservations));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'reservas-$suffix.png',
    size,
    find.text('Reservado'),
  );
  await tester.tap(find.text(PartnerMessages.rooms));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'salas-$suffix.png',
    size,
    find.text(PartnerMessages.savePrice),
  );
}

Future<void> _balance(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
) async {
  await _open(tester, size, theme);
  await _enter(tester);
  await _shot(
    tester,
    dir,
    'saldo-$suffix.png',
    size,
    find.byKey(AppKeys.partnerNet),
  );
}

Future<void> _open(WidgetTester tester, Size size, String theme) async {
  await pumpScapeMatch(
    tester,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(
        ThemeChoiceStore(saved: theme),
      ),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/parceiro');
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(AppKeys.partnerEmail),
    partnerDemoAccount.email,
  );
  await tester.enterText(
    find.byKey(AppKeys.partnerPassword),
    partnerDemoPassword,
  );
  await tester.tap(find.byKey(AppKeys.partnerSubmit));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  const dir = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
  if (!File('$dir/Roboto-Regular.ttf').existsSync()) {
    return;
  }
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
  String name,
  Size expected,
  Finder anchor,
) async {
  expect(anchor, findsWidgets, reason: name);
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
