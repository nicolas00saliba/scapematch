import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';

/// O que o cadastro pode mostrar de uma casa já aprovada.
class PublicVenue {
  const PublicVenue({
    required this.id,
    required this.name,
    required this.cityId,
    required this.neighborhood,
    required this.streetAddress,
    required this.addressNumber,
    required this.postalCode,
  });

  final String id;
  final String name;
  final String cityId;
  final String neighborhood;
  final String streetAddress;
  final String addressNumber;
  final String postalCode;
}

class VenueConflict {
  const VenueConflict({required this.type, this.venueId, this.venueName});

  final String type;
  final String? venueId;
  final String? venueName;

  bool get blocks => type == venueConflictDocument;
}

class VenueDraft {
  const VenueDraft({
    required this.ownerId,
    required this.name,
    required this.cityId,
    required this.postalCode,
    required this.addressNumber,
    required this.document,
    this.neighborhood = 'Centro',
    this.streetAddress = '',
    this.phone = '',
  });

  final String ownerId;
  final String name;
  final String cityId;
  final String postalCode;
  final String addressNumber;
  final String document;
  final String neighborhood;
  final String streetAddress;
  final String phone;
}

class VenueRecord {
  const VenueRecord({
    required this.id,
    required this.ownerId,
    required this.cityId,
    required this.name,
    required this.neighborhood,
    required this.streetAddress,
    required this.addressNumber,
    required this.postalCode,
    required this.documentNumber,
    required this.phone,
    required this.status,
    this.possibleDuplicateOf,
    this.mergedInto,
  });

  final String id;
  final String ownerId;
  final String cityId;
  final String name;
  final String neighborhood;
  final String streetAddress;
  final String addressNumber;
  final String postalCode;

  /// Fica no registro. A checagem de duplicata não devolve este campo.
  final String documentNumber;

  /// Fica no registro. A checagem de duplicata não devolve este campo.
  final String phone;
  final String status;
  final String? possibleDuplicateOf;
  final String? mergedInto;

  String get documentDigits => normalizeDocument(documentNumber) ?? '';
  String get nameNormalized => normalizeVenueName(name);
  String get addressNumberNormalized => normalizeAddressNumber(addressNumber);
  String get postalDigits => normalizePostalCode(postalCode);

  bool get activeDocument => status != 'rejected' && status != 'merged';

  PublicVenue get publicView => PublicVenue(
    id: id,
    name: name,
    cityId: cityId,
    neighborhood: neighborhood,
    streetAddress: streetAddress,
    addressNumber: addressNumber,
    postalCode: postalDigits,
  );

  VenueRecord copyWith({
    String? ownerId,
    String? status,
    String? possibleDuplicateOf,
    String? mergedInto,
    bool clearDuplicate = false,
    bool clearMerged = false,
  }) {
    return VenueRecord(
      id: id,
      ownerId: ownerId ?? this.ownerId,
      cityId: cityId,
      name: name,
      neighborhood: neighborhood,
      streetAddress: streetAddress,
      addressNumber: addressNumber,
      postalCode: postalCode,
      documentNumber: documentNumber,
      phone: phone,
      status: status ?? this.status,
      possibleDuplicateOf: clearDuplicate
          ? null
          : possibleDuplicateOf ?? this.possibleDuplicateOf,
      mergedInto: clearMerged ? null : mergedInto ?? this.mergedInto,
    );
  }
}

class VenueClaim {
  const VenueClaim({
    required this.id,
    required this.venueId,
    required this.claimantId,
    required this.note,
    required this.status,
    this.pendingVenueId,
  });

  final String id;
  final String venueId;
  final String claimantId;
  final String? pendingVenueId;
  final String note;
  final String status;

  VenueClaim copyWith({String? status}) {
    return VenueClaim(
      id: id,
      venueId: venueId,
      claimantId: claimantId,
      pendingVenueId: pendingVenueId,
      note: note,
      status: status ?? this.status,
    );
  }
}

class VenueDocumentBlocked implements Exception {
  const VenueDocumentBlocked();
}

class VenueLinkInvalid implements Exception {
  const VenueLinkInvalid();
}

class VenueClaimProblem implements Exception {
  const VenueClaimProblem(this.message);

  final String message;
}

class VenueBoard {
  const VenueBoard({
    required this.venues,
    required this.claims,
    this.sequence = 1,
  });

  final List<VenueRecord> venues;
  final List<VenueClaim> claims;
  final int sequence;

  static const approvedNinjaId = 'venue-ninja';
  static const pendingNinjaId = 'venue-ninja-centro';
  static const ninjaClaimId = 'claim-ninja';
  static const ninjaOwnerId = 'owner-ninja';
  static const applicantId = 'owner-applicant';

  /// Casa aprovada e um cadastro parecido, para a fila do admin.
  factory VenueBoard.demo() {
    return const VenueBoard(
      sequence: 4,
      venues: [
        VenueRecord(
          id: approvedNinjaId,
          ownerId: ninjaOwnerId,
          cityId: 'curitiba',
          name: 'Ninja Escape Room Ltda.',
          neighborhood: 'Centro',
          streetAddress: 'Rua das Flores',
          addressNumber: '120',
          postalCode: '80010000',
          documentNumber: '12345678000195',
          phone: '41988887777',
          status: 'approved',
        ),
        VenueRecord(
          id: pendingNinjaId,
          ownerId: applicantId,
          cityId: 'curitiba',
          name: 'Ninja Centro',
          neighborhood: 'Centro',
          streetAddress: 'Rua das Flores',
          addressNumber: '120',
          postalCode: '80010000',
          documentNumber: '99888777000166',
          phone: '41911113333',
          status: 'pending',
          possibleDuplicateOf: approvedNinjaId,
        ),
      ],
      claims: [
        VenueClaim(
          id: ninjaClaimId,
          venueId: approvedNinjaId,
          claimantId: applicantId,
          pendingVenueId: pendingNinjaId,
          note: 'A casa nova é a mesma. O documento é o da filial.',
          status: 'pending',
        ),
      ],
    );
  }

  VenueRecord? venueById(String id) {
    for (final venue in venues) {
      if (venue.id == id) {
        return venue;
      }
    }
    return null;
  }

  List<VenueRecord> get pendingVenues =>
      venues.where((venue) => venue.status == 'pending').toList();

  /// Conflitos visíveis. Casa pendente de terceiro não entra com nome.
  List<VenueConflict> check(VenueDraft draft, {String? exceptVenueId}) {
    final digits = normalizeDocument(draft.document);
    final name = normalizeVenueName(draft.name);
    final cityId = resolveVenueCity(draft.cityId);
    final postal = normalizePostalCode(draft.postalCode);
    final number = normalizeAddressNumber(draft.addressNumber);
    final conflicts = <VenueConflict>[];

    VenueRecord? documentHit;
    for (final venue in venues) {
      if (venue.id == exceptVenueId || !venue.activeDocument) {
        continue;
      }
      if (digits == null || venue.documentDigits != digits) {
        continue;
      }
      if (venue.status != 'pending' && venue.status != 'approved') {
        continue;
      }
      if (documentHit == null ||
          (venue.status == 'approved' && documentHit.status != 'approved')) {
        documentHit = venue;
      }
    }
    if (documentHit != null) {
      final approved = documentHit.status == 'approved';
      conflicts.add(
        VenueConflict(
          type: venueConflictDocument,
          venueId: approved ? documentHit.id : null,
          venueName: approved ? documentHit.name : null,
        ),
      );
    }

    final addresses = <VenueRecord>[];
    for (final venue in venues) {
      if (venue.id == exceptVenueId || venue.status != 'approved') {
        continue;
      }
      if (postal.length == 8 &&
          venue.postalDigits == postal &&
          venue.addressNumberNormalized == number) {
        addresses.add(venue);
      }
    }
    for (final venue in addresses.take(3)) {
      conflicts.add(
        VenueConflict(
          type: venueConflictAddress,
          venueId: venue.id,
          venueName: venue.name,
        ),
      );
    }

    final names = <({VenueRecord venue, double score})>[];
    for (final venue in venues) {
      if (venue.id == exceptVenueId || venue.status != 'approved') {
        continue;
      }
      if (cityId == null || venue.cityId != cityId) {
        continue;
      }
      if (!venueNamesMatch(venue.nameNormalized, name)) {
        continue;
      }
      names.add((
        venue: venue,
        score: trigramSimilarity(venue.nameNormalized, name),
      ));
    }
    names.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.venue.name.compareTo(b.venue.name);
    });
    for (final match in names.take(3)) {
      conflicts.add(
        VenueConflict(
          type: venueConflictName,
          venueId: match.venue.id,
          venueName: match.venue.name,
        ),
      );
    }
    return conflicts;
  }

  /// Casa aprovada que o aviso deve marcar, se o cadastro seguir.
  String? duplicateTarget(List<VenueConflict> conflicts) {
    for (final conflict in conflicts) {
      if (conflict.type == venueConflictAddress && conflict.venueId != null) {
        return conflict.venueId;
      }
    }
    for (final conflict in conflicts) {
      if (conflict.type == venueConflictName && conflict.venueId != null) {
        return conflict.venueId;
      }
    }
    for (final conflict in conflicts) {
      if (conflict.venueId != null) {
        return conflict.venueId;
      }
    }
    return null;
  }

  List<VenueClaim> claimsVisibleTo(String? userId, {required bool admin}) {
    if (userId == null) {
      return const [];
    }
    if (admin) {
      return claims;
    }
    return claims.where((claim) => claim.claimantId == userId).toList();
  }

  VenueBoard submit(VenueDraft draft, {String? possibleDuplicateOf}) {
    final conflicts = check(draft);
    if (conflicts.any((conflict) => conflict.blocks)) {
      throw const VenueDocumentBlocked();
    }
    final digits = normalizeDocument(draft.document);
    if (draft.name.trim().length < 2 ||
        resolveVenueCity(draft.cityId) == null ||
        normalizePostalCode(draft.postalCode).length != 8 ||
        digits == null ||
        (digits.length != 11 && digits.length != 14)) {
      throw const VenueLinkInvalid();
    }
    if (possibleDuplicateOf != null &&
        !venues.any(
          (venue) =>
              venue.id == possibleDuplicateOf && venue.status == 'approved',
        )) {
      throw const VenueLinkInvalid();
    }
    if (venues.any(
      (venue) => venue.activeDocument && venue.documentDigits == digits,
    )) {
      throw const VenueDocumentBlocked();
    }
    final created = VenueRecord(
      id: 'venue-$sequence',
      ownerId: draft.ownerId,
      cityId: resolveVenueCity(draft.cityId)!,
      name: draft.name.trim(),
      neighborhood: draft.neighborhood.trim().isEmpty
          ? 'Centro'
          : draft.neighborhood.trim(),
      streetAddress: draft.streetAddress.trim(),
      addressNumber: draft.addressNumber.trim().isEmpty
          ? 'S/N'
          : draft.addressNumber.trim(),
      postalCode: normalizePostalCode(draft.postalCode),
      documentNumber: digits,
      phone: draft.phone.replaceAll(RegExp(r'\D'), ''),
      status: 'pending',
      possibleDuplicateOf: possibleDuplicateOf,
    );
    return VenueBoard(
      venues: [...venues, created],
      claims: claims,
      sequence: sequence + 1,
    );
  }

  VenueBoard claim({
    required String venueId,
    required String claimantId,
    required String note,
    String? pendingVenueId,
  }) {
    final venue = venueById(venueId);
    if (venue == null || venue.status != 'approved') {
      throw const VenueClaimProblem('Essa casa não está aprovada.');
    }
    if (venue.ownerId == claimantId) {
      throw const VenueClaimProblem('Esta casa já está na sua conta.');
    }
    if (pendingVenueId != null) {
      final pending = venueById(pendingVenueId);
      if (pending == null ||
          pending.ownerId != claimantId ||
          pending.status != 'pending') {
        throw const VenueClaimProblem('O cadastro pendente não é seu.');
      }
    }
    if (claims.any(
      (item) =>
          item.venueId == venueId &&
          item.claimantId == claimantId &&
          item.status == 'pending',
    )) {
      throw const VenueClaimProblem('Você já pediu esta casa.');
    }
    final trimmed = note.trim();
    final created = VenueClaim(
      id: 'claim-$sequence',
      venueId: venueId,
      claimantId: claimantId,
      pendingVenueId: pendingVenueId,
      note: trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed,
      status: 'pending',
    );
    return VenueBoard(
      venues: venues,
      claims: [...claims, created],
      sequence: sequence + 1,
    );
  }

  VenueBoard reviewVenue({
    required String venueId,
    required String decision,
    String? mergeInto,
  }) {
    final current = venueById(venueId);
    if (current == null || current.status != 'pending') {
      throw const VenueClaimProblem('Essa casa não está pendente.');
    }
    if (decision == 'merged') {
      final target = mergeInto == null ? null : venueById(mergeInto);
      if (target == null ||
          target.id == venueId ||
          target.status != 'approved') {
        throw const VenueLinkInvalid();
      }
      return _replaceVenue(
        current.copyWith(status: 'merged', mergedInto: target.id),
      );
    }
    if (decision != 'approved' && decision != 'rejected') {
      throw const VenueClaimProblem('Decisão inválida.');
    }
    if (decision == 'approved' &&
        venues.any(
          (venue) =>
              venue.id != current.id &&
              venue.activeDocument &&
              venue.documentDigits == current.documentDigits,
        )) {
      throw const VenueDocumentBlocked();
    }
    return _replaceVenue(current.copyWith(status: decision));
  }

  VenueBoard reviewClaim({required String claimId, required String decision}) {
    VenueClaim? current;
    for (final claim in claims) {
      if (claim.id == claimId) {
        current = claim;
      }
    }
    if (current == null || current.status != 'pending') {
      throw const VenueClaimProblem('Esse pedido não está pendente.');
    }
    if (decision != 'approved' && decision != 'rejected') {
      throw const VenueClaimProblem('Decisão inválida.');
    }
    final updatedClaims = [
      for (final claim in claims)
        if (claim.id == claimId) claim.copyWith(status: decision) else claim,
    ];
    var nextVenues = venues;
    if (decision == 'approved') {
      nextVenues = [
        for (final venue in venues)
          if (venue.id == current.venueId && venue.status == 'approved')
            venue.copyWith(ownerId: current.claimantId)
          else if (venue.id == current.pendingVenueId &&
              venue.ownerId == current.claimantId &&
              venue.status == 'pending')
            venue.copyWith(status: 'merged', mergedInto: current.venueId)
          else
            venue,
      ];
    }
    return VenueBoard(
      venues: nextVenues,
      claims: updatedClaims,
      sequence: sequence,
    );
  }

  VenueBoard _replaceVenue(VenueRecord next) {
    return VenueBoard(
      venues: [
        for (final venue in venues)
          if (venue.id == next.id) next else venue,
      ],
      claims: claims,
      sequence: sequence,
    );
  }
}
