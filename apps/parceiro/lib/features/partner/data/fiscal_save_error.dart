import 'dart:convert';

import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

const fiscalSaveFailedMessage = 'Não foi possível gravar os dados fiscais.';

const fiscalSharedFallbackMessage =
    'Esta cidade recebe pela conta PagBank de outra cidade da casa, e a nota '
    'sai pelo CNPJ dessa conta. Configure a nota fiscal na cidade dona da conta.';

/// Por que os dados fiscais não foram gravados, e onde gravar.
class FiscalSaveFailure {
  const FiscalSaveFailure(this.message, {this.fiscalVenue});

  final String message;

  /// Cidade da casa onde a nota deve ser configurada (dona da conta PagBank),
  /// quando ela é uma das unidades deste login.
  final PartnerVenueOption? fiscalVenue;
}

/// Lê a recusa de `configure-venue-fiscal`.
///
/// 409 `pagbank_account_shared`: a cidade usa a conta PagBank de outra, e a
/// nota sai pelo CNPJ da conta que recebe. A mensagem diz em qual cidade
/// configurar.
FiscalSaveFailure fiscalSaveFailure(
  Object error,
  List<PartnerVenueOption> venues,
) {
  if (error is! FunctionException || error.status != 409) {
    return const FiscalSaveFailure(fiscalSaveFailedMessage);
  }
  final details = _asMap(error.details);
  if (details == null || details['error'] != 'pagbank_account_shared') {
    return const FiscalSaveFailure(fiscalSaveFailedMessage);
  }
  final id = details['fiscal_venue_id'];
  PartnerVenueOption? venue;
  for (final option in venues) {
    if (option.id == id) venue = option;
  }
  if (venue == null) {
    return const FiscalSaveFailure(fiscalSharedFallbackMessage);
  }
  final label = fiscalVenueLabel(venue);
  return FiscalSaveFailure(
    'Esta cidade recebe pela conta PagBank de $label, e a nota sai pelo CNPJ '
    'dessa conta. Configure a nota fiscal em $label.',
    fiscalVenue: venue,
  );
}

/// "Minos Curitiba, em Curitiba (PR)", ou só o nome se a cidade não vier.
/// O nome da cidade já traz a UF.
String fiscalVenueLabel(PartnerVenueOption venue) {
  final city = venue.cityName?.trim() ?? '';
  return city.isEmpty ? venue.name : '${venue.name}, em $city';
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }
  return null;
}
