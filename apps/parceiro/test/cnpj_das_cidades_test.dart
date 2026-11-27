import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/scape_points/data/reward_rules_store.dart';
import 'package:scapematch/features/scape_points/presentation/reward_rules_controller.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_account_loader.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const _draft = VenueDraft(
  name: 'Minos',
  cityId: 'curitiba',
  neighborhood: 'Centro',
  street: 'Rua A',
  number: '1',
  postalCode: '80000000',
  phone: '41999990000',
  documentKind: 'cnpj',
  documentNumber: '11222333000181',
  category: 'escape-room',
  incomeReais: '5000',
);

void main() {
  test('mesmo CNPJ repete o documento na próxima cidade; próprio, não', () {
    expect(_draft.forNextCity('cascavel-pr').documentNumber, '11222333000181');
    final own = _draft.forNextCity('cascavel-pr', keepDocument: false);
    expect(own.documentNumber, isEmpty);
    expect(own.name, 'Minos');
    expect(own.street, isEmpty);
  });

  test('lê os dados da casa para cadastrar outra cidade', () {
    final template = unitTemplateFrom({
      'name': 'Minos',
      'phone': '41999990000',
      'document_kind': 'cnpj',
      'document_number': '11222333000181',
      'company_type': 'MEI',
      'category': 'escape-room',
      'income_value': 5000,
    });
    expect(template?.documentNumber, '11222333000181');
    expect(template?.incomeReais, '5000');
    expect(template?.companyType, 'MEI');
    expect(unitTemplateFrom(null), isNull);
  });

  testWidgets('outra cidade: mesmo CNPJ trava o documento; próprio libera', (
    tester,
  ) async {
    final database = buildSampleDatabase(now: DateTime(2026, 11, 27, 15));
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final asked = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [
          clockProvider.overrideWithValue(
            FixedClock(DateTime(2026, 11, 27, 15)),
          ),
          cityRepositoryProvider.overrideWithValue(
            FakeCityRepository(database, latency: Duration.zero),
          ),
          partnerSessionProvider.overrideWith(_OpenSession.new),
          rewardRulesStoreProvider.overrideWithValue(
            RewardRulesStore(current: const PublicRewardRules()),
          ),
        ],
        child: MaterialApp(
          home: PartnerVenueScreen(
            addingUnit: true,
            loadTemplate: (id) async {
              asked.add(id);
              return _draft;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, ['cwb']);
    expect(find.byKey(PartnerKeys.partnerDocumentChoice), findsOneWidget);
    TextField document() =>
        tester.widget<TextField>(find.byKey(PartnerKeys.partnerVenueDocument));
    expect(document().controller!.text, '11222333000181');
    expect(document().readOnly, isTrue);
    expect(find.text(PartnerMessages.documentChoiceSameHint), findsOneWidget);

    await tester.tap(find.text(PartnerMessages.documentChoiceOwn));
    await tester.pumpAndSettle();
    expect(document().controller!.text, isEmpty);
    expect(document().readOnly, isFalse);
    expect(find.text(PartnerMessages.documentChoiceOwnHint), findsOneWidget);

    await tester.tap(find.text(PartnerMessages.documentChoiceSame));
    await tester.pumpAndSettle();
    expect(document().controller!.text, '11222333000181');
  });
}

class _OpenSession extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'cwb',
    houseName: 'Minos',
    userId: 'u1',
  );
}
