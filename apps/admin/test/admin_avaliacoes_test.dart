import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_reviews.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
    final icons = _fontDir();
    if (icons == null) return;
    final iconBytes = File(
      '$icons/MaterialIcons-Regular.otf',
    ).readAsBytesSync();
    final iconData = ByteData.sublistView(Uint8List.fromList(iconBytes));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(iconData));
    await iconLoader.load();
  });

  testWidgets('a flag nasce desligada e ocultar exige motivo', (tester) async {
    _size(tester, const Size(1280, 1700));
    final api = MemoryReviewAdminApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reviewAdminProvider.overrideWithValue(api)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: adminTheme(),
          home: const Scaffold(body: AvaliacoesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final flag = tester.widget<Switch>(find.byType(Switch));
    expect(flag.value, isFalse);
    expect(find.textContaining('Desligada'), findsOneWidget);
    expect(find.text('Ana · Ninja Escape · O Cofre'), findsOneWidget);
    expect(find.textContaining('story'), findsNothing);

    await _shot(tester, 'admin-avaliacoes-1280');

    await tester.enterText(find.byKey(const Key('admin-avaliacoes-m')), '12');
    await tester.enterText(
      find.byKey(const Key('admin-avaliacoes-minimo')),
      '15',
    );
    await tester.tap(find.byKey(const Key('admin-avaliacoes-salvar')));
    await tester.pumpAndSettle();
    expect(api.settings(), completion(isA<ReviewSettings>()));
    final saved = await api.settings();
    expect(saved.enabled, isFalse);
    expect(saved.priorWeight, 12);
    expect(saved.rankingMinimum, 15);
    expect(find.textContaining('save · settings · desligou'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-ocultar-avaliacao-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('O motivo fica entre 1 e 280 caracteres.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('admin-motivo-avaliacao-1')),
      'Ofensa à equipe',
    );
    await tester.tap(find.byKey(const Key('admin-ocultar-avaliacao-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('oculto: Ofensa à equipe'), findsOneWidget);
    expect(
      find.textContaining('hide · avaliacao-1 · Ofensa à equipe'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
