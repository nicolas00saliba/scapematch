import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/providers/repositories.dart';

void main() {
  testWidgets('saves player login and signup at 1440 and 390', (tester) async {
    if (Platform.environment['SCAPEMATCH_LOGIN_REAL_SHOTS'] != '1') return;
    final dir = Directory('/opt/cursor/artifacts/login-real')
      ..createSync(recursive: true);
    addTearDown(() => scapeUsesLiveBackend = false);
    scapeUsesLiveBackend = true;
    await tester.runAsync(_loadFonts);
    final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));
    for (final size in const [Size(1440, 1200), Size(390, 1400)]) {
      await _pump(tester, size, database, const LoginScreen());
      await _capture(
        tester,
        find.byKey(AppKeys.loginSubmit),
        dir,
        'jogador-login-${size.width.round()}',
      );
      await _pump(tester, size, database, const SignupScreen());
      await _capture(
        tester,
        find.text('Criar conta'),
        dir,
        'jogador-cadastro-${size.width.round()}',
      );
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  FakeDatabase database,
  Widget home,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 4, 15))),
        cityRepositoryProvider.overrideWithValue(
          FakeCityRepository(database, latency: Duration.zero),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  final alt = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
  final root = Directory(dir).existsSync() ? dir : alt;
  if (!File('$root/Roboto-Regular.ttf').existsSync()) return;
  Future<ByteData> bytes(String name) async {
    final data = File('$root/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Future<void> _capture(
  WidgetTester tester,
  Finder anchor,
  Directory dir,
  String name,
) async {
  await tester.pumpAndSettle();
  final boundary = _boundaryOf(tester.element(anchor));
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) return;
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  if (bytes == null) return;
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
