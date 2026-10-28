import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves account screens at 390 and 1280', (tester) async {
    final dir = _shotDir();
    await tester.runAsync(_loadFonts);

    await _open(tester, const Size(390, 844));
    await _capture(tester, find.byType(AccountScreen), dir, 'conta-390');
    await tester.scrollUntilVisible(
      find.text('Cartões cadastrados'),
      200,
      scrollable: find.descendant(
        of: find.byType(AccountScreen),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      ),
    );
    await _capture(tester, find.byType(AccountScreen), dir, 'conta-390-lista');

    await tester.tap(find.byKey(AppKeys.accountDestination('cards')));
    await tester.pumpAndSettle();
    await _capture(tester, find.text('Nenhum cartão cadastrado'), dir, 'cartoes-390');
    await tester.tap(find.byKey(AppKeys.addCard));
    await tester.pumpAndSettle();
    await _capture(tester, find.byKey(AppKeys.addCardNotice), dir, 'cartoes-390-aviso');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountAddBalance));
    await tester.pumpAndSettle();
    await _capture(tester, find.text('Forma de pagamento'), dir, 'saldo-390');

    while (find.byType(BackButton).evaluate().isNotEmpty) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await _capture(tester, find.byType(AccountScreen), dir, 'conta-1280');
    await tester.tap(find.byKey(AppKeys.accountAddBalance));
    await tester.pumpAndSettle();
    await _capture(tester, find.text('Forma de pagamento'), dir, 'saldo-1280');
  });
}

Future<void> _open(WidgetTester tester, Size size) async {
  await pumpScapeMatch(tester);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
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
    ..addFont(bytes('Roboto-Bold.ttf'))
    ..addFont(bytes('Roboto-Black.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Directory _shotDir() {
  final preferred = Directory('/opt/cursor/artifacts/account-wallet');
  try {
    preferred.createSync(recursive: true);
    return preferred;
  } catch (_) {
    return Directory.systemTemp.createTempSync('account-wallet');
  }
}

Future<void> _capture(
  WidgetTester tester,
  Finder anchor,
  Directory dir,
  String name,
) async {
  await tester.ensureVisible(anchor);
  await tester.pumpAndSettle();
  final boundary = _boundaryOf(tester.element(anchor));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) {
    return;
  }
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) {
    return;
  }
  File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}

RenderRepaintBoundary _boundaryOf(Element element) {
  RenderRepaintBoundary? found;
  element.visitAncestorElements((ancestor) {
    final render = ancestor.renderObject;
    if (render is RenderRepaintBoundary && render.size.height > 200) {
      found = render;
      return false;
    }
    return true;
  });
  expect(found, isNotNull);
  return found!;
}
