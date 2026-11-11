import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/reviews/presentation/room_review_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('um toque por linha, comentário opcional e meia estrela', (
    tester,
  ) async {
    _size(tester, const Size(390, 1700));
    ReviewScores? sent;
    String? comment;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: RoomReviewForm(
            roomName: 'O Cofre',
            houseName: 'Ninja Escape',
            onSubmit: (scores, text) async {
              sent = scores;
              comment = text;
              return null;
            },
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(AppKeys.roomReviewSubmit),
    );
    expect(button.onPressed, isNull);
    expect(find.byIcon(Icons.star_half), findsNothing);

    await tester.tap(find.byKey(AppKeys.reviewScore('story', 5)));
    await tester.tap(find.byKey(AppKeys.reviewScore('puzzles', 5)));
    await tester.tap(find.byKey(AppKeys.reviewScore('immersion', 5)));
    await tester.tap(find.byKey(AppKeys.reviewScore('service', 4)));
    await tester.tap(find.byKey(AppKeys.reviewScore('comfort', 4)));
    await tester.tap(find.byKey(AppKeys.reviewScore('value', 4)));
    await tester.pump();

    expect(find.text('Incrível'), findsWidgets);
    expect(find.text('Bom'), findsWidgets);
    expect(find.text('4,5'), findsOneWidget);
    expect(find.byIcon(Icons.star_half), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(AppKeys.roomReviewSubmit))
          .onPressed,
      isNotNull,
    );

    await _shot(tester, 'jogador-avaliar-390');

    await tester.tap(find.byKey(AppKeys.roomReviewSubmit));
    await tester.pump();
    expect(sent?.story, 5);
    expect(sent?.value, 4);
    expect(reviewOverall(sent!), 4.5);
    expect(comment, '');
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

Future<void> _loadFonts() async {
  final dir = _fontDir();
  if (dir == null) return;
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

String? _fontDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = '${dir.path}/artifacts/material_fonts';
    if (File('$candidate/Roboto-Regular.ttf').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
