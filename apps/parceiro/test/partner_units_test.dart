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
import 'package:scapematch_parceiro/features/partner/data/partner_units_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_units_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _curitiba = PartnerVenueOption(
  id: 'cwb',
  name: 'Casa Curitiba',
  status: 'approved',
  cityId: 'curitiba',
  cityName: 'Curitiba (PR)',
);
const _cascavel = PartnerVenueOption(
  id: 'cvel',
  name: 'Casa Cascavel',
  status: 'pending',
  cityId: 'cascavel-pr',
  cityName: 'Cascavel (PR)',
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

    test('RPC novo fora do banco (PGRST202) cai no antigo', () async {
      final calls = <Map<String, Object?>?>[];
      final code = await loadVenueReferralCode(
        'cvel',
        singleUnit: false,
        rpc: (fn, params) async {
          calls.add(params);
          if (params != null) {
            throw const PostgrestException(
              message: 'Could not find the function',
              code: 'PGRST202',
            );
          }
          return 'ANTIGO';
        },
      );
      expect(code, 'ANTIGO');
      expect(calls, [
        {'p_venue_id': 'cvel'},
        null,
      ]);
    });

    test('com várias unidades, outro erro não mostra código alheio', () async {
      final calls = <Map<String, Object?>?>[];
      Future<Object?> rpc(String fn, Map<String, Object?>? params) async {
        calls.add(params);
        if (params != null) {
          throw const PostgrestException(message: 'timeout', code: '57014');
        }
        return 'DA_MAIS_NOVA';
      }

      await expectLater(
        loadVenueReferralCode('cvel', singleUnit: false, rpc: rpc),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        loadVenueReferralCode(
          'cvel',
          singleUnit: false,
          rpc: (fn, params) async {
            calls.add(params);
            if (params != null) throw StateError('rede');
            return 'DA_MAIS_NOVA';
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls.where((params) => params == null), isEmpty);
    });

    test('com uma unidade só, qualquer erro cai no antigo', () async {
      final code = await loadVenueReferralCode(
        'cwb',
        rpc: (fn, params) async {
          if (params != null) {
            throw const PostgrestException(message: 'timeout', code: '57014');
          }
          return 'UNICA';
        },
      );
      expect(code, 'UNICA');
    });
  });

  group('várias cidades no cadastro', () {
    test('a cidade extra não repete nem duplica a principal', () {
      var cities = addUnitCity(const [], 'curitiba', 'cascavel-pr');
      cities = addUnitCity(cities, 'curitiba', 'cascavel-pr');
      cities = addUnitCity(cities, 'curitiba', 'curitiba');
      cities = addUnitCity(cities, 'curitiba', '');
      cities = addUnitCity(cities, 'curitiba', 'londrina-pr');
      expect(cities, ['cascavel-pr', 'londrina-pr']);
      expect(remainingUnitCities(cities, 'cascavel-pr'), ['londrina-pr']);
      expect(remainingUnitCities(cities, 'curitiba'), cities);
    });

    test('a próxima cidade repete a casa e zera o endereço', () {
      const draft = VenueDraft(
        name: 'Casa',
        cityId: 'curitiba',
        neighborhood: 'Centro',
        street: 'Rua A',
        number: '10',
        postalCode: '80000000',
        phone: '41999990000',
        documentKind: 'cnpj',
        documentNumber: '27180000000101',
        category: 'escape-room',
        incomeReais: '5000',
        companyType: 'MEI',
        inviteCode: 'convite',
        referralCode: 'IND',
      );
      final next = draft.forNextCity('cascavel-pr');
      expect(next.cityId, 'cascavel-pr');
      expect(next.name, 'Casa');
      expect(next.documentNumber, draft.documentNumber);
      expect(next.companyType, 'MEI');
      expect(next.phone, draft.phone);
      expect(next.neighborhood, isEmpty);
      expect(next.street, isEmpty);
      expect(next.number, isEmpty);
      expect(next.postalCode, isEmpty);
      expect(next.inviteCode, isEmpty);
      expect(next.referralCode, isEmpty);
    });

    test('abas em ordem de cadastro, com a cidade no rótulo', () {
      final tabs = partnerCityTabOrder(const [_cascavel, _curitiba]);
      expect(tabs.map((v) => v.id), ['cwb', 'cvel']);
      expect(partnerCityTabLabel(_curitiba), 'Curitiba (PR)');
      expect(partnerCityTabLabel(_cascavel), 'Cascavel (PR) (em análise)');
    });
  });

  group('remover unidade', () {
    test('cada recusa do servidor vira uma frase', () {
      expect(
        partnerUnitRemovalError('P0001', 'unit_last'),
        PartnerUnitMessages.last,
      );
      expect(
        partnerUnitRemovalError('P0001', 'unit_future_groups'),
        PartnerUnitMessages.futureGroups,
      );
      expect(
        partnerUnitRemovalError('P0001', 'unit_pending_money'),
        PartnerUnitMessages.pendingMoney,
      );
      expect(
        partnerUnitRemovalError('42501', 'not owner'),
        PartnerUnitMessages.notOwner,
      );
      expect(
        partnerUnitRemovalError('PGRST202', 'missing'),
        PartnerUnitMessages.unavailable,
      );
      expect(partnerUnitRemovalError('XX000', 'x'), PartnerUnitMessages.failed);
    });

    test('o repositório chama o RPC com a unidade', () async {
      final calls = <Map<String, Object?>>[];
      final repo = PartnerUnitsRepository(
        rpc: (fn, params) async {
          expect(fn, 'deactivate_my_unit');
          calls.add(params);
          return {'ok': true};
        },
      );
      expect(await repo.deactivate('cvel'), isNull);
      expect(calls, [
        {'p_venue_id': 'cvel'},
      ]);
      final refused = PartnerUnitsRepository(
        rpc: (fn, params) async => throw const PostgrestException(
          message: 'unit_future_groups',
          code: 'P0001',
        ),
      );
      expect(
        await refused.deactivate('cvel'),
        PartnerUnitMessages.futureGroups,
      );
    });
  });

  group('telas', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('uma aba por cidade troca a unidade aberta', (tester) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_TwoUnits.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PartnerCityTabs())),
        ),
      );
      expect(find.text('Curitiba (PR)'), findsOneWidget);
      expect(find.text('Cascavel (PR) (em análise)'), findsOneWidget);
      expect(find.byKey(PartnerKeys.partnerAddCityTab), findsOneWidget);
      await tester.tap(find.byKey(PartnerKeys.partnerCityTab('cvel')));
      await tester.pumpAndSettle();
      expect(container.read(partnerSessionProvider)!.houseId, 'cvel');
    });

    testWidgets('com uma cidade só, a barra só aparece no app real', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_OnlyPending.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  PartnerCityTabs(),
                  PartnerCityTabs(key: Key('real'), showWhenSingle: true),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(PartnerKeys.partnerAddCityTab), findsOneWidget);
    });

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
      expect(find.text(PartnerMessages.manageUnits), findsOneWidget);

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

    testWidgets('remover pede confirmação e mostra a recusa', (tester) async {
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          partnerSessionProvider.overrideWith(_TwoUnits.new),
          partnerUnitsRepositoryProvider.overrideWithValue(
            PartnerUnitsRepository(
              rpc: (fn, params) async {
                calls.add(params['p_venue_id']! as String);
                throw const PostgrestException(
                  message: 'unit_pending_money',
                  code: 'P0001',
                );
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PartnerUnitsScreen()),
        ),
      );
      expect(find.text('Curitiba (PR)'), findsOneWidget);
      expect(find.text('Casa Cascavel · em análise'), findsOneWidget);

      await tester.tap(find.byKey(PartnerKeys.partnerRemoveUnit('cvel')));
      await tester.pumpAndSettle();
      expect(
        find.text(PartnerMessages.removeUnitTitle('Casa Cascavel')),
        findsOneWidget,
      );
      // Cancelar não chama o servidor.
      await tester.tap(find.text(PartnerMessages.cancel));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.byKey(PartnerKeys.partnerRemoveUnit('cvel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PartnerKeys.partnerConfirmRemoveUnit));
      await tester.pumpAndSettle();
      expect(calls, ['cvel']);
      expect(find.text(PartnerUnitMessages.pendingMoney), findsOneWidget);
      expect(container.read(partnerSessionProvider)!.venues.length, 2);
    });

    testWidgets('com uma unidade só não há botão de remover', (tester) async {
      final container = ProviderContainer(
        overrides: [partnerSessionProvider.overrideWith(_OnlyPending.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PartnerUnitsScreen()),
        ),
      );
      expect(find.byKey(PartnerKeys.partnerRemoveUnit('cvel')), findsNothing);
      expect(find.text(PartnerMessages.unitsSingleHint), findsOneWidget);
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
