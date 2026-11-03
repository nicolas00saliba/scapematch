import 'dart:io';
import 'dart:ui' as ui;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/theme/data/theme_choice_store.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('saves the reserved, closed and host states', (tester) async {
    if (Platform.environment['SCAPEMATCH_HOLD_SHOTS'] != '1') {
      return;
    }
    final dir = Directory('/opt/cursor/artifacts/reserva')
      ..createSync(recursive: true);
    await tester.runAsync(_loadFonts);

    const shots = [
      (size: Size(412, 915), theme: 'light', suffix: '412-claro'),
      (size: Size(1280, 900), theme: 'dark', suffix: '1280-escuro'),
    ];
    for (final shot in shots) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _flow(tester, dir, shot.size, shot.theme, shot.suffix);
    }
  });
}

Future<void> _flow(
  WidgetTester tester,
  Directory dir,
  Size size,
  String theme,
  String suffix,
) async {
  await pumpScapeMatch(
    tester,
    overrides: [
      themeChoiceStoreProvider.overrideWithValue(
        ThemeChoiceStore(saved: theme),
      ),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpAndSettle();

  await _openCobertura(tester);
  await tester.tap(find.byKey(AppKeys.joinButton));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.payMyShare));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.paySimulate));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.payDone));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.textContaining('reservaram').first,
  );
  await _waitForPhotos(tester);
  await _shot(
    tester,
    dir,
    'grupo-$suffix.png',
    size,
    find.text('Reservado'),
  );
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(AppKeys.leaveGroup));
  await tester.tap(find.byKey(AppKeys.leaveGroup));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.dialogConfirm));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(GroupMessages.holdReleased).first);
  await _shot(
    tester,
    dir,
    'liberado-$suffix.png',
    size,
    find.text(GroupMessages.holdReleased),
  );

  final repo = _repo(tester);
  final alone = await _create(tester, repo);
  await _openGroup(tester, alone);
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  await _shot(
    tester,
    dir,
    'fechar-off-$suffix.png',
    size,
    find.text(GroupMessages.roomMinimum(2)),
  );
  await _shot(
    tester,
    dir,
    'excluir-on-$suffix.png',
    size,
    find.text('Excluir grupo'),
  );

  final withGuest = await _create(tester, repo);
  final joined = await _call(
    tester,
    () => repo.join(
      withGuest,
      participantUserId: 'user-bia',
      participantName: 'Bia',
      markAsLocalUser: false,
    ),
  );
  expect(joined, isA<JoinSuccess>());
  await _call(
    tester,
    () => repo.payShare(
      withGuest,
      userId: 'user-local',
      kind: PaymentMethodKind.pix,
    ),
  );
  await _call(
    tester,
    () => repo.payShare(
      withGuest,
      userId: 'user-bia',
      kind: PaymentMethodKind.pix,
    ),
  );
  await _openGroup(tester, withGuest);
  await _shot(
    tester,
    dir,
    'fechar-on-$suffix.png',
    size,
    find.textContaining('Fechar com'),
  );

  final closed = await _call(
    tester,
    () => repo.closeWithFewer(withGuest, userId: 'user-local'),
  );
  expect(closed, isA<CloseGroupSuccess>());
  await _openGroup(tester, withGuest);
  await tester.ensureVisible(find.text('Pago').first);
  await _shot(tester, dir, 'pago-$suffix.png', size, find.text('Pago'));

  _shift(tester, alone, DateTime.now().add(const Duration(minutes: 30)));
  await _openGroup(tester, alone);
  await _shot(
    tester,
    dir,
    'excluir-off-$suffix.png',
    size,
    find.text(GroupMessages.cannotDeleteYet),
  );
}

Future<String> _create(WidgetTester tester, FakeGroupRepository repo) async {
  final result = await _call(
    tester,
    () => repo.create(
      CreateGroupRequest(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: _openSlot(tester),
        extraSpots: 3,
        creatorUserId: 'user-local',
        creatorDisplayName: 'Nícolas',
      ),
    ),
  );
  expect(result, isA<CreateGroupSuccess>());
  return (result as CreateGroupSuccess).group.id;
}

Future<T> _call<T>(WidgetTester tester, Future<T> Function() action) async {
  final future = action();
  await tester.pump(const Duration(milliseconds: 400));
  return future;
}

String _openSlot(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  final database = ProviderScope.containerOf(context).read(fakeDatabaseProvider);
  final taken = {
    for (final group in database.groups)
      if (!group.isCancelled && group.roomId == SampleIds.roomPoaEstufa)
        group.startsAt,
  };
  final slot = database.slots.firstWhere(
    (item) =>
        item.roomId == SampleIds.roomPoaEstufa &&
        item.startsAt.isAfter(DateTime.now().add(const Duration(hours: 3))) &&
        !taken.contains(item.startsAt),
  );
  return slot.id;
}

FakeGroupRepository _repo(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  return ProviderScope.containerOf(context).read(groupRepositoryProvider)
      as FakeGroupRepository;
}

void _shift(WidgetTester tester, String id, DateTime startsAt) {
  final context = tester.element(find.byType(Scaffold).first);
  final container = ProviderScope.containerOf(context);
  final database = container.read(fakeDatabaseProvider);
  final index = database.groups.indexWhere((group) => group.id == id);
  database.groups[index] = database.groups[index].copyWith(startsAt: startsAt);
  container.invalidate(groupDetailViewModelProvider(id));
}

Future<void> _openCobertura(WidgetTester tester) async {
  await tester.tap(find.byKey(AppKeys.citySelector));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AppKeys.cityOption(SampleIds.saoPaulo)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(AppKeys.groupSearch), 'Cobertura');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
    300,
    scrollable: verticalScrollable,
  );
  await tester.tap(
    find.byKey(AppKeys.groupCard(SampleIds.groupSpCoberturaOpen)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openGroup(WidgetTester tester, String id) async {
  final context = tester.element(find.byType(Scaffold).first);
  ProviderScope.containerOf(context).invalidate(groupDetailViewModelProvider(id));
  GoRouter.of(context).go('/');
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/groups/$id');
  await tester.pumpAndSettle();
}

Future<void> _waitForPhotos(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  final assets = <AssetImage>[
    for (final photo in tester.widgetList<ScapePhoto>(find.byType(ScapePhoto)))
      AssetImage(photo.asset),
  ];
  if (assets.isEmpty) {
    return;
  }
  await tester.runAsync(() async {
    for (final asset in assets) {
      await precacheImage(asset, context);
    }
  });
  await tester.pump();
}

Future<void> _loadFonts() async {
  final poppins = await rootBundle.load('assets/fonts/Poppins-Medium.ttf');
  final brand = FontLoader('Poppins')..addFont(Future.value(poppins));
  await brand.load();

  const dir = '/home/ubuntu/flutter/bin/cache/artifacts/material_fonts';
  if (!File('$dir/Roboto-Regular.ttf').existsSync()) {
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
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
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
    () =>
        (layer! as OffsetLayer).toImage(Offset.zero & view.size, pixelRatio: 1),
  );
  expect(image!.width, expected.width.round(), reason: name);
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
}
