import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:scapematch_parceiro/features/partner/data/venue_claim_client.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

/// Colunas que o authenticated pode ler. Documento, telefone e renda ficam
/// em `venue_private`.
const partnerVenueColumns =
    'id, owner_id, city_id, name, neighborhood, street_address, '
    'address_number, postal_code, latitude, longitude, document_kind, '
    'category, badge, invite_id, status, reviewed_by, reviewed_at, created_at, '
    'receives_payments';

/// Chave da unidade aberta por último, por login, só neste aparelho.
String partnerVenuePreferenceKey(String userId) =>
    'parceiro.unidade_aberta.$userId';

Future<String?> readPartnerVenuePreference(String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(partnerVenuePreferenceKey(userId));
  } on Object {
    return null;
  }
}

Future<void> savePartnerVenuePreference(String userId, String venueId) async {
  if (userId.isEmpty || venueId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(partnerVenuePreferenceKey(userId), venueId);
  } on Object {
    // Sem preferência salva, o painel abre a mais nova aprovada.
  }
}

const _unitColumns = 'id, name, status, city_id, created_at';

/// Unidades ativas do login, da mais nova para a mais antiga, com a cidade.
///
/// Unidade desativada pelo dono (`deactivated_at`) fica de fora. Sem a
/// migration da coluna no banco (42703), lê sem ela: nada está desativado.
Future<List<PartnerVenueOption>> _ownerUnits(String userId) async {
  List<Map<String, dynamic>> rows;
  try {
    rows = await scapeSupabase
        .from('venues')
        .select('$_unitColumns, deactivated_at')
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
  } on PostgrestException catch (error) {
    if (error.code != '42703') rethrow;
    rows = await scapeSupabase
        .from('venues')
        .select(_unitColumns)
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
  }
  final active = [
    for (final row in rows)
      if (row['deactivated_at'] == null) row,
  ];
  final cityIds = {
    for (final row in active)
      if (row['city_id'] is String) row['city_id'] as String,
  };
  final cityNames = <String, String>{};
  if (cityIds.isNotEmpty) {
    try {
      final cities = await scapeSupabase
          .from('cities')
          .select('id, name, state_code')
          .inFilter('id', cityIds.toList());
      for (final city in cities) {
        final state = city['state_code'] as String?;
        final name = city['name'] as String;
        cityNames[city['id'] as String] = state == null || state.isEmpty
            ? name
            : '$name ($state)';
      }
    } on Object {
      // Sem o nome da cidade, a lista mostra só o nome da unidade.
    }
  }
  return [
    for (final row in active)
      PartnerVenueOption(
        id: row['id'] as String,
        name: row['name'] as String,
        status: row['status'] as String?,
        cityId: row['city_id'] as String?,
        cityName: cityNames[row['city_id']],
      ),
  ];
}

/// Lê todas as unidades do login e abre uma.
///
/// [preferVenueId] vence a escolha salva no aparelho. Sem nenhuma das duas,
/// vale [pickPartnerVenue].
Future<PartnerAccount?> loadPartnerAccount({String? preferVenueId}) async {
  final user = scapeSupabase.auth.currentUser;
  if (user == null) return null;
  final admin = await scapeSupabase
      .from('admins')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle();
  final venues = await _ownerUnits(user.id);
  final preferred = preferVenueId ?? await readPartnerVenuePreference(user.id);
  final venue = pickPartnerVenue(venues, preferredId: preferred);
  if (venue == null) {
    return PartnerAccount(
      email: user.email ?? '',
      houseId: '',
      houseName: '',
      userId: user.id,
      venueStatus: null,
      isAdmin: admin != null,
    );
  }
  return PartnerAccount(
    email: user.email ?? '',
    houseId: venue.id,
    houseName: venue.name,
    userId: user.id,
    venueStatus: venue.status,
    isAdmin: admin != null,
    venues: venues,
  );
}

/// Resultado do cadastro real. Aviso de duplicata não grava até a confirmação.
class VenueSignupResult {
  const VenueSignupResult({
    this.error,
    this.warnings = const [],
    this.duplicateOf,
    this.claim,
    this.venueId,
  });

  final String? error;
  final List<String> warnings;
  final String? duplicateOf;
  final ClaimableVenue? claim;

  /// Id da unidade gravada, quando o cadastro entrou.
  final String? venueId;

  bool get saved => error == null && warnings.isEmpty && claim == null;
}

/// Lê `check_venue_duplicates` e, se puder, grava a casa como pending.
///
/// Documento repetido não entra. Endereço ou nome parecido só avisa e,
/// confirmado, grava `possible_duplicate_of`. O aceite vai para
/// `terms_acceptances` pela função `accept_terms`.
Future<VenueSignupResult> submitVenue(
  VenueDraft draft, {
  required bool acceptedTerms,
  bool confirmDuplicate = false,
}) async {
  if (!acceptedTerms) {
    return const VenueSignupResult(
      error: 'Aceite os termos do Parceiro, a privacidade e a política de cancelamento para cadastrar a casa.',
    );
  }
  final error = draft.validate();
  if (error != null) return VenueSignupResult(error: error);
  var claim = const ClaimableVenue(path: VenueClaimPath.none);
  try {
    claim = await const VenueClaimClient().lookup(draft.documentNumber);
  } on Object {
    claim = const ClaimableVenue(path: VenueClaimPath.none);
  }
  if (claim.offersClaim) return VenueSignupResult(claim: claim);
  if (claim.path == VenueClaimPath.alreadyOwner) {
    return const VenueSignupResult(error: 'Esta casa já está na sua conta.');
  }
  final duplicates = await _venueDuplicates(draft);
  if (duplicates.error != null) {
    return VenueSignupResult(error: duplicates.error);
  }
  if (duplicates.blocked) {
    return VenueSignupResult(error: duplicates.blockedMessage);
  }
  if (duplicates.warnings.isNotEmpty && !confirmDuplicate) {
    return VenueSignupResult(
      warnings: duplicates.warnings,
      duplicateOf: duplicates.duplicateOf,
    );
  }
  final city = await scapeSupabase
      .from('cities')
      .select('id, latitude, longitude')
      .eq('id', draft.cityId)
      .maybeSingle();
  if (city == null) {
    return const VenueSignupResult(error: 'Cidade não encontrada.');
  }
  String? inviteId;
  final code = draft.inviteCode.trim().toLowerCase();
  if (code.isNotEmpty) {
    final invite = await scapeSupabase
        .from('partner_invites')
        .select('id')
        .eq('code', code)
        .eq('active', true)
        .maybeSingle();
    if (invite == null) {
      return const VenueSignupResult(error: 'Convite não encontrado.');
    }
    inviteId = invite['id'] as String;
  }
  final income = double.parse(draft.incomeReais.trim().replaceAll(',', '.'));
  try {
    final inserted = await scapeSupabase
        .from('venues')
        .insert({
          'city_id': draft.cityId,
          'name': draft.name.trim(),
          'neighborhood': draft.neighborhood.trim(),
          'street_address': draft.street.trim(),
          'address_number': draft.number.trim().isEmpty
              ? 'S/N'
              : draft.number.trim(),
          'postal_code': VenueDraft.digits(draft.postalCode),
          'latitude': city['latitude'],
          'longitude': city['longitude'],
          'income_value': income,
          'document_kind': draft.documentKind,
          'document_number': VenueDraft.digits(draft.documentNumber),
          'company_type': draft.documentKind == 'cnpj'
              ? draft.companyType
              : 'LIMITED',
          'phone': VenueDraft.digits(draft.phone),
          'category': draft.category,
          'invite_id': ?inviteId,
          if (duplicates.duplicateOf != null)
            'possible_duplicate_of': duplicates.duplicateOf,
        })
        .select('id')
        .maybeSingle();
    final venueId = inserted?['id'] as String?;
    if (venueId != null) {
      await scapeSupabase.rpc(
        'accept_terms',
        params: {'p_audience': 'partner', 'p_venue_id': venueId},
      );
      final referral = draft.referralCode.trim();
      if (referral.isNotEmpty) {
        try {
          await scapeSupabase.rpc(
            'claim_venue_referral',
            params: {'p_venue_id': venueId, 'p_code': referral},
          );
        } on Object {
          // Código inválido não desfaz a casa. A indicação fica de fora.
        }
      }
    }
    return VenueSignupResult(venueId: venueId);
  } on Object catch (error) {
    final text = error.toString().toLowerCase();
    if (text.contains('unknown invite')) {
      return const VenueSignupResult(error: 'Convite não encontrado.');
    }
    if (text.contains('duplicate document')) {
      return const VenueSignupResult(
        error: 'Documento já cadastrado. Esta casa não foi enviada.',
      );
    }
    if (text.contains('row-level') || text.contains('42501')) {
      return const VenueSignupResult(
        error: 'Entre na conta antes de cadastrar a casa.',
      );
    }
    return const VenueSignupResult(
      error: 'Não foi possível enviar a casa. Confira os dados.',
    );
  }
}

class _DuplicateRead {
  const _DuplicateRead({
    this.error,
    this.blocked = false,
    this.blockedMessage,
    this.warnings = const [],
    this.duplicateOf,
  });

  final String? error;
  final bool blocked;
  final String? blockedMessage;
  final List<String> warnings;
  final String? duplicateOf;
}

Future<_DuplicateRead> _venueDuplicates(VenueDraft draft) async {
  try {
    final raw = await scapeSupabase.rpc(
      'check_venue_duplicates',
      params: {
        'documento': draft.documentNumber,
        'nome': draft.name.trim(),
        'cidade': draft.cityId,
        'cep': draft.postalCode,
        'numero': draft.number,
      },
    );
    if (raw is! List) return const _DuplicateRead();
    final warnings = <String>[];
    String? duplicateOf;
    for (final row in raw) {
      if (row is! Map) continue;
      final conflict = row['conflict'] == true;
      if (!conflict) continue;
      final type = '${row['conflict_type'] ?? ''}';
      final name = '${row['venue_name'] ?? ''}'.trim();
      final venueId = row['venue_id'];
      if (type == 'documento') {
        final who = name.isEmpty ? '' : ' A casa aprovada é $name.';
        return _DuplicateRead(
          blocked: true,
          blockedMessage:
              'Documento já cadastrado.$who Esta casa não foi enviada.',
        );
      }
      final label = type == 'endereço'
          ? 'O endereço coincide com uma casa aprovada'
          : 'O nome parece com uma casa aprovada';
      warnings.add(name.isEmpty ? '$label.' : '$label: $name.');
      if (duplicateOf == null && venueId is String && venueId.isNotEmpty) {
        duplicateOf = venueId;
      }
    }
    return _DuplicateRead(warnings: warnings, duplicateOf: duplicateOf);
  } on Object {
    return const _DuplicateRead(
      error: 'Não foi possível verificar se a casa já existe.',
    );
  }
}

Future<List<Map<String, dynamic>>> listPendingVenues() async {
  final rows = await scapeSupabase
      .from('venues')
      .select(partnerVenueColumns)
      .eq('status', 'pending')
      .order('created_at');
  return [for (final row in rows) Map<String, dynamic>.from(row)];
}

Future<Map<String, dynamic>?> readVenuePrivate(String venueId) async {
  final rows = await scapeSupabase.rpc(
    'venue_private',
    params: {'p_venue_id': venueId},
  );
  if (rows is List && rows.isNotEmpty && rows.first is Map) {
    return Map<String, dynamic>.from(rows.first as Map);
  }
  if (rows is Map) return Map<String, dynamic>.from(rows);
  return null;
}

Future<String?> reviewVenue({
  required String venueId,
  required String status,
}) async {
  final userId = scapeSupabase.auth.currentUser?.id;
  if (userId == null) return 'Entre como admin.';
  final updated = await scapeSupabase
      .from('venues')
      .update({
        'status': status,
        'reviewed_by': userId,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', venueId)
      .select('id');
  if (updated.isEmpty) return 'Não foi possível atualizar a casa.';
  return null;
}
