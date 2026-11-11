import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/reviews/data/venue_staff_gateway.dart';
import 'package:scapematch/features/reviews/presentation/venue_invite_banner.dart';

void main() {
  testWidgets('aceitar tira o convite pendente', (tester) async {
    const invite = VenueInvite(
      venueId: 'casa-1',
      venueName: 'Ninja Escape',
      role: 'staff',
    );
    final gateway = MemoryVenueStaffGateway(invites: const [invite]);
    String? answered;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueInviteBanner(
            invites: gateway.invites,
            onAccept: (item) async {
              answered = item.venueId;
              return gateway.accept(item.venueId);
            },
            onDecline: (item) => gateway.decline(item.venueId),
          ),
        ),
      ),
    );

    expect(
      find.text('Ninja Escape convidou você para a equipe (equipe).'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(AppKeys.venueInviteAccept('casa-1')));
    await tester.pump();
    expect(answered, 'casa-1');
    expect(gateway.invites, isEmpty);
  });
}
