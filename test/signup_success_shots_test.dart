import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/features/auth/domain/signup_result.dart';
import 'package:scapematch/features/auth/presentation/signup_success_view.dart';

void main() {
  testWidgets('saves the signup success screen at 390', (tester) async {
    if (Platform.environment['SCAPEMATCH_SIGNUP_SUCCESS_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts')..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    const size = Size(390, 844);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: AppScaffold(
          desktopMaxWidth: AppScaffold.formMax,
          appBar: AppBar(
            leading: const ScapeBackButton(),
            title: const Text('Conta criada'),
          ),
          body: SignupSuccessView(
            email: 'ana@exemplo.com',
            cooldown: signupResendCooldown,
            onLogin: () {},
            onResend: () async => null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(AppKeys.signupSuccess), findsOneWidget);
    expect(find.text('Você pode reenviar em 60s.'), findsOneWidget);

    final view = tester.binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    expect(layer, isA<OffsetLayer>());
    final image = await tester.runAsync(
      () => (layer! as OffsetLayer).toImage(
        Offset.zero & view.size,
        pixelRatio: 1,
      ),
    );
    expect(image!.width, 390);
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    File('${dir.path}/cadastro-sucesso-390.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}
