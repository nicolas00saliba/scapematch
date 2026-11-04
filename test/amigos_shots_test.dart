import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('salva amigos, turma, entrada e filtro em 390 e 1440', (
    tester,
  ) async {
    final dir = _shotDir();
    await tester.runAsync(_loadFonts);

    await _open(tester, const Size(390, 844));
    await _capture(
      tester,
      find.byKey(AppKeys.friendSection),
      dir,
      'amigos-lista-390',
    );
    await _createCrew(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.createCrewForm),
      dir,
      'amigos-criar-turma-390',
    );
    await _back(tester);
    await _filter(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.crewVacancyFilter),
      dir,
      'amigos-filtro-390',
    );
    await _openParty(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.partyJoinSheet),
      dir,
      'amigos-entrar-turma-390',
    );

    await _closeSheet(tester);
    await _size(tester, const Size(1440, 900));
    await tester.tap(find.byKey(AppKeys.accountTab));
    await tester.pumpAndSettle();
    await _openFriends(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.friendSection),
      dir,
      'amigos-lista-1440',
    );
    await _createCrew(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.createCrewForm),
      dir,
      'amigos-criar-turma-1440',
    );
    await _back(tester);
    await _filter(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.crewVacancyFilter),
      dir,
      'amigos-filtro-1440',
    );
    await _openParty(tester);
    await _capture(
      tester,
      find.byKey(AppKeys.partyJoinSheet),
      dir,
      'amigos-entrar-turma-1440',
    );
  });
}

Future<void> _open(WidgetTester tester, Size size) async {
  await pumpScapeMatch(tester);
  await _size(tester, size);
  await tester.tap(find.byKey(AppKeys.accountTab));
  await tester.pumpAndSettle();
  await _openFriends(tester);
}

Future<void> _openFriends(WidgetTester tester) async {
  final tile = find.byKey(AppKeys.accountFriends);
  final scrollable = find.descendant(
    of: find.byType(AccountScreen),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.vertical,
    ),
  );
  if (scrollable.evaluate().isNotEmpty) {
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();
}

Future<void> _createCrew(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.createCrew));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AppKeys.crewName), 'Dupla do centro');
  await tester.tap(find.byKey(AppKeys.crewPhoto('Foto 1')));
  final luna = find.byKey(AppKeys.crewFriend(sampleLuna));
  await tester.ensureVisible(luna);
  await tester.tap(luna);
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester) async {
  await _popToShell(tester);
  await tester.tap(find.byKey(AppKeys.homeTab));
  await tester.pumpAndSettle();
  final chip = find.byKey(AppKeys.crewVacancyFilter);
  await tester.ensureVisible(chip);
  final selected = tester.widget<FilterChip>(chip).selected;
  if (!selected) {
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }
}

Future<void> _openParty(WidgetTester tester) async {
  // No celular a Home só lista grupo quase cheio. O grupo aberto continua
  // na rota, e é nele que a folha de turma aparece.
  GoRouter.of(tester.element(find.byType(Scaffold).first))
      .go('/groups/grp-cwb-opera-open');
  await tester.pumpAndSettle();
  final button = find.byKey(AppKeys.joinWithCrew);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.scapeBack));
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  final sheet = find.byKey(AppKeys.partyJoinSheet);
  if (sheet.evaluate().isNotEmpty) {
    Navigator.of(tester.element(sheet)).pop();
    await tester.pumpAndSettle();
  }
  await _popToShell(tester);
}

Future<void> _popToShell(WidgetTester tester) async {
  for (var step = 0; step < 6; step++) {
    if (find.byKey(AppKeys.homeTab).hitTestable().evaluate().isNotEmpty) {
      return;
    }
    final back = find.byType(BackButton).hitTestable();
    if (back.evaluate().isEmpty) {
      return;
    }
    await tester.tap(back.first);
    await tester.pumpAndSettle();
  }
}

const sampleLuna = 'user-luna';

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  final sdkFonts = Directory(
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/artifacts/material_fonts',
  );
  final dirs = [
    sdkFonts.path,
    '/home/ubuntu/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
    '/opt/flutter/bin/cache/artifacts/material_fonts',
  ];
  final dir = dirs.cast<String?>().firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
    orElse: () => null,
  );
  if (dir == null) {
    throw StateError(
      'Roboto não encontrado. Sem a fonte real o print sai em Ahem.',
    );
  }
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'))
    ..addFont(bytes('Roboto-Black.ttf'))
    ..addFont(bytes('Roboto-Light.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Directory _shotDir() {
  final preferred = Directory('/opt/cursor/artifacts/amigos');
  preferred.createSync(recursive: true);
  return preferred;
}

Future<void> _capture(
  WidgetTester tester,
  Finder anchor,
  Directory dir,
  String name,
) async {
  expect(anchor, findsWidgets, reason: name);
  await tester.ensureVisible(anchor);
  await tester.pumpAndSettle();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image, isNotNull, reason: name);
  await tester.runAsync(() => _expectReadable(image!, name));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  expect(bytes, isNotNull, reason: name);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  image!.dispose();
}

/// Ahem pinta cada letra como um retângulo sólido. Texto de verdade tem
/// traço fino: a maior parte dos pixels escuros encosta no fundo.
Future<void> _expectReadable(ui.Image image, String name) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(raw, isNotNull, reason: name);
  final data = raw!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  var dark = 0;
  var edge = 0;
  bool isDark(int x, int y) {
    final i = (y * width + x) * 4;
    return data[i] < 55 && data[i + 1] < 80 && data[i + 2] < 80;
  }

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      if (!isDark(x, y)) {
        continue;
      }
      dark++;
      final boxed =
          isDark(x - 1, y) &&
          isDark(x + 1, y) &&
          isDark(x, y - 1) &&
          isDark(x, y + 1);
      if (!boxed) {
        edge++;
      }
    }
  }
  expect(dark, greaterThan(400), reason: '$name não tem texto');
  // Fotos e o fundo do modal são blocos escuros de verdade. O Ahem só
  // aparece quando a tela é quase só texto e mesmo assim o traço some.
  if (name.startsWith('amigos-lista')) {
    expect(
      edge / dark,
      greaterThan(0.42),
      reason: '$name ainda está com a fonte Ahem',
    );
  }
}
