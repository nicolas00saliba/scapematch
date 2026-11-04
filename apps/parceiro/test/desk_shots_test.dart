import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('saves the partner desk screenshots', (tester) async {
    if (Platform.environment['SCAPEMATCH_DESK_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/parceiro')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    await _capture(tester, dir, const Size(390, 844), '390');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _capture(tester, dir, const Size(1440, 900), '1440');
  });
}

Future<void> _capture(
  WidgetTester tester,
  Directory dir,
  Size size,
  String suffix,
) async {
  await pumpParceiro(tester, size: size);
  await tester.enterText(
    find.byKey(PartnerKeys.partnerEmail),
    partnerDemoAccount.email,
  );
  await tester.enterText(
    find.byKey(PartnerKeys.partnerPassword),
    partnerDemoPassword,
  );
  await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
  await tester.pumpAndSettle();

  await _openTab(tester, PartnerMessages.rooms);
  await tester.tap(find.byKey(PartnerKeys.agendaAddRoom));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'formulario-sala-$suffix.png',
    size,
    find.byKey(PartnerKeys.agendaRoomName),
  );
  await tester.enterText(find.byKey(PartnerKeys.agendaRoomName), 'Sala da Casa');
  await tester.tap(find.byKey(PartnerKeys.agendaSaveRoom));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  final created = find.text('Sala da Casa');
  await tester.scrollUntilVisible(created, 400, scrollable: verticalScrollable);
  await tester.ensureVisible(created);
  await tester.pumpAndSettle();
  await _shot(tester, dir, 'sala-criada-$suffix.png', size, created);

  await _openTab(tester, PartnerMessages.reservations);
  await tester.tap(find.text(PartnerMessages.upcoming));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'reservas-proximas-$suffix.png',
    size,
    find.text(PartnerMessages.upcoming),
  );
  await tester.tap(find.text(PartnerMessages.done));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'reservas-realizadas-$suffix.png',
    size,
    find.text(PartnerMessages.closedGroup),
  );
  await tester.tap(find.text(PartnerMessages.cancelledTab));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'reservas-canceladas-$suffix.png',
    size,
    find.text(PartnerMessages.cancelled),
  );

  await _openTab(tester, PartnerMessages.agenda);
  await _selectView(tester, size, PartnerKeys.agendaViewDay);
  await tester.tap(find.byKey(PartnerKeys.agendaMonthToggle));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'agenda-dia-$suffix.png',
    size,
    find.byKey(PartnerKeys.agendaMiniCalendar),
  );
  await tester.tap(find.byKey(PartnerKeys.agendaMonthToggle));
  await tester.pumpAndSettle();
  await _selectView(tester, size, PartnerKeys.agendaViewWeek);
  await _shot(
    tester,
    dir,
    'agenda-semana-$suffix.png',
    size,
    find.byKey(PartnerKeys.agendaCalendar),
  );
  await _selectView(tester, size, PartnerKeys.agendaViewMonth);
  await _shot(
    tester,
    dir,
    'agenda-mes-$suffix.png',
    size,
    find.byKey(PartnerKeys.agendaMonthGrid),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.text(label);
  await tester.ensureVisible(tab.first);
  await tester.pumpAndSettle();
  await tester.tap(tab.first);
  await tester.pumpAndSettle();
}

Future<void> _selectView(WidgetTester tester, Size size, Key view) async {
  if (size.width < 960) {
    await tester.tap(find.byKey(PartnerKeys.agendaViews));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(view));
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();
  const candidates = [
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? dir;
  for (final path in candidates) {
    if (File('$path/Roboto-Regular.ttf').existsSync()) {
      dir = path;
      break;
    }
  }
  if (dir == null) {
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
    () => (layer! as OffsetLayer).toImage(
      Offset.zero & view.size,
      pixelRatio: 1,
    ),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
