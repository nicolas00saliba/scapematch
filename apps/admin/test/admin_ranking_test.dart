import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_ranking.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
  });

  testWidgets('a flag nasce desligada e o admin remove uma linha', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MemoryRankingAdminApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rankingAdminProvider.overrideWithValue(api)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: adminTheme(),
          home: const Scaffold(body: RankingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final flag = tester.widget<Switch>(find.byType(Switch));
    expect(flag.value, isFalse);
    expect(find.textContaining('Desligada'), findsOneWidget);
    expect(find.text('Os Ninjas · Ninja Escape · O Cofre'), findsOneWidget);
    expect(find.textContaining('38:12 (Restavam 21:48)'), findsOneWidget);
    await _shot(tester, 'ranking-admin');

    await tester.tap(find.byKey(const Key('admin-ranking-flag')));
    await tester.tap(find.byKey(const Key('admin-ranking-salvar')));
    await tester.pumpAndSettle();
    expect((await api.settings()).enabled, isTrue);
    expect(find.textContaining('Ligada'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-ranking-remover-tempo-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('removido'), findsOneWidget);
    expect(find.byKey(const Key('admin-ranking-remover-tempo-1')), findsNothing);
  });
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
