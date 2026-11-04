import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('prints do cadastro e da home com fonte real', (tester) async {
    if (Platform.environment['SCAPEMATCH_CONSOLIDADO_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/consolidado')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/cadastro');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.signupSubmit),
      300,
      scrollable: verticalScrollable,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Li e aceito os termos, a privacidade e o reembolso (versão $legalDocumentVersion).',
      ),
      findsOneWidget,
    );
    await _shot(tester, dir, 'jogador-cadastro-390.png');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    await _waitForPhotos(tester);
    expect(find.text('Promoções'), findsOneWidget);
    await _shot(tester, dir, 'jogador-home-1440.png');
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

Future<void> _waitForPhotos(WidgetTester tester) async {
  if (find.byType(Scaffold).evaluate().isEmpty) {
    return;
  }
  final context = tester.element(find.byType(Scaffold).first);
  final providers = <ImageProvider>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      AssetImage(photo.asset),
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      image.image,
  ];
  if (providers.isEmpty) {
    return;
  }
  await tester.runAsync(() async {
    for (final provider in providers) {
      await precacheImage(provider, context);
    }
  });
  await tester.pump();
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
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  await tester.runAsync(() => _expectReadable(image!, name));
  image!.dispose();
}

Future<void> _expectReadable(ui.Image image, String name) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: name);
  final data = raw!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  var dark = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = (y * width + x) * 4;
      if (data[i] < 55 && data[i + 1] < 80 && data[i + 2] < 80) {
        dark++;
      }
    }
  }
  expect(dark, greaterThan(400), reason: '$name não tem texto');
  // O botão preenchido é um bloco sólido e derruba a razão da página
  // inteira. A faixa de cima é o formulário: texto de verdade tem traço.
  if (name.startsWith('jogador-cadastro')) {
    final band = _edgeRatio(data, width, height, 40, (height * 0.72).round());
    expect(
      band,
      greaterThan(0.42),
      reason: '$name ainda está com a fonte Ahem',
    );
  }
}

double _edgeRatio(Uint8List data, int width, int height, int y0, int y1) {
  var dark = 0;
  var edge = 0;
  bool isDark(int x, int y) {
    final i = (y * width + x) * 4;
    return data[i] < 55 && data[i + 1] < 80 && data[i + 2] < 80;
  }

  final bottom = y1.clamp(2, height - 1);
  for (var y = y0.clamp(1, bottom - 1); y < bottom; y++) {
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
  return dark == 0 ? 0 : edge / dark;
}
