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
  testWidgets('saves the partner agenda', (tester) async {
    if (Platform.environment['SCAPEMATCH_AGENDA_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/agenda')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(const SizedBox.shrink());
    await _desk(tester, const Size(1280, 900), 'light');
    await _shot(tester, dir, 'semana-1280-claro.png', const Size(1280, 900), find.byKey(AppKeys.agendaCalendar));

    await tester.pumpWidget(const SizedBox.shrink());
    await _desk(tester, const Size(1280, 900), 'dark');
    await _shot(tester, dir, 'semana-1280-escuro.png', const Size(1280, 900), find.byKey(AppKeys.agendaCalendar));
    await _lists(tester, dir, '1280-escuro', const Size(1280, 900));
    await _forms(tester, dir, '1280-escuro', const Size(1280, 900));

    await tester.pumpWidget(const SizedBox.shrink());
    await _desk(tester, const Size(412, 915), 'light');
    await _shot(tester, dir, 'dia-412-claro.png', const Size(412, 915), find.text(PartnerMessages.agenda));
    await _sheet(tester, dir, '412-claro', const Size(412, 915));
    await _lists(tester, dir, '412-claro', const Size(412, 915));
    await _forms(tester, dir, '412-claro', const Size(412, 915));
  });
}

Future<void> _desk(WidgetTester tester, Size size, String theme) async {
  await pumpScapeMatch(
    tester,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(ThemeChoiceStore(saved: theme)),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/parceiro');
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AppKeys.partnerEmail), partnerDemoAccount.email);
  await tester.enterText(find.byKey(AppKeys.partnerPassword), partnerDemoPassword);
  await tester.tap(find.byKey(AppKeys.partnerSubmit));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.text(PartnerMessages.agenda).first);
  await tester.pumpAndSettle();
}

Future<void> _sheet(
  WidgetTester tester,
  Directory dir,
  String suffix,
  Size size,
) async {
  await tester.tap(find.text(PartnerMessages.agendaList));
  await tester.pumpAndSettle();
  await tester.tap(find.text(PartnerMessages.done));
  await tester.pumpAndSettle();
  final block = find.text(PartnerMessages.closedGroup);
  await tester.ensureVisible(block.first);
  await tester.tap(block.first);
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'detalhe-$suffix.png', size, find.byKey(AppKeys.agendaSheet));
  Navigator.of(tester.element(find.byKey(AppKeys.agendaSheet))).pop();
  await tester.pumpAndSettle();
}

Future<void> _forms(
  WidgetTester tester,
  Directory dir,
  String suffix,
  Size size,
) async {
  await tester.tap(find.byKey(AppKeys.agendaAdd));
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'nova-sessao-$suffix.png', size, find.text(PartnerMessages.addSession));
  Navigator.of(tester.element(find.text(PartnerMessages.openSession))).pop();
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(AppKeys.agendaRooms));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.agendaAddRoom));
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'nova-sala-$suffix.png', size, find.byKey(AppKeys.agendaRoomName));
  Navigator.of(tester.element(find.byKey(AppKeys.agendaRoomName))).pop();
  await tester.pumpAndSettle();
}

Future<void> _lists(
  WidgetTester tester,
  Directory dir,
  String suffix,
  Size size,
) async {
  await tester.tap(find.text(PartnerMessages.agendaList));
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'lista-proximas-$suffix.png', size, find.text(PartnerMessages.upcoming));
  await tester.tap(find.text(PartnerMessages.done));
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'lista-realizadas-$suffix.png', size, find.text(PartnerMessages.done));
  await tester.tap(find.text(PartnerMessages.cancelledTab));
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'lista-canceladas-$suffix.png', size, find.text(PartnerMessages.cancelledTab));
  await tester.tap(find.text(PartnerMessages.agenda).last);
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
  final icons = FontLoader('MaterialIcons')..addFont(bytes('MaterialIcons-Regular.otf'));
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
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
