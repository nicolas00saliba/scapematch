import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/splash_gate.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

void main() {
  testWidgets(
    'the wordmark stays hidden until the pin can paint in the same frame',
    (tester) async {
      final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
      final loader = FontLoader('Poppins')..addFont(Future.value(poppins));
      await tester.runAsync(loader.load);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bundle = _LatePinBundle(rootBundle);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: DefaultAssetBundle(
            bundle: bundle,
            child: const SplashGate(child: SizedBox.expand()),
          ),
        ),
      );

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_wordmark(), findsNothing);
        expect(_pin(), findsNothing);
        expect(find.byKey(AppKeys.splash), findsOneWidget);
        expect(find.byKey(SplashGate.logoOpacityKey), findsNothing);
      }
      await _saveFrame(tester, 'after-splash-waiting.png');

      bundle.release();
      var appeared = false;
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        final word = _wordmark().evaluate().isNotEmpty;
        final pin = _pin().evaluate().isNotEmpty;
        expect(word, pin, reason: 'frame $i word=$word pin=$pin');
        if (word && pin) {
          appeared = true;
          expect(
            tester
                .widget<Opacity>(find.byKey(SplashGate.logoOpacityKey))
                .opacity,
            0,
          );
          expect(
            tester.widget<ScapePinBox>(_pin()).assetName,
            ScapeLogo.markAsset,
          );
          break;
        }
      }
      expect(appeared, isTrue);

      await tester.pump(const Duration(milliseconds: 48));
      final image = await _raster(tester);
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final pinInk = _ink(tester.getRect(_pin()), image, data!);
      final wordInk = _ink(tester.getRect(_wordmark()), image, data);
      image.dispose();
      expect(pinInk, greaterThan(20));
      expect(wordInk, greaterThan(20));
      await _saveFrame(tester, 'after-splash-lockup.png');
      final holdMs =
          (SplashGate.duration.inMilliseconds * SplashGate.holdEnd).round() -
          48;
      await tester.pump(Duration(milliseconds: holdMs));
      await _saveFrame(tester, 'after-splash-hold.png');
    },
  );
}

Future<void> _saveFrame(WidgetTester tester, String name) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) {
    return;
  }
  final image = await _raster(tester);
  final png = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
  image.dispose();
}

Finder _wordmark() {
  return find.descendant(
    of: find.byKey(AppKeys.splash),
    matching: find.text('ScapeMatch'),
  );
}

Finder _pin() {
  return find.descendant(
    of: find.byKey(AppKeys.splash),
    matching: find.byType(ScapePinBox),
  );
}

Future<ui.Image> _raster(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer! as OffsetLayer;
  final image = await tester.runAsync(
    () => layer.toImage(Offset.zero & view.size),
  );
  return image!;
}

int _ink(Rect rect, ui.Image image, ByteData data) {
  final bytes = data.buffer.asUint8List();
  final left = rect.left.floor().clamp(0, image.width - 1);
  final right = rect.right.ceil().clamp(0, image.width);
  final top = rect.top.floor().clamp(0, image.height - 1);
  final bottom = rect.bottom.ceil().clamp(0, image.height);
  var count = 0;
  for (var y = top; y < bottom; y += 2) {
    for (var x = left; x < right; x += 2) {
      final i = (y * image.width + x) * 4;
      final delta =
          (bytes[i] - 255).abs() +
          (bytes[i + 1] - 255).abs() +
          (bytes[i + 2] - 255).abs();
      if (delta > 24) {
        count++;
      }
    }
  }
  return count;
}

class _LatePinBundle extends CachingAssetBundle {
  _LatePinBundle(this.inner);

  final AssetBundle inner;
  final Completer<void> _gate = Completer<void>();

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  bool _holds(String key) => key.contains('logo_simbolo');

  @override
  Future<ByteData> load(String key) {
    if (_holds(key)) {
      return _gate.future.then((_) => inner.load(key));
    }
    return inner.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    return inner.loadString(key, cache: cache);
  }
}
