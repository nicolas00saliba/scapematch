import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/scape_liability_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('assets/fonts/Poppins-Medium.ttf');
    final data = ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('o aviso manda o passivo e as revisões para o console', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = buildAppTheme(Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Poppins'),
          primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Poppins'),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: 'Poppins',
            ),
          ),
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text(PartnerMessages.adminTitle)),
          body: const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: AdminConsoleNotice(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.scapeLiability), findsOneWidget);
    expect(find.text('Passivo e indicações'), findsOneWidget);
    expect(
      find.textContaining('console do EscapeMatch'),
      findsOneWidget,
    );
    expect(find.text('Abrir admin.escapematch.com.br'), findsOneWidget);
    expect(find.text('Em revisão'), findsNothing);
    expect(find.text('Aprovar'), findsNothing);
    expect(find.textContaining('ScapeMatch'), findsNothing);
    await tester.tap(find.byKey(PartnerKeys.adminConsole));
    await tester.pump();
    expect(find.text('Abrir admin.escapematch.com.br'), findsOneWidget);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2),
    );
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );
    final dir = Directory('/opt/cursor/artifacts');
    dir.createSync(recursive: true);
    File('${dir.path}/parceiro-aviso-console.png').writeAsBytesSync(
      bytes!.buffer.asUint8List(),
    );
  });
}
