import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_withdrawals_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('a tela explica a Transferência Automática e não pede banco', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: VenueWithdrawalsPanel(
              venueId: 'casa-1',
              onOpenPagBank: (uri) => opened = uri,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(PartnerMessages.withdrawalsTitle), findsOneWidget);
    expect(find.text(PartnerMessages.withdrawalsBody), findsOneWidget);
    expect(find.text(PartnerMessages.receiveStepAccount), findsOneWidget);
    expect(find.text(PartnerMessages.receiveStepMenu), findsOneWidget);
    expect(find.text(PartnerMessages.receiveStepDestination), findsOneWidget);
    expect(find.text(PartnerMessages.receiveStepEnable), findsOneWidget);
    expect(find.text(PartnerMessages.withdrawalBank), findsNothing);
    expect(find.text(PartnerMessages.withdrawalSubmit), findsNothing);
    expect(find.byKey(PartnerKeys.withdrawalAmount), findsNothing);
    expect(find.byKey(PartnerKeys.withdrawalDocument), findsNothing);

    final button = find.byKey(PartnerKeys.receiveOpenPagBank);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(opened, VenueWithdrawalsPanel.pagBankUri);
  });
}
