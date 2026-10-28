import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves invite screens at 390 and 1280', (tester) async {
    final dir = _shotDir();
    await tester.runAsync(_loadFonts);
    await pumpScapeMatch(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );

    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/convite/${SampleIds.groupSpCoberturaOpen}');
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.text('Participar'),
        dir,
        'convite-${size.width.toInt()}',
      );
      await tester.tap(find.byKey(AppKeys.participate));
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.text('Fazer cadastro'),
        dir,
        'login-${size.width.toInt()}',
      );
      await tester.tap(find.byKey(AppKeys.goToSignup));
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.text('Criar conta'),
        dir,
        'cadastro-${size.width.toInt()}',
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
      await tester.pumpAndSettle();
    }
  });

  testWidgets('saves the share sheet and the joined group', (tester) async {
    final dir = _shotDir();
    await tester.runAsync(_loadFonts);
    await pumpScapeMatch(tester);

    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .go('/convite/${SampleIds.groupSpCoberturaOpen}');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.participate));
      await tester.pumpAndSettle();
      final list = find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      );
      tester.state<ScrollableState>(list.first).position.jumpTo(0);
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.byKey(AppKeys.inviteGroup),
        dir,
        'grupo-${size.width.toInt()}',
      );
      await tester.tap(find.byKey(AppKeys.inviteGroup));
      await tester.pumpAndSettle();
      await _capture(
        tester,
        find.text('Copiar link'),
        dir,
        'convidar-${size.width.toInt()}',
      );
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/');
      await tester.pumpAndSettle();
    }
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
  final preferred = Directory('/opt/cursor/artifacts/group-invite');
  try {
    preferred.createSync(recursive: true);
    return preferred;
  } catch (_) {
    return Directory.systemTemp.createTempSync('group-invite');
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
