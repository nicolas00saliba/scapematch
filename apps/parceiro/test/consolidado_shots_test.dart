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
  testWidgets('print da aba Notas fiscais com fonte real', (tester) async {
    if (Platform.environment['SCAPEMATCH_CONSOLIDADO_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/consolidado')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpParceiro(tester, size: const Size(1440, 900));
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
    final tab = find.text(PartnerMessages.invoices);
    await tester.ensureVisible(tab.first);
    await tester.pumpAndSettle();
    await tester.tap(tab.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nota de teste'), findsWidgets);
    expect(find.text(PartnerMessages.invoices), findsWidgets);
    await _shot(tester, dir, 'parceiro-notas-1440.png');
  });
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  final sdkFonts = Directory(
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/artifacts/material_fonts',
  );
  final dirs = [
    sdkFonts.path,
    '/home/ubuntu/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
    '/opt/flutter/bin/cache/artifacts/material_fonts',
  ];
  final dir = dirs.cast<String?>().firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
    orElse: () => null,
  );
  if (dir == null) {
    throw StateError(
      'Roboto não encontrado. Sem a fonte real o print sai em Ahem.',
    );
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

Future<void> _shot(WidgetTester tester, Directory dir, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image, isNotNull, reason: name);
  await tester.runAsync(() => _expectReadable(image!, name));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}

Future<void> _expectReadable(ui.Image image, String name) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: name);
  final data = raw!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  var dark = 0;
  var edge = 0;
  bool isDark(int x, int y) {
    final i = (y * width + x) * 4;
    return data[i] < 55 && data[i + 1] < 80 && data[i + 2] < 80;
  }

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      if (!isDark(x, y)) {
        continue;
      }
      dark++;
      final boxed =
          isDark(x - 1, y) &&
          isDark(x + 1, y) &&
          isDark(x, y - 1) &&
          isDark(x, y + 1);
      if (!boxed) {
        edge++;
      }
    }
  }
  expect(dark, greaterThan(400), reason: '$name não tem texto');
  expect(
    edge / dark,
    greaterThan(0.35),
    reason: '$name ainda está com a fonte Ahem',
  );
}
