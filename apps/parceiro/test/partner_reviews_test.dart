import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_reviews_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('mostra agregado, primeiro nome e força ou fraqueza', (
    tester,
  ) async {
    _size(tester, const Size(1100, 1900));
    const distribution = {1: 6, 2: 1, 3: 2, 4: 3, 5: 8};
    final board = VenueReviewBoard(
      houseName: 'Ninja Escape',
      overall: 4.2,
      count: 20,
      categories: const {
        ReviewCategory.story: 4.6,
        ReviewCategory.puzzles: 3.1,
        ReviewCategory.immersion: 4.0,
        ReviewCategory.service: 4.0,
        ReviewCategory.comfort: 4.2,
        ReviewCategory.value: 3.8,
      },
      cityCategories: const {
        ReviewCategory.story: 4.0,
        ReviewCategory.puzzles: 4.0,
        ReviewCategory.immersion: 4.0,
        ReviewCategory.service: 4.1,
        ReviewCategory.comfort: 3.5,
        ReviewCategory.value: 3.8,
      },
      rooms: const [
        (name: 'O Cofre', average: 4.5, count: 12),
        (name: 'O Labirinto', average: 3.6, count: 8),
      ],
      months: const [
        ReviewMonth(month: '2026-09', count: 8, average: 3.9),
        ReviewMonth(month: '2026-10', count: 12, average: 4.4),
      ],
      distribution: distribution,
      comments: const [
        PublicReviewComment(
          id: 'comentario-1',
          firstName: 'Ana',
          body: 'A história prende do começo ao fim.',
          overall: 4.5,
        ),
      ],
    );
    expect(
      distribution.values.fold<int>(0, (sum, count) => sum + count),
      board.count,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: PartnerReviewsPanel(
            board: board,
            onReply: (id, body) async => null,
          ),
        ),
      ),
    );

    for (final label in reviewCategoryLabels.values) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('comentario-1'), findsNothing);
    expect(
      find.byKey(const Key('review-standing-História')),
      findsOneWidget,
    );
    expect(find.text('acima da cidade'), findsWidgets);
    expect(find.text('abaixo da cidade'), findsWidgets);
    expect(find.text('na média da cidade'), findsWidgets);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(find.byKey(PartnerKeys.partnerReviews), findsOneWidget);
    expect(find.byKey(PartnerKeys.partnerReviewReply), findsOneWidget);

    await _shot(tester, 'parceiro-avaliacoes-1100');
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
