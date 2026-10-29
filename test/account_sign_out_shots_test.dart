import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves sign-out screens at 390', (tester) async {
    final dir = _shotDir();
    await tester.runAsync(_loadFonts);
    await pumpScapeMatch(tester);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(AccountScreen),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(AppKeys.accountSignOut),
      200,
      scrollable: scrollable,
    );
    await _capture(tester, find.byKey(AppKeys.accountSignOut), dir, 'sair-390');
    await tester.tap(find.byKey(AppKeys.accountSignOut));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      find.text(AccountMessages.signOutTitle),
      dir,
      'sair-dialogo-390',
    );
    await tester.tap(find.byKey(AppKeys.dialogConfirm));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      find.text(AccountMessages.signedOutTitle),
      dir,
      'saiu-390',
    );
    await tester.tap(find.byKey(AppKeys.accountSignIn));
    await tester.pumpAndSettle();
    await _capture(tester, find.text('Fazer cadastro'), dir, 'entrar-390');
  });
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
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Directory _shotDir() {
  final preferred = Directory('/opt/cursor/artifacts/account-sign-out');
  try {
    preferred.createSync(recursive: true);
    return preferred;
  } catch (_) {
    return Directory.systemTemp.createTempSync('account-sign-out');
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
  RenderRepaintBoundary? found;
  tester.element(anchor).visitAncestorElements((ancestor) {
    final render = ancestor.renderObject;
    if (render is RenderRepaintBoundary && render.size.height > 200) {
      found = render;
      return false;
    }
    return true;
  });
  final boundary = found;
  if (boundary == null) {
    return;
  }
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
