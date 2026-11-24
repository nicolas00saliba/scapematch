import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/features/payments/domain/card_installments.dart';
import 'package:scapematch/features/payments/presentation/installment_grid.dart';
import 'package:scapematch/features/payments/presentation/installment_summary.dart';

void main() {
  test('R\$ 100 libera até 3x e a cotação libera o restante', () {
    final open = cardInstallmentOptions(
      principalCents: 10000,
      interestCentsByCount: {
        for (var count = 4; count <= 12; count++) count: 160 * (count - 3),
      },
    );
    expect(open.every((item) => item.enabled), isTrue);
    expect(open[2].interestFree, isTrue);
    expect(open[3].showsTotal, isTrue);

    final quoted = cardInstallmentOptions(principalCents: 14999);
    expect(quoted.where((item) => item.enabled).map((item) => item.count), [
      1,
      2,
      3,
    ]);
    expect(quoted[3].disabledReason, 'Cotação indisponível');
  });

  test('parcela abaixo de R\$ 5 fica desabilitada', () {
    final options = cardInstallmentOptions(principalCents: 900);
    expect(options.where((item) => item.enabled).map((item) => item.count), [
      1,
    ]);
    expect(options[1].disabledReason, 'parcela mínima de R\$ 5');

    final exact = cardInstallmentOptions(principalCents: 1000);
    expect(exact[1].enabled, isTrue);
    expect(exact[2].enabled, isFalse);
  });

  testWidgets('a grade marca sem juros até 3x e o total a partir de 4x', (
    tester,
  ) async {
    var selected = 1;
    final options = cardInstallmentOptions(
      principalCents: 20000,
      interestCentsByCount: {4: 640, 12: 2400},
    );
    await tester.pumpWidget(
      _host(
        selected: selected,
        options: options,
        onSelect: (count) => selected = count,
      ),
    );

    expect(find.text('sem juros'), findsNWidgets(3));
    expect(find.text('com juros'), findsNWidgets(2));
    final free = tester.widget<Text>(find.text('sem juros').first);
    final paid = tester.widget<Text>(find.text('com juros').first);
    expect(free.style?.color, const Color(0xFFFFFFFF));
    expect(free.style?.fontWeight, FontWeight.w800);
    expect(free.style?.fontSize, greaterThan(paid.style?.fontSize ?? 0));
    expect(find.textContaining('206,40'), findsOneWidget);
    expect(find.textContaining('51,60'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('parcela-4')));
    await tester.pumpWidget(
      _host(
        selected: selected,
        options: options,
        onSelect: (count) => selected = count,
      ),
    );
    expect(selected, 4);

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('parcela-1')),
    );
    expect(semantics.flagsCollection.isButton, isTrue);

    final box = tester.getSize(find.byKey(const ValueKey('parcela-2')));
    expect(box.height, greaterThanOrEqualTo(48));
    expect(box.width, greaterThanOrEqualTo(48));
  });

  testWidgets('parcela abaixo de R\$ 5 não seleciona', (tester) async {
    await tester.pumpWidget(
      _host(
        selected: 1,
        options: cardInstallmentOptions(
          principalCents: 900,
          interestCentsByCount: {
            for (var count = 4; count <= 12; count++) count: 160 * (count - 3),
          },
        ),
        onSelect: (_) {},
      ),
    );
    expect(find.text('parcela mínima de R\$ 5'), findsNWidgets(11));
    await tester.tap(find.byKey(const ValueKey('parcela-4')));
    await tester.pump();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('salva o resumo e a grade a 390px', (tester) async {
    if (Platform.environment['SCAPEMATCH_INSTALLMENT_SHOT'] != '1') return;
    await tester.runAsync(_loadFonts);
    final options = cardInstallmentOptions(
      principalCents: 10000,
      interestCentsByCount: {
        for (var count = 4; count <= 12; count++) count: 160 * (count - 3),
      },
    );
    expect(options.every((item) => item.enabled), isTrue);
    expect(options[2].interestFree, isTrue);
    expect(options[3].showsTotal, isTrue);
    final photo = File('test/fixtures/sala-acerto-de-contas.jpeg')
        .readAsBytesSync();
    await _shot(
      tester,
      const Size(390, 280),
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: ReservationPaySummary(
              coverAsset: '',
              coverBytes: photo,
              houseName: 'Puzzle Room Escape Game',
              roomName: 'Acerto de Contas',
              totalLabel: formatPrice(10000),
              installmentLabel: '3x sem juros',
              onOpenInstallments: () {},
            ),
          ),
        ),
      ),
      '/opt/cursor/artifacts/resumo-parcelas-390.png',
      photo: MemoryImage(photo),
    );
    await _shot(
      tester,
      const Size(390, 1000),
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: InstallmentPickerPage(options: options, selected: 3),
      ),
      '/opt/cursor/artifacts/parcelas-390.png',
    );
  });
}

Future<void> _shot(
  WidgetTester tester,
  Size size,
  Widget app,
  String path, {
  ImageProvider? photo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  final context = tester.element(find.byType(Scaffold).first);
  final provider = photo;
  if (provider != null) {
    await tester.runAsync(() async {
      await precacheImage(provider, context);
    });
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  Directory('/opt/cursor/artifacts').createSync(recursive: true);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  expect(image!.width, 390);
  image.dispose();
}

Widget _host({
  required int selected,
  required List<CardInstallmentOption> options,
  required ValueChanged<int> onSelect,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: InstallmentGrid(
          options: options,
          selected: selected,
          onSelect: onSelect,
        ),
      ),
    ),
  );
}

Future<void> _loadFonts() async {
  const dir = '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';
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
