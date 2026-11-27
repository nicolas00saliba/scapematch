import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_pending_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_switcher.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_referral_code.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _curitiba = PartnerVenueOption(
  id: 'cwb',
  name: 'Casa Curitiba',
  status: 'approved',
);
const _cascavel = PartnerVenueOption(
  id: 'cvel',
  name: 'Casa Cascavel',
  status: 'pending',
);
const _recusada = PartnerVenueOption(
  id: 'old',
  name: 'Casa Antiga',
  status: 'rejected',
);

void main() {
  group('pickPartnerVenue', () {
    test('sem unidade, nada abre', () {
      expect(pickPartnerVenue(const []), isNull);
    });

    test('a segunda unidade em análise não tranca a aprovada', () {
      // Mais nova primeiro: Cascavel acabou de ser enviada.
      final venue = pickPartnerVenue(const [_cascavel, _curitiba]);
      expect(venue?.id, 'cwb');
    });

    test('a unidade escolhida antes vence, mesmo em análise', () {
      final venue = pickPartnerVenue(const [
        _cascavel,
        _curitiba,
      ], preferredId: 'cvel');
      expect(venue?.id, 'cvel');
    });

    test('escolha que não é mais do login é ignorada', () {
      final venue = pickPartnerVenue(const [
        _cascavel,
        _curitiba,
      ], preferredId: 'de-outro-dono');
      expect(venue?.id, 'cwb');
    });

    test('sem aprovada, abre a em análise antes da recusada', () {
      expect(pickPartnerVenue(const [_recusada, _cascavel])?.id, 'cvel');
      expect(pickPartnerVenue(const [_recusada])?.id, 'old');
    });
  });

  test('o rótulo marca só quem não está aprovada', () {
    expect(partnerVenueStatusLabel('approved'), isNull);
    expect(partnerVenueStatusLabel('pending'), 'em análise');
    expect(partnerVenueStatusLabel('rejected'), 'recusada');
  });

  test('openVenue troca a unidade e mantém a lista', () {
    const account = PartnerAccount(
      email: 'dono@exemplo.invalid',
      houseId: 'cwb',
      houseName: 'Casa Curitiba',
      userId: 'u1',
      venues: [_cascavel, _curitiba],
    );
    expect(account.otherVenues.map((v) => v.id), ['cvel']);
    final opened = account.openVenue(_cascavel);
    expect(opened.houseId, 'cvel');
    expect(opened.houseName, 'Casa Cascavel');
    expect(opened.venueStatus, 'pending');
    expect(opened.hasApprovedHouse, isFalse);
    expect(opened.venues, account.venues);
    expect(opened.otherVenues.map((v) => v.id), ['cwb']);
  });

  group('loadVenueReferralCode', () {
    test('pede o código da unidade aberta', () async {
      final calls = <Map<String, Object?>?>[];
      final code = await loadVenueReferralCode(
        'cvel',
        rpc: (fn, params) async {
          calls.add(params);
          return 'CASCAVEL';
        },
      );
      expect(code, 'CASCAVEL');
      expect(calls, [
        {'p_venue_id': 'cvel'},
      ]);
    });

    test('sem o RPC novo no banco, cai no antigo', () async {
      final calls = <Map<String, Object?>?>[];
      final code = await loadVenueReferralCode(
        'cvel',
        rpc: (fn, params) async {
          calls.add(params);
          if (params != null) throw StateError('function not found');
          return 'ANTIGO';
        },
      );
      expect(code, 'ANTIGO');
      expect(calls, [
        {'p_venue_id': 'cvel'},
        null,
      ]);
    });
  });

  group('telas', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('o seletor lista as unidades e troca a aberta', (tester) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_TwoUnits.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: PartnerVenueSwitcher())),
          ),
        ),
      );
      await tester.tap(find.byKey(PartnerKeys.partnerVenueSwitcher));
      await tester.pumpAndSettle();
      expect(find.text('Casa Curitiba'), findsOneWidget);
      expect(find.text('Casa Cascavel (em análise)'), findsOneWidget);
      expect(find.text(PartnerMessages.addUnit), findsOneWidget);

      await tester.tap(find.text('Casa Cascavel (em análise)'));
      await tester.pumpAndSettle();
      final session = container.read(partnerSessionProvider)!;
      expect(session.houseId, 'cvel');
      expect(session.venueStatus, 'pending');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('parceiro.unidade_aberta.u1'), 'cvel');
    });

    testWidgets('em análise, a tela oferece abrir a outra unidade', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_PendingUnit.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PartnerPendingScreen(rejected: false)),
        ),
      );
      expect(find.text(PartnerMessages.otherUnitsTitle), findsOneWidget);
      await tester.tap(find.text(PartnerMessages.openUnit('Casa Curitiba')));
      await tester.pumpAndSettle();
      expect(container.read(partnerSessionProvider)!.houseId, 'cwb');
    });

    testWidgets('uma unidade só não mostra outras unidades na espera', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_OnlyPending.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PartnerPendingScreen(rejected: false)),
        ),
      );
      expect(find.text(PartnerMessages.otherUnitsTitle), findsNothing);
    });
  });
}

class _TwoUnits extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'cwb',
    houseName: 'Casa Curitiba',
    userId: 'u1',
    venues: [_cascavel, _curitiba],
  );
}

class _PendingUnit extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'cvel',
    houseName: 'Casa Cascavel',
    userId: 'u1',
    venueStatus: 'pending',
    venues: [_cascavel, _curitiba],
  );
}

class _OnlyPending extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'cvel',
    houseName: 'Casa Cascavel',
    userId: 'u1',
    venueStatus: 'pending',
    venues: [_cascavel],
  );
}
