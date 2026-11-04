import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

/// Colunas que o authenticated pode ler. Documento, telefone e renda ficam
/// em `venue_private`.
const partnerVenueColumns =
    'id, owner_id, city_id, name, neighborhood, street_address, '
    'address_number, postal_code, latitude, longitude, document_kind, '
    'category, badge, invite_id, status, reviewed_by, reviewed_at, created_at';

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

/// Grava a casa como pending. O gatilho `venues_guard` força o status.
Future<String?> submitVenue(VenueDraft draft) async {
  final error = draft.validate();
  if (error != null) return error;
  final city = await scapeSupabase
      .from('cities')
      .select('id, latitude, longitude')
      .eq('id', draft.cityId)
      .maybeSingle();
  if (city == null) return 'Cidade não encontrada.';
  String? inviteId;
  final code = draft.inviteCode.trim().toLowerCase();
  if (code.isNotEmpty) {
    final invite = await scapeSupabase
        .from('partner_invites')
        .select('id')
        .eq('code', code)
        .eq('active', true)
        .maybeSingle();
    if (invite == null) return 'Convite não encontrado.';
    inviteId = invite['id'] as String;
  }
  final income = double.parse(draft.incomeReais.trim().replaceAll(',', '.'));
  try {
    await scapeSupabase.from('venues').insert({
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
    });
    return null;
  } on Object catch (error) {
    final text = error.toString().toLowerCase();
    if (text.contains('unknown invite')) return 'Convite não encontrado.';
    if (text.contains('row-level') || text.contains('42501')) {
      return 'Entre na conta antes de cadastrar a casa.';
    }
    return 'Não foi possível enviar a casa. Confira os dados.';
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
