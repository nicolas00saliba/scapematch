import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/photo_picker.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('framed photos keep the player mold and the simulated fill', (tester) async {
    final source = (await tester.runAsync(_portrait))!;
    final image = (await tester.runAsync(() => decodePhoto(source)))!;
    for (final frame in RoomFrame.values) {
      final png = (await tester.runAsync(() => renderRoomFrame(
        source: image,
        frame: frame,
        placement: const FramePlacement(),
      )))!;
      final fitted = (await tester.runAsync(() => decodePhoto(png)))!;
      expect(fitted.width, frame.width, reason: frame.name);
      expect(fitted.height, frame.height, reason: frame.name);
      fitted.dispose();
      final filled = (await tester.runAsync(
        () => simulateSceneFill(source: image, frame: frame),
      ))!;
      final expanded = (await tester.runAsync(() => decodePhoto(filled)))!;
      expect(expanded.width, frame.width, reason: frame.name);
      expect(expanded.height, frame.height, reason: frame.name);
      final raw = await tester.runAsync(() => expanded.toByteData());
      final pixels = raw!.buffer.asUint8List();
      expect(pixels[3], greaterThan(0), reason: '${frame.name} borda');
      expanded.dispose();
    }
    image.dispose();
  });

  testWidgets('a saved room keeps story, theme and photos for the player catalog', (
    tester,
  ) async {
    final database = loadSampleDatabase();
    final partner = PartnerRepository(
      groups: FakeGroupRepository(
        database,
        clock: loadSampleClock(),
        latency: Duration.zero,
      ),
      catalog: FakeCatalogRepository(database, latency: Duration.zero),
      database: database,
      clock: loadSampleClock(),
    );
    final source = (await tester.runAsync(_portrait))!;
    final image = (await tester.runAsync(() => decodePhoto(source)))!;
    final frames = <RoomFrame, Uint8List>{};
    for (final frame in RoomFrame.values) {
      frames[frame] = (await tester.runAsync(
        () => renderRoomFrame(
          source: image,
          frame: frame,
          placement: const FramePlacement(),
        ),
      ))!;
    }
    image.dispose();
    final error = partner.saveRoom(
      houseId: SampleIds.houseCwbRuaXv,
      name: 'Sala com foto',
      theme: 'Uma história curta da casa.',
      category: RoomCategory.terror,
      difficulty: Difficulty.easy,
      durationMinutes: 60,
      minimumPlayers: 2,
      capacity: 6,
      priceCents: 9900,
      accent: 0xFF1F6F8A,
      pictures: [
        RoomPicture(id: 'pic-1', source: source, frames: frames),
      ],
    );
    expect(error, isNull);
    final catalog = FakeCatalogRepository(database, latency: Duration.zero);
    final listed = await catalog.listRoomsByCity(SampleIds.curitiba);
    final room = listed.singleWhere((item) => item.room.name == 'Sala com foto').room;
    expect(room.theme, 'Uma história curta da casa.');
    expect(room.category, RoomCategory.terror);
    expect(room.pictureBytes(RoomFrame.card), isNotNull);
    expect(room.pictures.single.bytesFor(RoomFrame.hero), isNotNull);
  });

  testWidgets('a real portrait stays visible inside the card frame', (tester) async {
    final source = File(
      '../../assets/images/rooms/gallery/egito.jpg',
    ).readAsBytesSync();
    final image = (await tester.runAsync(() => decodePhoto(source)))!;
    final png = (await tester.runAsync(
      () => renderRoomFrame(
        source: image,
        frame: RoomFrame.card,
        placement: const FramePlacement(),
      ),
    ))!;
    final fitted = (await tester.runAsync(() => decodePhoto(png)))!;
    final raw = (await tester.runAsync(() => fitted.toByteData()))!;
    final pixels = raw.buffer.asUint8List();
    final colors = <int>{};
    for (var i = 0; i < pixels.length; i += 16) {
      colors.add((pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2]);
    }
    expect(fitted.width, RoomFrame.card.width);
    expect(fitted.height, RoomFrame.card.height);
    expect(colors.length, greaterThan(40));
    image.dispose();
    fitted.dispose();
  });

  testWidgets('the room form edits the story and expands a photo', (tester) async {
    final portrait = (await tester.runAsync(_portrait))!;
    await pumpParceiro(
      tester,
      overrides: [
        photoPickerProvider.overrideWithValue(_BytesPicker([portrait])),
      ],
    );
    await tester.enterText(find.byKey(PartnerKeys.partnerEmail), partnerDemoAccount.email);
    await tester.enterText(find.byKey(PartnerKeys.partnerPassword), partnerDemoPassword);
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(PartnerMessages.rooms).first);
    await tester.tap(find.text(PartnerMessages.rooms).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.agendaAddRoom));
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.roomStory), findsOneWidget);
    expect(find.text('Mistério'), findsWidgets);
    expect(find.text(PartnerMessages.roomPlayers), findsOneWidget);

    await tester.enterText(find.byKey(PartnerKeys.agendaRoomName), 'Sala ilustrada');
    await tester.enterText(
      find.byKey(PartnerKeys.roomStory),
      'O vapor guarda um retrato.',
    );
    await tester.tap(find.byKey(PartnerKeys.roomCategory('terror')));
    await tester.pumpAndSettle();

    await _reveal(tester, find.byKey(PartnerKeys.roomAddPhotos));
    await tester.tap(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(PartnerKeys.roomFramePreview));
    expect(find.byKey(PartnerKeys.roomFramePreview), findsOneWidget);
    expect(find.text('Card 300×168'), findsOneWidget);

    await _reveal(tester, find.byKey(PartnerKeys.roomExpand));
    await tester.tap(find.byKey(PartnerKeys.roomExpand));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.byKey(PartnerKeys.roomSimulated).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(PartnerKeys.roomSimulated), findsOneWidget);
  });
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 8; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      return;
    }
    await tester.drag(find.byKey(PartnerKeys.roomForm), const Offset(0, -350));
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
}

class _BytesPicker implements PhotoPicker {
  const _BytesPicker(this.photos);

  final List<Uint8List> photos;

  @override
  Future<List<Uint8List>> pick() async => photos;
}

Future<Uint8List> _portrait() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 80, 180),
    ui.Paint()..color = const ui.Color(0xFF1F6F8A),
  );
  canvas.drawCircle(
    const ui.Offset(40, 36),
    16,
    ui.Paint()..color = const ui.Color(0xFFD2642A),
  );
  final image = await recorder.endRecording().toImage(80, 180);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
