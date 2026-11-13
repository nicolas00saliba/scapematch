import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_claim.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_draft.dart';

class VenueClaimClient {
  const VenueClaimClient();

  Future<ClaimableVenue> lookup(String document) async {
    final raw = await scapeSupabase.rpc(
      'find_claimable_venue',
      params: {'p_document': VenueDraft.digits(document)},
    );
    if (raw is! Map) return const ClaimableVenue(path: VenueClaimPath.none);
    return ClaimableVenue.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<ClaimDispatch> send(String venueId) async {
    final response = await scapeSupabase.functions.invoke(
      'venue-claim',
      body: {'action': 'send', 'venue_id': venueId},
    );
    return _dispatch(response.data);
  }

  Future<bool> confirm(String venueId, String code) async {
    final response = await scapeSupabase.functions.invoke(
      'venue-claim',
      body: {
        'action': 'confirm',
        'venue_id': venueId,
        'code': code.trim(),
      },
    );
    final data = response.data;
    return data is Map && data['status'] == 'confirmed';
  }

  Future<String?> provision(String venueId) async {
    try {
      final response = await scapeSupabase.functions.invoke(
        'provision-venue-wallet',
        body: {'venue_id': venueId},
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        return 'Não foi possível criar a subconta.';
      }
      return null;
    } on Object {
      return 'Não foi possível criar a subconta.';
    }
  }

  ClaimDispatch _dispatch(Object? data) {
    if (data is! Map) return const ClaimDispatch(status: 'erro');
    return ClaimDispatch(
      status: '${data['status'] ?? 'erro'}',
      hint: '${data['hint'] ?? ''}',
    );
  }
}
