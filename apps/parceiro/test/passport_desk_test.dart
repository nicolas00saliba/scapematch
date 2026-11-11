import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/presentation/passport_desk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('a casa liga o mimo, grava outro e marca o código entregue', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Poppins'),
        home: const Scaffold(
          body: PassportDesk(
            venueId: 'casa-ninja',
            rooms: [
              PassportRoomChoice(id: 'sala-cofre', name: 'O Cofre'),
              PassportRoomChoice(id: 'sala-templo', name: 'Templo'),
            ],
            preview: PassportDeskData.sample,
          ),
        ),
      ),
    );
    expect(find.text('Foto da sala'), findsWidgets);
    expect(find.text('Chaveiro da casa'), findsOneWidget);
    expect(find.textContaining('FOTO7A2C'), findsOneWidget);
    expect(find.byKey(const Key('passport-desk-sample')), findsOneWidget);

    await tester.tap(find.byKey(const Key('passport-gift-active-mimo-foto')));
    await tester.pump();
    expect(find.textContaining('desligado'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('passport-gift-title')),
      'Desconto da casa',
    );
    await tester.enterText(
      find.byKey(const Key('passport-gift-details')),
      '10% na próxima, por conta da casa.',
    );
    await tester.ensureVisible(find.byKey(const Key('passport-gift-save')));
    await tester.tap(find.byKey(const Key('passport-gift-save')));
    await tester.pump();
    expect(find.text('Desconto da casa'), findsOneWidget);
    expect(find.text('Mimo anotado neste exemplo.'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('passport-deliver-FOTO7A2C')),
    );
    await tester.tap(find.byKey(const Key('passport-deliver-FOTO7A2C')));
    await tester.pump();
    expect(find.textContaining('Entregue'), findsWidgets);
    expect(find.byKey(const Key('passport-deliver-FOTO7A2C')), findsNothing);
    await _shot(tester, 'passaporte-parceiro');
  });

  testWidgets('código curto não marca entrega', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PassportDesk(
            venueId: 'casa-ninja',
            rooms: [PassportRoomChoice(id: 'sala-cofre', name: 'O Cofre')],
            preview: PassportDeskData.sample,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('passport-claim-code')));
    await tester.enterText(find.byKey(const Key('passport-claim-code')), 'ABC');
    await tester.tap(find.byKey(const Key('passport-claim-deliver')));
    await tester.pump();
    expect(find.text('O código tem 8 caracteres.'), findsOneWidget);
    expect(find.textContaining('Aguardando'), findsOneWidget);
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
