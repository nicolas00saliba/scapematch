import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/scape_points/domain/passport_book.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch/features/scape_points/presentation/passport_card.dart';
import 'package:scapematch/features/scape_points/presentation/scape_points_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  test('o extrato chama o marco do passaporte pelo nome', () {
    final entry = ScapePointEntry.fromJson({
      'kind': 'accrual',
      'program': 'passport',
      'points': 500,
      'amount_cents': 500,
    });
    expect(entry.title, 'Passaporte de salas');
    expect(entry.detail, contains('Não paga a vaga inteira'));
    final back = ScapePointEntry.fromJson({
      'kind': 'reversal',
      'program': 'passport',
      'points': 500,
      'amount_cents': 500,
    });
    expect(back.title, 'Estorno do passaporte');
  });

  test('passaporte desligado não inventa carimbo', () {
    final book = PassportBook.fromJson({'enabled': false});
    expect(book.enabled, isFalse);
    expect(book.stamps, isEmpty);
    expect(book.gifts, isEmpty);
  });

  testWidgets('a aba mostra carimbos diferentes, visitas e o código', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 980);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Poppins'),
        home: const Scaffold(
          body: PassportCard(book: PassportBook.sample),
        ),
      ),
    );
    expect(find.byKey(const Key('passport-stamp-sala-cofre')), findsOneWidget);
    expect(find.byKey(const Key('passport-stamp-sala-templo')), findsOneWidget);
    expect(find.text('2 visitas'), findsOneWidget);
    expect(find.text('1 visita'), findsOneWidget);
    expect(find.text('Código FOTO7A2C'), findsOneWidget);
    expect(find.text('5 salas · 500 pontos · em aberto'), findsOneWidget);
    expect(
      find.textContaining('Não pagam a vaga inteira'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('passport-sample')), findsOneWidget);
    await _shot(tester, 'passaporte-jogador');
  });

  testWidgets('o preview sem passaporte continua só com o extrato', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScapePointsBody(preview: ScapeWallet.sample),
        ),
      ),
    );
    expect(find.byKey(const Key('passport-card')), findsNothing);
    expect(find.textContaining('SCAPEDEMO'), findsOneWidget);
  });

  testWidgets('passaporte fechado avisa sem carimbo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PassportCard(book: PassportBook.closed)),
      ),
    );
    expect(find.byKey(const Key('passport-closed')), findsOneWidget);
    expect(find.byKey(const Key('passport-stamp-sala-cofre')), findsNothing);
  });
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary =
      tester.renderObject(find.byType(RepaintBoundary).first)
          as RenderRepaintBoundary;
  try {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('/opt/cursor/artifacts/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  } on Object {
    // O CI não tem a pasta de artefatos do agente.
  }
}
