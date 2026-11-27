import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_share_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_units_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/presentation/pagbank_share_offer.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_units_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _curitiba = PartnerVenueOption(
  id: 'cwb',
  name: 'Minos Curitiba',
  status: 'approved',
  cityId: 'curitiba',
  cityName: 'Curitiba (PR)',
);
const _cascavel = PartnerVenueOption(
  id: 'cvel',
  name: 'Minos Cascavel',
  status: 'pending',
  cityId: 'cascavel-pr',
  cityName: 'Cascavel (PR)',
);

void main() {
  group('conta PagBank da outra cidade', () {
    test('lê as cidades que podem emprestar a conta', () async {
      final calls = <String>[];
      final repo = PagbankShareRepository(
        rpc: (fn, params) async {
          calls.add('$fn:${params['p_venue_id']}');
          return [
            {
              'venue_id': 'cwb',
              'venue_name': 'Minos Curitiba',
              'city_name': 'Curitiba (PR)',
              'account_last4': '4321',
            },
            {'sem': 'id'},
          ];
        },
      );
      final sources = await repo.sources('cvel');
      expect(calls, ['my_pagbank_share_sources:cvel']);
      expect(sources, hasLength(1));
      expect(
        PagbankShareMessages.button(sources.single),
        'Receber pela conta de Curitiba (PR) (Minos Curitiba) (final 4321)',
      );
    });

    test('erro na leitura esconde a oferta', () async {
      final repo = PagbankShareRepository(
        rpc: (fn, params) async =>
            throw const PostgrestException(message: 'x', code: 'PGRST202'),
      );
      expect(await repo.sources('cvel'), isEmpty);
    });

    test('recusas do servidor viram frase clara', () async {
      Future<String?> shareWith(String message) => PagbankShareRepository(
        rpc: (fn, params) async =>
            throw PostgrestException(message: message, code: 'PB409'),
      ).share('cvel', 'cwb');
      expect(
        await shareWith('pagbank_account_exists'),
        PagbankShareMessages.exists,
      );
      expect(
        await shareWith('pagbank_share_invalid'),
        PagbankShareMessages.invalid,
      );
      expect(
        await shareWith('pagbank_account_in_use'),
        PagbankShareMessages.inUse,
      );
      expect(await shareWith('outra'), PagbankShareMessages.failed);
    });

    test('a conta mostra de qual cidade veio', () {
      final shared = PagbankAccountView.fromJson({
        'connected': true,
        'shared': true,
        'shared_from': 'Minos Curitiba',
      });
      expect(shared.sharedFrom, 'Minos Curitiba');
      final own = PagbankAccountView.fromJson({'connected': true});
      expect(own.sharedFrom, isNull);
    });

    testWidgets('a oferta pede confirmação antes de ligar a conta', (
      tester,
    ) async {
      final calls = <String>[];
      var shared = 0;
      final repo = PagbankShareRepository(
        rpc: (fn, params) async {
          calls.add(fn);
          if (fn == 'my_pagbank_share_sources') {
            return [
              {
                'venue_id': 'cwb',
                'venue_name': 'Minos Curitiba',
                'city_name': 'Curitiba (PR)',
                'account_last4': '4321',
              },
            ];
          }
          expect(params, {'p_venue_id': 'cvel', 'p_source_venue_id': 'cwb'});
          return {'ok': true};
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pagbankShareRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: PagbankShareOffer(
                venueId: 'cvel',
                onShared: () => shared++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(PartnerKeys.pagbankShareOffer), findsOneWidget);

      await tester.tap(find.byKey(PartnerKeys.pagbankShareUse('cwb')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(PagbankShareMessages.cancel));
      await tester.pumpAndSettle();
      expect(calls, ['my_pagbank_share_sources']);

      await tester.tap(find.byKey(PartnerKeys.pagbankShareUse('cwb')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PartnerKeys.pagbankShareConfirm));
      await tester.pumpAndSettle();
      expect(calls.last, 'share_venue_pagbank_account');
      expect(shared, 1);
      expect(find.text(PagbankShareMessages.done), findsOneWidget);
      expect(find.byKey(PartnerKeys.pagbankShareOffer), findsNothing);
    });

    testWidgets('sem outra cidade com conta, não aparece nada', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pagbankShareRepositoryProvider.overrideWithValue(
              PagbankShareRepository(rpc: (fn, params) async => const []),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PagbankShareOffer(venueId: 'cvel', onShared: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(PartnerKeys.pagbankShareOffer), findsNothing);
    });
  });

  group('mesmo CNPJ em várias cidades do mesmo dono', () {
    test('cadastrar outra cidade com o mesmo documento passa', () {
      expect(
        ownDocumentSignupError(VenueClaimPath.alreadyOwner, addingUnit: true),
        isNull,
      );
    });

    test('casa nova com documento que já é do login continua barrada', () {
      expect(
        ownDocumentSignupError(VenueClaimPath.alreadyOwner, addingUnit: false),
        'Esta casa já está na sua conta.',
      );
      expect(
        ownDocumentSignupError(VenueClaimPath.none, addingUnit: false),
        isNull,
      );
    });

    test('documento de outro dono tem frase própria', () {
      expect(sameDocumentUnitError, contains('outra casa'));
    });
  });

  group('reativar cidade', () {
    test('recusas do servidor viram frase clara', () {
      expect(
        partnerUnitReactivationError('42501', 'not owner'),
        PartnerUnitMessages.notOwner,
      );
      expect(
        partnerUnitReactivationError('PGRST202', 'x'),
        PartnerUnitMessages.reactivateUnavailable,
      );
      expect(
        partnerUnitReactivationError('23505', 'duplicate document'),
        PartnerUnitMessages.documentTaken,
      );
      expect(
        partnerUnitReactivationError('P0001', 'unit_removed_by_admin'),
        PartnerUnitMessages.removedByAdmin,
      );
      expect(
        partnerUnitReactivationError('P0001', 'unit_reactivate_support'),
        PartnerUnitMessages.reactivateSupport,
      );
      expect(
        partnerUnitReactivationError(null, 'x'),
        PartnerUnitMessages.reactivateFailed,
      );
    });

    testWidgets('cidade removida aparece à parte e reativa com confirmação', (
      tester,
    ) async {
      final calls = <String>[];
      final container = ProviderContainer(
        overrides: [
          partnerSessionProvider.overrideWith(_OneRemoved.new),
          partnerUnitsRepositoryProvider.overrideWithValue(
            PartnerUnitsRepository(
              rpc: (fn, params) async {
                calls.add('$fn:${params['p_venue_id']}');
                return {'ok': true, 'status': 'pending'};
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
      expect(find.text(PartnerUnitMessages.removedTitle), findsOneWidget);
      expect(find.text('Cascavel (PR)'), findsOneWidget);
      // Cidade removida não tem botão de remover de novo.
      expect(find.byKey(PartnerKeys.partnerRemoveUnit('cvel')), findsNothing);

      await tester.tap(find.byKey(PartnerKeys.partnerReactivateUnit('cvel')));
      await tester.pumpAndSettle();
      expect(
        find.text(PartnerUnitMessages.reactivateConfirmTitle),
        findsOneWidget,
      );
      await tester.tap(find.byKey(PartnerKeys.partnerConfirmReactivateUnit));
      await tester.pumpAndSettle();
      expect(calls, ['reactivate_my_unit:cvel']);
      expect(find.text(PartnerUnitMessages.reactivated), findsOneWidget);
    });

    test('a conta guarda as removidas ao trocar de cidade', () {
      const account = PartnerAccount(
        email: 'dono@exemplo.invalid',
        houseId: 'cwb',
        houseName: 'Minos Curitiba',
        venues: [_curitiba],
        removedVenues: [_cascavel],
      );
      expect(account.openVenue(_curitiba).removedVenues, [_cascavel]);
    });
  });
}

class _OneRemoved extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'cwb',
    houseName: 'Minos Curitiba',
    userId: 'u1',
    venues: [_curitiba],
    removedVenues: [_cascavel],
  );
}
