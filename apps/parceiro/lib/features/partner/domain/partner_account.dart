import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';

/// Casa que entrou no Parceiro.
class PartnerAccount {
  const PartnerAccount({
    required this.email,
    required this.houseId,
    required this.houseName,
    this.userId = '',
    this.venueStatus = 'approved',
    this.isAdmin = false,
    this.venues = const [],
    this.removedVenues = const [],
  });

  final String email;
  final String houseId;
  final String houseName;
  final String userId;

  /// `loading`, nulo (sem casa), `pending`, `approved` ou `rejected`.
  final String? venueStatus;
  final bool isAdmin;

  /// Todas as unidades do login, da mais nova para a mais antiga. A aberta é
  /// [houseId].
  final List<PartnerVenueOption> venues;

  /// Unidades que o dono removeu e pode reativar.
  final List<PartnerVenueOption> removedVenues;

  /// Outras unidades do mesmo login, para trocar sem sair.
  List<PartnerVenueOption> get otherVenues => [
    for (final venue in venues)
      if (venue.id != houseId) venue,
  ];

  /// A mesma conta com outra unidade aberta.
  PartnerAccount openVenue(PartnerVenueOption venue) {
    return PartnerAccount(
      email: email,
      houseId: venue.id,
      houseName: venue.name,
      userId: userId,
      venueStatus: venue.status,
      isAdmin: isAdmin,
      venues: venues,
      removedVenues: removedVenues,
    );
  }

  bool get hasApprovedHouse => houseId.isNotEmpty && venueStatus == 'approved';
}

const partnerDemoPassword = 'demo';

/// Atalho da mesma casa de exemplo. Não entra no build de produção.
const partnerQuickUser = 'a';
const partnerQuickPassword = 'b';

const partnerDemoAccount = PartnerAccount(
  email: 'xv@scapematch.exemplo',
  houseId: SampleIds.houseCwbRuaXv,
  houseName: 'Mistério da Rua XV',
);

/// Senhas fixas só existem fora do release. O compilador de produção corta o resto.
const partnerAdminAccount = PartnerAccount(
  email: 'admin@scapematch.exemplo',
  houseId: 'admin',
  houseName: 'Admin',
  isAdmin: true,
);

PartnerAccount? matchPartnerLogin(String email, String password) {
  if (!kAllowSampleLogin) return null;
  final id = email.trim().toLowerCase();
  final quick = id == partnerQuickUser && password == partnerQuickPassword;
  final full =
      id == partnerDemoAccount.email && password == partnerDemoPassword;
  if (quick || full) return partnerDemoAccount;
  if (id == partnerAdminAccount.email && password == partnerDemoPassword) {
    return partnerAdminAccount;
  }
  return null;
}

String partnerDemoEmailHint() {
  if (!kAllowSampleLogin) return '';
  return 'Casa de exemplo: xv@scapematch.exemplo. Senha: demo.';
}

String partnerDemoQuickLabel() {
  if (!kAllowSampleLogin) return '';
  return 'Demo: a / b';
}
