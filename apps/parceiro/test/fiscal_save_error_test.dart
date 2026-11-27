import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/data/fiscal_save_error.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

const _curitiba = PartnerVenueOption(
  id: 'v-cwb',
  name: 'Minos Curitiba',
  status: 'approved',
  cityId: 'curitiba',
  cityName: 'Curitiba (PR)',
);
const _arapoti = PartnerVenueOption(
  id: 'v-ara',
  name: 'Minos Arapoti',
  status: 'approved',
  cityId: 'arapoti-pr',
  cityName: 'Arapoti (PR)',
);

void main() {
  test('cidade que usa a conta de outra: diz onde configurar a nota', () {
    final failure = fiscalSaveFailure(
      const FunctionException(
        status: 409,
        details: {
          'error': 'pagbank_account_shared',
          'fiscal_venue_id': 'v-cwb',
          'message': 'texto do servidor',
        },
      ),
      const [_arapoti, _curitiba],
    );
    expect(failure.fiscalVenue?.id, 'v-cwb');
    expect(
      failure.message,
      'Esta cidade recebe pela conta PagBank de Minos Curitiba, em Curitiba '
      '(PR), e a nota sai pelo CNPJ dessa conta. Configure a nota fiscal em '
      'Minos Curitiba, em Curitiba (PR).',
    );
  });

  test('detalhe em texto JSON também vale', () {
    final failure = fiscalSaveFailure(
      const FunctionException(
        status: 409,
        details: '{"error":"pagbank_account_shared","fiscal_venue_id":"v-cwb"}',
      ),
      const [_curitiba],
    );
    expect(failure.fiscalVenue?.id, 'v-cwb');
  });

  test(
    'cidade dona da conta fora do login: mensagem geral da conta da casa',
    () {
      final failure = fiscalSaveFailure(
        const FunctionException(
          status: 409,
          details: {
            'error': 'pagbank_account_shared',
            'fiscal_venue_id': 'v-outra',
          },
        ),
        const [_arapoti],
      );
      expect(failure.fiscalVenue, isNull);
      expect(failure.message, fiscalSharedFallbackMessage);
    },
  );

  test('outros erros seguem com a mensagem genérica', () {
    expect(
      fiscalSaveFailure(
        const FunctionException(status: 500, details: {'error': 'x'}),
        const [_curitiba],
      ).message,
      fiscalSaveFailedMessage,
    );
    expect(
      fiscalSaveFailure(
        const FunctionException(status: 409, details: {'error': 'outro'}),
        const [_curitiba],
      ).message,
      fiscalSaveFailedMessage,
    );
    expect(
      fiscalSaveFailure(StateError('rede'), const [_curitiba]).message,
      fiscalSaveFailedMessage,
    );
  });

  test('rótulo sem parênteses duplos: a cidade já traz a UF', () {
    final label = fiscalVenueLabel(_curitiba);
    expect(label, 'Minos Curitiba, em Curitiba (PR)');
    expect(label.contains(') ('), isFalse);
  });

  test('Abrir a cidade dona da conta leva às Notas fiscais dela', () async {
    final container = ProviderContainer(
      overrides: [partnerSessionProvider.overrideWith(_TwoCities.new)],
    );
    addTearDown(container.dispose);
    container.read(partnerSessionProvider);
    container
        .read(partnerSectionProvider.notifier)
        .select(PartnerSection.invoices);
    await container
        .read(partnerSessionProvider.notifier)
        .openVenue('v-cwb', section: PartnerSection.invoices);
    expect(container.read(partnerSessionProvider)?.houseId, 'v-cwb');
    expect(container.read(partnerSectionProvider), PartnerSection.invoices);
  });

  test('trocar de cidade sem pedir seção continua abrindo o Saldo', () async {
    final container = ProviderContainer(
      overrides: [partnerSessionProvider.overrideWith(_TwoCities.new)],
    );
    addTearDown(container.dispose);
    container.read(partnerSessionProvider);
    container
        .read(partnerSectionProvider.notifier)
        .select(PartnerSection.invoices);
    await container.read(partnerSessionProvider.notifier).openVenue('v-cwb');
    expect(container.read(partnerSectionProvider), PartnerSection.balance);
  });

  test('rótulo sem cidade usa só o nome', () {
    expect(
      fiscalVenueLabel(
        const PartnerVenueOption(id: 'a', name: 'Minos', status: 'approved'),
      ),
      'Minos',
    );
  });
}

class _TwoCities extends PartnerSessionController {
  @override
  PartnerAccount? build() => const PartnerAccount(
    email: 'dono@exemplo.invalid',
    houseId: 'v-ara',
    houseName: 'Minos Arapoti',
    venues: [_arapoti, _curitiba],
  );
}
