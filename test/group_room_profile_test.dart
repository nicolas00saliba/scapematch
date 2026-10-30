import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/catalog/presentation/room_detail_screen.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  testWidgets('the group screen shows the room cover and profile', (
    tester,
  ) async {
    await pumpScapeMatch(
      tester,
      overrides: [clockProvider.overrideWithValue(FixedClock(sampleNow))],
    );

    expect(
      find.descendant(
        of: find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Hero &&
              widget.tag == groupHeroTag(SampleIds.groupCwbCofreAlmost),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(AppKeys.groupCard(SampleIds.groupCwbCofreAlmost)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(find.byKey(AppKeys.groupCover), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.groupCover),
        matching: find.text('O Cofre do Café'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AppKeys.groupCover),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Hero &&
              widget.tag == groupHeroTag(SampleIds.groupCwbCofreAlmost),
        ),
      ),
      findsOneWidget,
    );

    expect(find.text('Sobre a sala'), findsOneWidget);
    expect(find.byKey(AppKeys.roomProfile), findsOneWidget);
    expect(find.text('História'), findsOneWidget);
    expect(find.text('Um café que fecha a porta sozinho'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
    expect(find.text('Médio'), findsOneWidget);
    expect(find.text('Até 6 pessoas'), findsOneWidget);
    expect(find.textContaining('por pessoa'), findsWidgets);
    expect(find.text('Mistério da Rua XV'), findsOneWidget);
    expect(find.textContaining('Rua de exemplo'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppKeys.groupRoomGallery),
        matching: find.byType(ScapePhoto),
      ),
      findsNWidgets(3),
    );

    expect(find.byKey(AppKeys.inviteGroup), findsOneWidget);
    expect(find.text('Entrar no grupo'), findsOneWidget);
    expect(find.byKey(AppKeys.openMaps), findsOneWidget);
    expect(find.byKey(AppKeys.openWaze), findsOneWidget);
    expect(find.byKey(AppKeys.groupPhase), findsOneWidget);
    expect(find.byKey(AppKeys.closeDeadline), findsOneWidget);
    expect(find.text('Quem já está'), findsOneWidget);

    final scrollable = find.descendant(
      of: find.byType(GroupDetailScreen),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.openRoomDetail));
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsOneWidget);
    expect(
      find.byKey(AppKeys.roomDetail(SampleIds.roomCwbCofre)),
      findsOneWidget,
    );
    expect(
      ModalRoute.of(tester.element(find.byType(RoomDetailScreen)))!.isCurrent,
      isTrue,
    );
  });
}
