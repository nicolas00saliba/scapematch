import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_board.dart';

class VenueRegistry extends Notifier<VenueBoard> {
  VenueRegistry([this._seed]);

  final VenueBoard? _seed;

  @override
  VenueBoard build() => _seed ?? VenueBoard.demo();

  List<VenueConflict> check(VenueDraft draft, {String? exceptVenueId}) {
    return state.check(draft, exceptVenueId: exceptVenueId);
  }

  void submit(VenueDraft draft, {String? possibleDuplicateOf}) {
    state = state.submit(draft, possibleDuplicateOf: possibleDuplicateOf);
  }

  void claim({
    required String venueId,
    required String claimantId,
    required String note,
    String? pendingVenueId,
  }) {
    state = state.claim(
      venueId: venueId,
      claimantId: claimantId,
      note: note,
      pendingVenueId: pendingVenueId,
    );
  }

  void reviewVenue({
    required String venueId,
    required String decision,
    String? mergeInto,
  }) {
    state = state.reviewVenue(
      venueId: venueId,
      decision: decision,
      mergeInto: mergeInto,
    );
  }

  void reviewClaim({required String claimId, required String decision}) {
    state = state.reviewClaim(claimId: claimId, decision: decision);
  }
}

final venueRegistryProvider = NotifierProvider<VenueRegistry, VenueBoard>(
  VenueRegistry.new,
);
