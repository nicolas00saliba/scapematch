import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';

void main() {
  testWidgets('the room card uses the session photo', (tester) async {
    final source = (await tester.runAsync(_square))!;
    final image = (await tester.runAsync(() => decodePhoto(source)))!;
    final card = (await tester.runAsync(() => renderRoomFrame(
      source: image,
      frame: RoomFrame.card,
      placement: const FramePlacement(),
    )))!;
    image.dispose();
    final room = EscapeRoom(
      id: 'room-foto',
      houseId: 'house',
      name: 'Sala com foto',
      theme: 'Uma história curta.',
      category: RoomCategory.mystery,
      capacity: 6,
      durationMinutes: 60,
      difficulty: Difficulty.medium,
      priceCents: 9900,
      pictures: [
        RoomPicture(
          id: 'pic',
          source: source,
          frames: {RoomFrame.card: card},
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: roomCardWidth,
              child: RoomCard(
                listing: RoomListing(
                  room: room,
                  houseId: 'house',
                  houseName: 'Casa',
                  cityId: 'cwb',
                  cityName: 'Curitiba',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final photo = tester.widget<ScapePhoto>(find.byType(ScapePhoto));
    expect(photo.bytes, card);
    expect(find.text('Sala com foto'), findsOneWidget);
    expect(find.text('2–6 jogadores'), findsOneWidget);
  });
}

Future<Uint8List> _square() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 40, 40),
    ui.Paint()..color = const ui.Color(0xFF0F4C4A),
  );
  final image = await recorder.endRecording().toImage(40, 40);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
