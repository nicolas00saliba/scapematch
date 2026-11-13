/// Caminho da reivindicação. O contato oficial não sai daqui.
enum VenueClaimPath { none, otp, manual, alreadyOwner, alreadyClaimed }

class ClaimableVenue {
  const ClaimableVenue({
    required this.path,
    this.venueId = '',
    this.name = '',
    this.cityId = '',
    this.neighborhood = '',
    this.hasOfficialEmail = false,
    this.hasOfficialPhone = false,
  });

  final VenueClaimPath path;
  final String venueId;
  final String name;
  final String cityId;
  final String neighborhood;
  final bool hasOfficialEmail;
  final bool hasOfficialPhone;

  bool get offersClaim =>
      path == VenueClaimPath.otp || path == VenueClaimPath.manual;

  static ClaimableVenue fromJson(Map<String, dynamic> json) {
    return ClaimableVenue(
      path: _path('${json['path'] ?? ''}'),
      venueId: '${json['venue_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      cityId: '${json['city_id'] ?? ''}',
      neighborhood: '${json['neighborhood'] ?? ''}',
      hasOfficialEmail: json['has_official_email'] == true,
      hasOfficialPhone: json['has_official_phone'] == true,
    );
  }
}

VenueClaimPath _path(String raw) {
  return switch (raw) {
    'otp' => VenueClaimPath.otp,
    'manual' => VenueClaimPath.manual,
    'already_owner' => VenueClaimPath.alreadyOwner,
    'already_claimed' => VenueClaimPath.alreadyClaimed,
    _ => VenueClaimPath.none,
  };
}

class ClaimDispatch {
  const ClaimDispatch({
    required this.status,
    this.hint = '',
  });

  final String status;
  final String hint;

  bool get sent => status == 'otp';
  bool get manual => status == 'manual';
}

/// O código tem 6 dígitos. Qualquer outro texto não segue.
bool claimCodeLooksValid(String raw) {
  return RegExp(r'^[0-9]{6}$').hasMatch(raw.trim());
}
