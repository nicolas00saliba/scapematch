import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_possession_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  test('o código só segue com 6 dígitos', () {
    expect(claimCodeLooksValid('482193'), isTrue);
    expect(claimCodeLooksValid(' 482193 '), isTrue);
    expect(claimCodeLooksValid('48219'), isFalse);
    expect(claimCodeLooksValid('4821931'), isFalse);
    expect(claimCodeLooksValid('48a193'), isFalse);
  });

  test('a busca não guarda o contato oficial', () {
    final venue = ClaimableVenue.fromJson({
      'path': 'otp',
      'venue_id': 'casa-ninja',
      'name': 'Ninja Escape Room',
      'city_id': 'curitiba',
      'neighborhood': 'Batel',
      'has_official_email': true,
      'has_official_phone': false,
      'email': 'oficial@ninja.example',
      'phone': '41910001992',
    });
    expect(venue.offersClaim, isTrue);
    expect(venue.name, 'Ninja Escape Room');
    expect(venue.hasOfficialEmail, isTrue);
    expect(venue.hasOfficialPhone, isFalse);
    expect('$venue'.contains('oficial@ninja.example'), isFalse);
  });

  testWidgets('o CNPJ encontrado oferece reivindicar a casa que já existe', (
    tester,
  ) async {
    var claimed = false;
    await tester.pumpWidget(
      _app(
        VenueClaimOffer(
          venue: _ninja(VenueClaimPath.otp),
          onClaim: () => claimed = true,
        ),
      ),
    );
    expect(find.text(PartnerMessages.claimOfferTitle), findsOneWidget);
    expect(find.text('Ninja Escape Room'), findsOneWidget);
    expect(find.text(PartnerMessages.claimOfferButton), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.venueClaim));
    await tester.pump();
    expect(claimed, isTrue);
  });

  testWidgets('código curto não confirma e o certo abre a subconta', (
    tester,
  ) async {
    String? confirmed;
    var provisions = 0;
    await tester.pumpWidget(
      _app(
        VenueClaimDesk(
          venue: _ninja(VenueClaimPath.otp),
          onSend: () async => const ClaimDispatch(
            status: 'otp',
            hint: 'o***@ninja.example',
          ),
          onConfirm: (code) async {
            confirmed = code;
            return code == '482193';
          },
          onProvision: () async {
            provisions += 1;
            return null;
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(PartnerKeys.venueClaimCode), '48219');
    await tester.tap(find.byKey(PartnerKeys.venueClaimConfirm));
    await tester.pump();
    expect(find.text(PartnerMessages.claimMismatch), findsOneWidget);
    expect(confirmed, isNull);

    await tester.enterText(find.byKey(PartnerKeys.venueClaimCode), '482193');
    await tester.tap(find.byKey(PartnerKeys.venueClaimConfirm));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(PartnerKeys.venueClaimFinance), findsOneWidget);
    expect(find.text(PartnerMessages.claimLinked), findsOneWidget);
    expect(confirmed, '482193');

    await tester.tap(find.byKey(PartnerKeys.venueClaimProvision));
    await tester.pump();
    await tester.pump();
    expect(provisions, 1);
    expect(find.text(PartnerMessages.claimProvisionDone), findsOneWidget);
  });

  testWidgets('perfil sem contato oficial pede aprovação do admin', (
    tester,
  ) async {
    var sent = false;
    await tester.pumpWidget(
      _app(
        VenueClaimDesk(
          venue: _ninja(VenueClaimPath.manual),
          onSend: () async {
            sent = true;
            return const ClaimDispatch(status: 'manual');
          },
          onConfirm: (_) async => false,
          onProvision: () async => null,
        ),
      ),
    );
    expect(find.text(PartnerMessages.claimManualSent), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueClaimCode), findsNothing);
    await tester.tap(find.byKey(PartnerKeys.venueClaimSend));
    await tester.pump();
    await tester.pump();
    expect(sent, isTrue);
    expect(find.byKey(PartnerKeys.venueClaimSent), findsOneWidget);
  });
}

ClaimableVenue _ninja(VenueClaimPath path) {
  return ClaimableVenue(
    path: path,
    venueId: 'casa-ninja',
    name: 'Ninja Escape Room',
    cityId: 'curitiba',
    neighborhood: 'Batel',
    hasOfficialEmail: path == VenueClaimPath.otp,
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}
