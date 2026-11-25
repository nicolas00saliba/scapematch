import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_money.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes = File('assets/fonts/Poppins-Medium.ttf').readAsBytesSync();
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader('Poppins')..addFont(Future<ByteData>.value(data));
    await loader.load();
    final icons = _fontDir();
    if (icons == null) return;
    final iconBytes = File('$icons/MaterialIcons-Regular.otf').readAsBytesSync();
    final iconData = ByteData.sublistView(Uint8List.fromList(iconBytes));
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(iconData));
    await iconLoader.load();
  });

  testWidgets('pagamentos mostra a custódia e só libera com LIBERAR', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final money = MemoryAdminMoneyApi(
      charges: [
        {
          'id': 'cobranca-ana',
          'venue_name': 'Casa Dinheiro',
          'player_name': 'Ana',
          'status': 'paid',
          'amount_cents': 10000,
          'custody': 'falha',
          'custody_release_attempts': 8,
        },
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          adminApiProvider.overrideWithValue(MemoryAdminApi()),
          adminMoneyProvider.overrideWithValue(money),
          adminSessionProvider.overrideWith(_Ready.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Pagamentos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.byKey(const Key('admin-cac-flag')), findsOneWidget);
    expect(find.textContaining('não lê segredo'), findsOneWidget);
    expect(find.textContaining('Casa Dinheiro · Ana'), findsOneWidget);
    await tester.tap(find.textContaining('Casa Dinheiro · Ana'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('juros'), findsOneWidget);
    expect(find.textContaining('1ª sessão'), findsOneWidget);
    expect(find.textContaining('pontos 100'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('admin-cobranca')));
    await tester.pump();
    await _shot(tester, 'admin-pagamentos-cobranca');

    await tester.tap(find.byKey(const Key('admin-liberar-custodia')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byKey(const Key('admin-confirm-word')), 'nao');
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pump();
    expect(money.custodyReset, isFalse);
    expect(money.settled, isEmpty);

    await tester.enterText(find.byKey(const Key('admin-confirm-word')), 'LIBERAR');
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(money.custodyReset, isTrue);
    expect(money.settled, ['grupo-caixa']);
    expect(find.textContaining('Tentativa zerada'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('admin-dinheiro-aviso')));
    await tester.pump();
    await _shot(tester, 'admin-pagamentos-liberada');
  });
}

class _Ready extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
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

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  ) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('/opt/cursor/artifacts/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
