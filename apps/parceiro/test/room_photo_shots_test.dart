import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_detail_screen.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/photo_picker.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('saves room photo screenshots', (tester) async {
    if (Platform.environment['SCAPEMATCH_PHOTO_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/parceiro-fotos')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final portrait = File(
      '../../assets/images/rooms/gallery/egito.jpg',
    ).readAsBytesSync();
    await _parceiro(tester, dir, const Size(390, 844), '390', portrait);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _parceiro(tester, dir, const Size(1440, 900), '1440', portrait);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _player(tester, dir, const Size(390, 844), '390', portrait);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _player(tester, dir, const Size(1440, 900), '1440', portrait);
  });
}

Future<void> _parceiro(
  WidgetTester tester,
  Directory dir,
  Size size,
  String suffix,
  Uint8List portrait,
) async {
  await pumpParceiro(
    tester,
    size: size,
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
  await _shot(
    tester,
    dir,
    'personalizacao-$suffix.png',
    size,
    find.byKey(PartnerKeys.roomStory),
  );

  await tester.ensureVisible(find.byKey(PartnerKeys.roomAddPhotos));
  await tester.tap(find.byKey(PartnerKeys.roomAddPhotos));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Card · 300×168'));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'molduras-$suffix.png',
    size,
    find.text('Card · 300×168'),
  );

  await tester.ensureVisible(find.byKey(PartnerKeys.roomExpand));
  await tester.tap(find.byKey(PartnerKeys.roomExpand));
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    if (find.byKey(PartnerKeys.roomSimulated).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.ensureVisible(find.byKey(PartnerKeys.roomSimulated));
  await _shot(
    tester,
    dir,
    'expansao-$suffix.png',
    size,
    find.byKey(PartnerKeys.roomSimulated),
  );
}

Future<void> _player(
  WidgetTester tester,
  Directory dir,
  Size size,
  String suffix,
  Uint8List source,
) async {
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
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
          body: Center(
            child: SizedBox(
              width: roomCardWidth,
              child: RoomCard(
                listing: RoomListing(
                  room: _room(source, frames),
                  houseId: SampleIds.houseCwbRuaXv,
                  houseName: 'Mistério da Rua XV',
                  cityId: SampleIds.curitiba,
                  cityName: 'Curitiba',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  await _show(tester, [frames[RoomFrame.card]!]);
  await _shot(
    tester,
    dir,
    'jogador-card-$suffix.png',
    size,
    find.text('Sala com foto'),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final database = loadSampleDatabase();
  database.addRoom(_room(source, frames));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(loadSampleClock()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: const RoomDetailScreen(roomId: 'room-foto-demo'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _show(tester, [
    frames[RoomFrame.hero]!,
    frames[RoomFrame.heroWide]!,
    frames[RoomFrame.gallery]!,
    frames[RoomFrame.galleryWide]!,
  ]);
  await _shot(
    tester,
    dir,
    'jogador-detalhe-$suffix.png',
    size,
    find.text('Uma história curta da casa.'),
  );
}

EscapeRoom _room(Uint8List source, Map<RoomFrame, Uint8List> frames) {
  return EscapeRoom(
    id: 'room-foto-demo',
    houseId: SampleIds.houseCwbRuaXv,
    name: 'Sala com foto',
    theme: 'Uma história curta da casa.',
    category: RoomCategory.egypt,
    capacity: 6,
    durationMinutes: 60,
    difficulty: Difficulty.medium,
    priceCents: 9900,
    minimumPlayers: 2,
    pictures: [
      RoomPicture(id: 'pic-demo', source: source, frames: frames),
    ],
  );
}

Future<void> _show(WidgetTester tester, List<Uint8List> images) async {
  await tester.runAsync(() async {
    for (final bytes in images) {
      final done = Completer<void>();
      final stream = MemoryImage(bytes).resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        stream.removeListener(listener);
        if (!done.isCompleted) {
          done.complete();
        }
      }, onError: (error, stack) {
        stream.removeListener(listener);
        if (!done.isCompleted) {
          done.completeError(error, stack);
        }
      });
      stream.addListener(listener);
      await done.future;
    }
  });
  await tester.pump();
}

class _BytesPicker implements PhotoPicker {
  const _BytesPicker(this.photos);

  final List<Uint8List> photos;

  @override
  Future<List<Uint8List>> pick() async => photos;
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();
  const candidates = [
    '/tmp/flutter-sdk/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
  ];
  String? dir;
  for (final path in candidates) {
    if (File('$path/Roboto-Regular.ttf').existsSync()) {
      dir = path;
      break;
    }
  }
  if (dir == null) {
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
  final icons = FontLoader('MaterialIcons')..addFont(bytes('MaterialIcons-Regular.otf'));
  await roboto.load();
  await icons.load();
}

Future<void> _shot(
  WidgetTester tester,
  Directory dir,
  String name,
  Size expected,
  Finder anchor,
) async {
  expect(anchor, findsWidgets, reason: name);
  await tester.pump();
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = view.layer;
  expect(layer, isA<OffsetLayer>(), reason: name);
  final image = await tester.runAsync(
    () => (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
