import 'package:supabase_flutter/supabase_flutter.dart';

/// Convite de sócio ou equipe. Só entra quem aceita.
class VenueInvite {
  const VenueInvite({
    required this.venueId,
    required this.venueName,
    required this.role,
  });

  final String venueId;
  final String venueName;
  final String role;

  String get roleLabel => role == 'partner' ? 'sócio' : 'equipe';
}

abstract class VenueStaffGateway {
  Future<List<VenueInvite>> mine();
  Future<String?> accept(String venueId);
  Future<String?> decline(String venueId);
}

class MemoryVenueStaffGateway implements VenueStaffGateway {
  MemoryVenueStaffGateway({List<VenueInvite>? invites})
    : invites = List.of(invites ?? const []);

  final List<VenueInvite> invites;

  @override
  Future<List<VenueInvite>> mine() async => List.of(invites);

  @override
  Future<String?> accept(String venueId) async {
    invites.removeWhere((invite) => invite.venueId == venueId);
    return null;
  }

  @override
  Future<String?> decline(String venueId) async {
    invites.removeWhere((invite) => invite.venueId == venueId);
    return null;
  }
}

class SupabaseVenueStaffGateway implements VenueStaffGateway {
  SupabaseVenueStaffGateway(this.client);

  final SupabaseClient client;

  @override
  Future<List<VenueInvite>> mine() async {
    final raw = await client.rpc('my_venue_invites');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          VenueInvite(
            venueId: '${item['venue_id'] ?? ''}',
            venueName: '${item['venue_name'] ?? ''}',
            role: '${item['role'] ?? ''}',
          ),
    ];
  }

  @override
  Future<String?> accept(String venueId) {
    return _call('accept_venue_staff', venueId);
  }

  @override
  Future<String?> decline(String venueId) {
    return _call('decline_venue_staff', venueId);
  }

  Future<String?> _call(String fn, String venueId) async {
    try {
      await client.rpc(fn, params: {'p_venue_id': venueId});
      return null;
    } on PostgrestException catch (error) {
      final message = error.message.trim();
      if (message.isEmpty) return 'Não foi possível responder ao convite.';
      return message;
    }
  }
}
