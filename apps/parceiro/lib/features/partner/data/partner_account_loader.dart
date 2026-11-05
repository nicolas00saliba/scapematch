import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

/// Colunas que o authenticated pode ler. Documento, telefone e renda ficam
/// em `venue_private`.
const partnerVenueColumns =
    'id, owner_id, city_id, name, neighborhood, street_address, '
    'address_number, postal_code, latitude, longitude, document_kind, '
    'category, badge, invite_id, status, reviewed_by, reviewed_at, created_at, '
    'receives_payments';

Future<PartnerAccount?> loadPartnerAccount() async {
  final user = scapeSupabase.auth.currentUser;
  if (user == null) return null;
  final admin = await scapeSupabase
      .from('admins')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle();
  final venues = await scapeSupabase
      .from('venues')
      .select(partnerVenueColumns)
      .eq('owner_id', user.id)
      .order('created_at', ascending: false);
  if (venues.isEmpty) {
    return PartnerAccount(
      email: user.email ?? '',
      houseId: '',
      houseName: '',
      userId: user.id,
      venueStatus: null,
      isAdmin: admin != null,
    );
  }
  final venue = venues.first;
  return PartnerAccount(
    email: user.email ?? '',
    houseId: venue['id'] as String,
    houseName: venue['name'] as String,
    userId: user.id,
    venueStatus: venue['status'] as String?,
    isAdmin: admin != null,
  );
}

/// Resultado do cadastro real. Aviso de duplicata não grava até a confirmação.
class VenueSignupResult {
  const VenueSignupResult({
    this.error,
    this.warnings = const [],
    this.duplicateOf,
  });

  final String? error;
  final List<String> warnings;
  final String? duplicateOf;

  bool get saved => error == null && warnings.isEmpty;
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
    await scapeSupabase
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
          'phone': VenueDraft.digits(draft.phone),
          'category': draft.category,
          'invite_id': ?inviteId,
          if (duplicates.duplicateOf != null)
            'possible_duplicate_of': duplicates.duplicateOf,
        })
        .select('id');
    final userId = scapeSupabase.auth.currentUser?.id;
    if (userId != null) {
      final created = await scapeSupabase
          .from('venues')
          .select('id')
          .eq('owner_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      if (created.isNotEmpty) {
        await scapeSupabase.rpc(
          'accept_terms',
          params: {'p_audience': 'partner', 'p_venue_id': created.first['id']},
        );
      }
    }
    return const VenueSignupResult();
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
