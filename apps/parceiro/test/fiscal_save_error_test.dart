import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/data/fiscal_save_error.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
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
      'Esta cidade recebe pela conta PagBank de Curitiba (PR) (Minos Curitiba), '
      'e a nota sai pelo CNPJ dessa conta. Configure a nota fiscal em '
      'Curitiba (PR) (Minos Curitiba).',
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

  test('rótulo sem cidade usa só o nome', () {
    expect(
      fiscalVenueLabel(
        const PartnerVenueOption(id: 'a', name: 'Minos', status: 'approved'),
      ),
      'Minos',
    );
  });
}
