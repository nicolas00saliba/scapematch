import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_home_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_pending_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';

void main() {
  testWidgets('saves house signup, waiting and the approved desk', (
    tester,
  ) async {
    if (Platform.environment['SCAPEMATCH_LOGIN_REAL_SHOTS'] != '1') return;
    final dir = Directory('/opt/cursor/artifacts/login-real')
      ..createSync(recursive: true);
    addTearDown(() => scapeUsesLiveBackend = false);
    scapeUsesLiveBackend = true;
    await tester.runAsync(_loadFonts);
    final database = buildSampleDatabase(now: DateTime(2026, 11, 4, 15));
    final cities = cityRepositoryProvider.overrideWithValue(
      FakeCityRepository(database, latency: Duration.zero),
    );
    for (final size in const [Size(1440, 1400), Size(390, 1600)]) {
      final width = size.width.round();
      await _pump(
        tester,
        size,
        home: const PartnerVenueScreen(),
        session: _Session.new,
        cities: cities,
      );
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        find.byType(PartnerVenueScreen),
        dir,
        'casa-cadastro-$width',
      );
      await _pump(
        tester,
        size,
        home: const PartnerPendingScreen(rejected: false),
        session: _PendingSession.new,
        cities: cities,
      );
      await _capture(
        tester,
        find.byKey(PartnerKeys.partnerPending),
        dir,
        'casa-aguardando-$width',
      );
      await _pump(
        tester,
        size,
        home: PartnerHome(snapshot: _desk()),
        session: _ApprovedSession.new,
        cities: cities,
      );
      await _capture(
        tester,
        find.byKey(PartnerKeys.partnerHouseName),
        dir,
        'casa-painel-$width',
      );
    }
  });
}

class _ApprovedSession extends PartnerSessionController {
  @override
  PartnerAccount? build() {
    return const PartnerAccount(
      email: 'casa@exemplo.invalid',
      houseId: 'demo',
      houseName: 'ScapeMatch Demo',
      userId: 'user-1',
      venueStatus: 'approved',
    );
  }
}

class _Session extends PartnerSessionController {
  @override
  PartnerAccount? build() {
    return const PartnerAccount(
      email: 'casa@exemplo.invalid',
      houseId: '',
      houseName: '',
      userId: 'user-1',
      venueStatus: null,
    );
  }
}

class _PendingSession extends PartnerSessionController {
  @override
  PartnerAccount? build() {
    return const PartnerAccount(
      email: 'casa@exemplo.invalid',
      houseId: 'venue-1',
      houseName: 'Ninja Escape Room',
      userId: 'user-1',
      venueStatus: 'pending',
    );
  }
}

PartnerSnapshot _desk() {
  const house = EscapeHouse(
    id: 'demo',
    cityId: 'curitiba',
    name: 'ScapeMatch Demo',
    neighborhood: 'Centro',
    latitude: -25.4296,
    longitude: -49.2719,
    streetAddress: 'Rua XV de Novembro, 100',
  );
  EscapeRoom room(String id, String name, RoomCategory category, int price) {
    return EscapeRoom(
      id: id,
      houseId: house.id,
      name: name,
      theme: name,
      category: category,
      capacity: 6,
      minimumPlayers: 2,
      durationMinutes: 60,
      difficulty: Difficulty.medium,
      priceCents: price,
    );
  }

  final cofre = room('cofre', 'O Cofre', RoomCategory.mystery, 12000);
  return PartnerSnapshot(
    house: house,
    now: DateTime(2026, 11, 4, 15),
    grossCents: 0,
    commissionCents: 0,
    netCents: 0,
    reservedCents: 0,
    lines: const [],
    moneyByGroup: const {},
    groups: [
      Group(
        id: 'grupo-demo',
        cityId: 'curitiba',
        cityName: 'Curitiba',
        houseId: house.id,
        houseName: house.name,
        neighborhood: house.neighborhood,
        roomId: cofre.id,
        roomName: cofre.name,
        roomTheme: cofre.theme,
        roomCapacity: cofre.capacity,
        roomMinimum: 2,
        durationMinutes: 60,
        difficulty: Difficulty.medium,
        slotId: 'sessao-1',
        startsAt: DateTime(2026, 11, 6, 19),
        filledSpots: 1,
        totalSpots: 6,
        participants: const [
          Participant(
            id: 'membro-1',
            displayName: 'Ana',
            isCreator: true,
            isLocalUser: false,
          ),
        ],
        priceCents: 12000,
        streetAddress: house.streetAddress,
      ),
    ],
    rooms: [
      cofre,
      room('biblioteca', 'A Biblioteca', RoomCategory.adventure, 10000),
      room('calabouco', 'O Calabouço', RoomCategory.terror, 14000),
    ],
    slotsByRoom: const {},
    absenceCounts: const {},
    absenceMarks: const {},
    standings: const {},
    invoices: const [],
    fiscal: demoHouseFiscal,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required Widget home,
  required PartnerSessionController Function() session,
  required Override cities,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 11, 4, 15))),
        cities,
        partnerSessionProvider.overrideWith(session),
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
  const candidates = [
    '/opt/flutter/bin/cache/artifacts/material_fonts',
    '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts',
  ];
  final root = candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
    orElse: () => '',
  );
  if (root.isEmpty) return;
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
