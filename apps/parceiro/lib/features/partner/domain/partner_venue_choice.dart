/// Uma unidade (casa) do mesmo login do Parceiro.
///
/// Um dono pode ter mais de uma unidade, por exemplo uma em cada cidade, cada
/// uma com o próprio cadastro. O painel mostra uma por vez.
class PartnerVenueOption {
  const PartnerVenueOption({
    required this.id,
    required this.name,
    required this.status,
    this.cityId,
    this.cityName,
  });

  final String id;
  final String name;

  /// Cidade da unidade. No app do jogador ela aparece nesta cidade, com as
  /// salas dela.
  final String? cityId;
  final String? cityName;

  /// `pending`, `approved` ou `rejected`.
  final String? status;

  bool get approved => status == 'approved';
}

/// Escolhe a unidade aberta no painel.
///
/// [venues] vem da mais nova para a mais antiga. Vale a unidade escolhida
/// antes ([preferredId]) se ela ainda é do login. Sem escolha, abre a mais
/// nova aprovada, depois a mais nova em análise, depois a mais nova. Assim,
/// cadastrar uma segunda unidade não tranca o painel da que já está aprovada.
PartnerVenueOption? pickPartnerVenue(
  List<PartnerVenueOption> venues, {
  String? preferredId,
}) {
  if (venues.isEmpty) return null;
  if (preferredId != null && preferredId.isNotEmpty) {
    for (final venue in venues) {
      if (venue.id == preferredId) return venue;
    }
  }
  for (final venue in venues) {
    if (venue.approved) return venue;
  }
  for (final venue in venues) {
    if (venue.status == 'pending') return venue;
  }
  return venues.first;
}

/// Rótulo curto do estado, ao lado do nome no seletor de unidades.
String? partnerVenueStatusLabel(String? status) {
  return switch (status) {
    'pending' => 'em análise',
    'rejected' => 'recusada',
    _ => null,
  };
}
