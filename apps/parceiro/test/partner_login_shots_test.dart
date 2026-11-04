import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('saves the partner login with the short demo hint', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_PARTNER_LOGIN_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/parceiro-login')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(1280, 900);
    await pumpParceiro(tester, size: size);
    expect(find.text(PartnerMessages.quickDemo), findsOneWidget);
    await _shot(tester, dir, 'parceiro-login-demo.png', size);
  });
}

Future<void> _loadFonts() async {
  final poppins = File('/workspace/assets/fonts/Poppins-Medium.ttf')
      .readAsBytesSync();
  final loader = FontLoader('Poppins')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(poppins).buffer)));
  await loader.load();
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
) async {
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
  expect(image.height, expected.height.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
