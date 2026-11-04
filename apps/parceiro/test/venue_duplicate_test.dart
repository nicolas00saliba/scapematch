import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_board.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  test('normaliza documento, número e nome como o banco', () {
    expect(normalizeDocument('12.345.678/0001-95'), '12345678000195');
    expect(normalizeDocument('123.456.789-09'), '12345678909');
    expect(normalizeAddressNumber('nº 120'), '120');
    expect(normalizeAddressNumber('S/N'), 'sn');
    expect(normalizeVenueName('Ninja Escape Room Ltda.'), 'ninja');
    expect(normalizeVenueName('Mistério da Rua XV'), 'misterio da rua xv');
    expect(normalizeVenueName('Quest S.A.'), 'quest');
    expect(resolveVenueCity('Curitiba'), 'curitiba');
    expect(resolveVenueCity('São Paulo'), 'sao-paulo');
    expect(
      trigramSimilarity('ninja', 'ninja centro'),
      closeTo(0.461538, 0.0001),
    );
    expect(
      trigramSimilarity('caldeira', 'caldeirao'),
      closeTo(0.727273, 0.0001),
    );
    expect(venueNamesMatch('ninja', 'ninja centro'), isTrue);
    expect(venueNamesMatch('caldeira', 'caldeirao'), isTrue);
    expect(venueNamesMatch('misterio da rua xv', 'caldeira'), isFalse);
  });

  test('documento repetido bloqueia e não revela casa pendente', () {
    final board = VenueBoard.demo();
    const secret = VenueRecord(
      id: 'venue-secreta',
      ownerId: 'owner-secreta',
      cityId: 'curitiba',
      name: 'Casa Sigilosa do Lote 9',
      neighborhood: 'Batel',
      streetAddress: 'Rua Escondida',
      addressNumber: '44',
      postalCode: '80020999',
      documentNumber: '52998224725',
      phone: '41977776666',
      status: 'pending',
    );
    final withSecret = VenueBoard(
      venues: [...board.venues, secret],
      claims: board.claims,
    );
    final hidden = withSecret.check(
      const VenueDraft(
        ownerId: venueSignupOwnerId,
        name: 'Outra',
        cityId: 'curitiba',
        postalCode: '01310000',
        addressNumber: '9',
        document: '529.982.247-25',
      ),
    );
    final document = hidden.singleWhere(
      (conflict) => conflict.type == venueConflictDocument,
    );
    expect(document.blocks, isTrue);
    expect(document.venueId, isNull);
    expect(document.venueName, isNull);
    expect(
      hidden.any(
        (conflict) => conflict.venueName?.contains('Sigilosa') ?? false,
      ),
      isFalse,
    );
    expect(
      () => withSecret.submit(
        const VenueDraft(
          ownerId: venueSignupOwnerId,
          name: 'Outra',
          cityId: 'curitiba',
          postalCode: '01310000',
          addressNumber: '9',
          document: '52998224725',
        ),
      ),
      throwsA(isA<VenueDocumentBlocked>()),
    );

    final approved = board.check(
      const VenueDraft(
        ownerId: venueSignupOwnerId,
        name: 'Outra',
        cityId: 'curitiba',
        postalCode: '01310000',
        addressNumber: '9',
        document: '12.345.678/0001-95',
      ),
    );
    final named = approved.single;
    expect(named.type, venueConflictDocument);
    expect(named.venueId, VenueBoard.approvedNinjaId);
    expect(named.venueName, 'Ninja Escape Room Ltda.');
    expect(named.toString(), isNot(contains('41988887777')));
  });

  test('CEP e nome parecido avisam e o envio fica marcado', () {
    final board = VenueBoard.demo();
    const draft = VenueDraft(
      ownerId: venueSignupOwnerId,
      name: 'Ninja Centro',
      cityId: 'Curitiba',
      postalCode: '80010-000',
      addressNumber: '120',
      document: '10987654321',
    );
    final conflicts = board.check(draft);
    expect(
      conflicts.map((conflict) => conflict.type),
      containsAll([venueConflictAddress, venueConflictName]),
    );
    expect(
      conflicts.every(
        (conflict) => conflict.venueName == 'Ninja Escape Room Ltda.',
      ),
      isTrue,
    );
    expect(board.duplicateTarget(conflicts), VenueBoard.approvedNinjaId);

    final otherCity = board.check(
      const VenueDraft(
        ownerId: venueSignupOwnerId,
        name: 'Ninja Centro',
        cityId: 'sao-paulo',
        postalCode: '01001000',
        addressNumber: '50',
        document: '10987654321',
      ),
    );
    expect(
      otherCity.any((conflict) => conflict.type == venueConflictName),
      isFalse,
    );

    final sent = board.submit(
      draft,
      possibleDuplicateOf: board.duplicateTarget(conflicts),
    );
    final created = sent.venues.last;
    expect(created.status, 'pending');
    expect(created.possibleDuplicateOf, VenueBoard.approvedNinjaId);
    expect(created.phone, isEmpty);
  });

  test('reivindicação fica com quem pediu e o admin decide', () {
    final board = VenueBoard.demo();
    expect(board.claimsVisibleTo(null, admin: false), isEmpty);
    expect(board.claimsVisibleTo('alguem', admin: false), isEmpty);
    expect(
      board.claimsVisibleTo(VenueBoard.applicantId, admin: false).single.id,
      VenueBoard.ninjaClaimId,
    );

    final claimed = board.claim(
      venueId: VenueBoard.approvedNinjaId,
      claimantId: venueSignupOwnerId,
      note: 'Sou a responsável.',
    );
    expect(
      claimed.claimsVisibleTo(venueSignupOwnerId, admin: false).single.note,
      'Sou a responsável.',
    );
    expect(
      claimed.claimsVisibleTo(VenueBoard.ninjaOwnerId, admin: false),
      isEmpty,
    );
    expect(
      () => board.claim(
        venueId: VenueBoard.approvedNinjaId,
        claimantId: VenueBoard.ninjaOwnerId,
        note: 'Já é minha',
      ),
      throwsA(isA<VenueClaimProblem>()),
    );

    final decided = board.reviewClaim(
      claimId: VenueBoard.ninjaClaimId,
      decision: 'approved',
    );
    expect(
      decided.venueById(VenueBoard.approvedNinjaId)!.ownerId,
      VenueBoard.applicantId,
    );
    expect(decided.venueById(VenueBoard.pendingNinjaId)!.status, 'merged');
    expect(
      decided.venueById(VenueBoard.pendingNinjaId)!.mergedInto,
      VenueBoard.approvedNinjaId,
    );

    final merged = board.reviewVenue(
      venueId: VenueBoard.pendingNinjaId,
      decision: 'merged',
      mergeInto: VenueBoard.approvedNinjaId,
    );
    expect(merged.venueById(VenueBoard.pendingNinjaId)!.status, 'merged');
    expect(merged.pendingVenues, isEmpty);
  });

  test('a migration não entrega documento nem casa pendente ao anon', () {
    final file = [
      File('supabase/migrations/20261104130000_venue_duplicates.sql'),
      File('../../supabase/migrations/20261104130000_venue_duplicates.sql'),
    ].firstWhere((candidate) => candidate.existsSync());
    final sql = file.readAsStringSync();
    expect(sql, contains('check_venue_duplicates'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('force row level security'));
    expect(sql, contains('pg_trgm'));
    expect(sql, contains('venue_claims'));
    expect(sql, contains("'documento'"));
    expect(sql, contains("'endereço'"));
    expect(sql, contains("'nome parecido'"));
    expect(sql, contains('possible_duplicate_of'));
    expect(
      sql,
      contains(
        'revoke all on table public.venue_claims from public, anon, authenticated',
      ),
    );
    expect(sql, contains('security invoker'));
    expect(sql, isNot(contains('grant select (document_digits)')));
    expect(sql, isNot(contains('grant select (phone)')));
  });

  testWidgets('o aviso deixa enviar e abre Esta casa é minha', (tester) async {
    await pumpParceiro(tester, size: const Size(1440, 900));
    await _tap(tester, find.byKey(PartnerKeys.partnerSignup));
    await tester.enterText(find.byKey(PartnerKeys.venueName), 'Ninja Centro');
    await tester.enterText(
      find.byKey(PartnerKeys.venuePostalCode),
      '80010-000',
    );
    await tester.enterText(find.byKey(PartnerKeys.venueNumber), '120');
    await tester.enterText(
      find.byKey(PartnerKeys.venueDocument),
      '10987654321',
    );
    await _tap(tester, find.byKey(PartnerKeys.venueCheck));

    expect(find.byKey(PartnerKeys.venueDuplicateBanner), findsOneWidget);
    expect(find.text(PartnerMessages.duplicateTitle), findsOneWidget);
    expect(find.textContaining('Ninja Escape Room Ltda.'), findsWidgets);
    expect(find.textContaining('41988887777'), findsNothing);
    expect(find.textContaining('12345678000195'), findsNothing);
    expect(find.textContaining('Casa Sigilosa'), findsNothing);

    await _tap(tester, find.byKey(PartnerKeys.venueClaim));
    expect(find.text(PartnerMessages.claimTitle), findsWidgets);
    expect(find.text(PartnerMessages.claimBody), findsOneWidget);
    await tester.enterText(
      find.byKey(PartnerKeys.venueClaimNote),
      'Eu respondo por essa casa.',
    );
    await _tap(tester, find.byKey(PartnerKeys.venueClaimSubmit));
    expect(find.byKey(PartnerKeys.venueClaimSent), findsOneWidget);
  });

  testWidgets('documento repetido não tem envio', (tester) async {
    await pumpParceiro(tester, size: const Size(390, 844));
    await _tap(tester, find.byKey(PartnerKeys.partnerSignup));
    await tester.enterText(find.byKey(PartnerKeys.venueName), 'Outra casa');
    await tester.enterText(find.byKey(PartnerKeys.venuePostalCode), '01310000');
    await tester.enterText(find.byKey(PartnerKeys.venueNumber), '9');
    await tester.enterText(
      find.byKey(PartnerKeys.venueDocument),
      '12.345.678/0001-95',
    );
    await _tap(tester, find.byKey(PartnerKeys.venueCheck));
    expect(find.text(PartnerMessages.documentBlockedTitle), findsOneWidget);
    expect(find.textContaining('Ninja Escape Room Ltda.'), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueSubmitAnyway), findsNothing);
    expect(find.byKey(PartnerKeys.venueClaim), findsOneWidget);
    expect(find.textContaining('41988887777'), findsNothing);
  });

  testWidgets('o admin vê a pendente ao lado da parecida e mescla', (
    tester,
  ) async {
    await pumpParceiro(tester, size: const Size(1440, 900));
    await _tap(tester, find.byKey(PartnerKeys.partnerAdminDemo));
    expect(find.text(PartnerMessages.adminQueue), findsWidgets);
    expect(find.byKey(PartnerKeys.venuePending), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueSimilar), findsOneWidget);
    expect(find.text('Ninja Centro'), findsOneWidget);
    expect(find.text('Ninja Escape Room Ltda.'), findsWidgets);
    expect(
      find.text('A casa nova é a mesma. O documento é o da filial.'),
      findsOneWidget,
    );
    expect(find.textContaining('41988887777'), findsNothing);
    expect(find.textContaining('12345678000195'), findsNothing);
    expect(find.textContaining('12.345.678/0001-95'), findsNothing);
    expect(find.textContaining('99.888.777/0001-66'), findsOneWidget);

    await _tap(tester, find.byKey(PartnerKeys.venueMerge));
    expect(find.text(PartnerMessages.noPendingVenues), findsOneWidget);
    expect(find.text('Ninja Centro'), findsNothing);
  });

  test('o admin de exemplo não é a casa de demonstração', () {
    expect(
      matchPartnerLogin(
        partnerAdminAccount.email,
        partnerDemoPassword,
      )?.isAdmin,
      isTrue,
    );
    expect(
      matchPartnerLogin(partnerDemoAccount.email, partnerDemoPassword)?.isAdmin,
      isFalse,
    );
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  final scrollable = find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axis == Axis.vertical,
  );
  if (scrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable.last);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
