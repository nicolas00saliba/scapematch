import 'dart:async';
import 'dart:typed_data';

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch_parceiro/features/partner/data/photo_picker.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_room_form.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('foto ilegível avisa e conserva as outras', (tester) async {
    final good = _png(width: 24, height: 36);
    final picker = _ScriptedPicker([
      RoomPhotoPick([good]),
      const RoomPhotoPick(
        <Uint8List>[],
        error: 'Não consegui abrir esta foto. Tente uma foto JPG ou PNG.',
      ),
    ]);
    await _pump(tester, picker);

    await tester.ensureVisible(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.tap(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(PartnerKeys.roomFramePreview), findsOneWidget);
    expect(find.text(PartnerMessages.roomPhotoUnread), findsNothing);

    await tester.ensureVisible(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.tap(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.roomPhotoUnread), findsOneWidget);
    expect(find.byKey(PartnerKeys.roomFramePreview), findsOneWidget);
  });

  testWidgets('preparar fotos avisa e desativa os botões', (tester) async {
    final good = _png(width: 24, height: 36);
    final gate = Completer<RoomPhotoPick>();
    var started = false;
    final picker = _GatedPicker(gate.future, () {
      started = true;
      expect(find.text(PartnerMessages.roomPhotosPreparing), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(PartnerKeys.roomAddPhotos)).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(PartnerKeys.agendaSaveRoom)).onPressed,
        isNull,
      );
    });
    await _pump(tester, picker);

    await tester.ensureVisible(find.byKey(PartnerKeys.roomAddPhotos));
    await tester.tap(find.byKey(PartnerKeys.roomAddPhotos));
    expect(started, isFalse);
    expect(find.text(PartnerMessages.roomPhotosPreparing), findsNothing);

    await tester.pump(Duration.zero);

    expect(started, isTrue);
    expect(find.text(PartnerMessages.roomPhotosPreparing), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(PartnerKeys.roomAddPhotos)).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(PartnerKeys.agendaSaveRoom)).onPressed,
      isNull,
    );

    gate.complete(RoomPhotoPick([good]));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.roomPhotosPreparing), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byKey(PartnerKeys.roomAddPhotos)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(PartnerKeys.agendaSaveRoom)).onPressed,
      isNotNull,
    );
    expect(find.byKey(PartnerKeys.roomFramePreview), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, PhotoPicker picker) async {
  tester.view.physicalSize = const Size(480, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [photoPickerProvider.overrideWithValue(picker)],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: PartnerRoomForm(snapshot: _snapshot())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PartnerSnapshot _snapshot() {
  return PartnerSnapshot(
    house: const EscapeHouse(
      id: 'casa-1',
      cityId: 'curitiba',
      name: 'Casa da Foto',
      neighborhood: 'Centro',
      latitude: -25.4,
      longitude: -49.2,
      receivesPayments: true,
    ),
    now: DateTime(2026, 11, 20, 12),
    grossCents: 0,
    commissionCents: 0,
    netCents: 0,
    reservedCents: 0,
    lines: const [],
    moneyByGroup: const {},
    groups: const [],
    rooms: const [],
    slotsByRoom: const {},
    absenceCounts: const {},
    absenceMarks: const {},
    standings: const {},
    invoices: const [],
    fiscal: demoHouseFiscal,
  );
}

class _GatedPicker implements PhotoPicker {
  _GatedPicker(this.pending, this.onPick);

  final Future<RoomPhotoPick> pending;
  final void Function() onPick;

  @override
  Future<RoomPhotoPick> pick() {
    onPick();
    return pending;
  }
}

class _ScriptedPicker implements PhotoPicker {
  _ScriptedPicker(this.steps);

  final List<RoomPhotoPick> steps;
  var index = 0;

  @override
  Future<RoomPhotoPick> pick() async {
    final step = steps[index];
    index += 1;
    return step;
  }
}

Uint8List _png({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 90, 140));
  return img.encodePng(image);
}
