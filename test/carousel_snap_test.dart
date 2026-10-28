import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('carousels rest on whole cards at 390 and at 1280', (
    tester,
  ) async {
    final shots = _shotDir();
    await tester.runAsync(_loadFonts);
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      await pumpScapeMatch(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HomeScreen));
      await tester.runAsync(() async {
        for (final flyer in promoFlyers) {
          await precacheImage(AssetImage(flyer.asset), context);
        }
      });
      await tester.pumpAndSettle();

      for (final id in const ['promos', 'news', 'rooms']) {
        await _show(tester, id);
        tester.state<ScrollableState>(_horizontal(id)).position.jumpTo(0);
        await tester.pumpAndSettle();
        _expectWhole(tester, id, 'A');
        await _capture(tester, id, size, 'a', shots);
        final next = find.byKey(AppKeys.carouselNext(id));
        expect(next, findsOneWidget, reason: id);
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        _expectWhole(tester, id, 'B');
        await _capture(tester, id, size, 'b', shots);
        await _expectDragSnaps(tester, id);
      }
    }
  });
}

Future<void> _loadFonts() async {
  const dir = '/opt/flutter/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String name) async {
    final data = File('$dir/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(data).buffer);
  }

  if (!File('$dir/Roboto-Regular.ttf').existsSync()) {
    return;
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
  final preferred = Directory('/opt/cursor/artifacts/carousel-frames');
  try {
    preferred.createSync(recursive: true);
    return preferred;
  } catch (_) {
    return Directory.systemTemp.createTempSync('carousel-frames');
  }
}

Future<void> _show(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.carouselFrame(id)),
    500,
    scrollable: verticalScrollable,
  );
  await tester.pumpAndSettle();
}

void _expectWhole(WidgetTester tester, String id, String position) {
  final scrollable = _horizontal(id);
  final scroll = tester.state<ScrollableState>(scrollable).position;
  final layout = CarouselLayout.fit(
    viewport: scroll.viewportDimension,
    itemCount: 12,
    preferredItemWidth: carouselPreferredItemWidth,
  );
  final remainder = scroll.pixels % layout.stride;
  expect(
    remainder <= 1.5 || layout.stride - remainder <= 1.5,
    isTrue,
    reason: '$id $position pixels=${scroll.pixels} stride=${layout.stride}',
  );
  final view = tester.getRect(scrollable);
  var visible = 0;
  for (var index = 0; index < 24; index++) {
    final item = find.byKey(AppKeys.carouselItem(id, index));
    if (item.evaluate().isEmpty) {
      continue;
    }
    final rect = tester.getRect(item);
    final center = rect.center.dx;
    if (center < view.left || center > view.right) {
      continue;
    }
    visible += 1;
    expect(
      rect.left,
      greaterThanOrEqualTo(view.left - 1),
      reason: '$id $position item $index left ${rect.left} view ${view.left}',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(view.right + 1),
      reason:
          '$id $position item $index right ${rect.right} view ${view.right}',
    );
  }
  expect(visible, layout.perView, reason: '$id $position');
  if (scroll.pixels <= 1) {
    expect(find.byKey(AppKeys.carouselPrevious(id)), findsNothing);
  }
  if (scroll.pixels >= scroll.maxScrollExtent - 1) {
    expect(find.byKey(AppKeys.carouselNext(id)), findsNothing);
  }
}

Future<void> _expectDragSnaps(WidgetTester tester, String id) async {
  final scrollable = _horizontal(id);
  final scroll = tester.state<ScrollableState>(scrollable).position;
  final layout = CarouselLayout.fit(
    viewport: scroll.viewportDimension,
    itemCount: 12,
    preferredItemWidth: carouselPreferredItemWidth,
  );
  final origin = scroll.pixels;
  await tester.drag(scrollable, Offset(-layout.stride * 0.62, 0));
  await tester.pumpAndSettle();
  expect(scroll.pixels, closeTo(origin + layout.stride, 2), reason: id);
  _expectWhole(tester, id, 'arrasto');
  await tester.drag(scrollable, Offset(layout.stride * 0.2, 0));
  await tester.pumpAndSettle();
  expect(scroll.pixels, closeTo(origin + layout.stride, 2), reason: id);
}

Finder _horizontal(String id) {
  return find.descendant(
    of: find.byKey(AppKeys.carouselFrame(id)),
    matching: find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
    ),
  );
}

Future<void> _capture(
  WidgetTester tester,
  String id,
  Size size,
  String position,
  Directory dir,
) async {
  await tester.ensureVisible(find.byKey(AppKeys.carouselFrame(id)));
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(AppKeys.carouselFrame(id)),
  );
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
  final width = size.width.toInt();
  final file = File('${dir.path}/$id-$width-$position.png');
  file.writeAsBytesSync(bytes.buffer.asUint8List());
}
