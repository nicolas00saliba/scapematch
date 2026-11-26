import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('o cadastro de casa busca qualquer município e envia o id', (
    tester,
  ) async {
    await pumpParceiro(tester);
    await tester.tap(find.byKey(PartnerKeys.partnerSignup));
    await tester.pumpAndSettle();

    expect(find.text(PartnerMessages.venueCity), findsWidgets);
    expect(find.text(PartnerMessages.venueState), findsWidgets);
    expect(find.byKey(PartnerKeys.venueCity), findsOneWidget);
    expect(find.text('Curitiba'), findsOneWidget);

    await tester.enterText(find.byKey(PartnerKeys.venueCity), 'campinas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Campinas').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(PartnerKeys.venueName), 'Casa Nova');
    await tester.enterText(find.byKey(PartnerKeys.venuePostalCode), '13010000');
    await tester.enterText(find.byKey(PartnerKeys.venueNumber), '100');
    await tester.enterText(
      find.byKey(PartnerKeys.venueDocument),
      '39053344705',
    );
    await tester.tap(find.byKey(PartnerKeys.venueCheck));
    await tester.pumpAndSettle();

    expect(find.text(PartnerMessages.invalidVenue), findsNothing);
    expect(resolveVenueCity('campinas-sp'), 'campinas-sp');
  });
}
