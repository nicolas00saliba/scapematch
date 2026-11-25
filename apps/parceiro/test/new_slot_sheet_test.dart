import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/presentation/new_slot_sheet.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets(
    'abre horário com data e hora exatas, inclusive em menos de 1 h',
    (tester) async {
      await tester.runAsync(_loadFonts);
      final now = DateTime(2026, 11, 24, 15);
      DateTime? saved;
      await tester.binding.setSurfaceSize(const Size(412, 915));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: const Locale('pt', 'BR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('pt', 'BR')],
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    saved = await showNewSlotSheet(context, now: now);
                  },
                  child: const Text('Novo horário'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Novo horário'));
      await tester.pumpAndSettle();
      expect(find.byKey(PartnerKeys.newSlotDate), findsOneWidget);
      expect(find.byKey(PartnerKeys.newSlotTime), findsOneWidget);
      expect(find.text('19:00'), findsOneWidget);
      expect(find.textContaining('Curitiba'), findsOneWidget);
      await _shotRoot(tester, 'parceiro-novo-horario-celular');

      await tester.tap(find.byKey(PartnerKeys.newSlotSave));
      await tester.pumpAndSettle();
      expect(saved, DateTime(2026, 11, 25, 19));
    },
  );

  testWidgets('horário passado não abre', (tester) async {
    final now = DateTime(2026, 11, 24, 15);
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () async {
                  final result = await showDialog<DateTime>(
                    context: context,
                    builder: (context) => NewSlotSheet(
                      now: now,
                      initial: DateTime(2026, 11, 24, 14),
                    ),
                  );
                  saved = result != null;
                },
                child: const Text('abrir'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.newSlotSave));
    await tester.pumpAndSettle();
    expect(find.text('Esse horário já passou.'), findsOneWidget);
    expect(saved, isFalse);
  });
}

Future<void> _shotRoot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  await tester.pump();
  final image = await tester.runAsync(() async {
    var node = tester.renderObject(find.byType(MaterialApp).first);
    while (node.parent != null) {
      node = node.parent!;
    }
    final layer = node.debugLayer;
    if (layer is! OffsetLayer) return null;
    return layer.toImage(node.paintBounds, pixelRatio: 1);
  });
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}

Future<void> _loadFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  String? fonts;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) {
      fonts = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (fonts == null) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$fonts/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
}
