/// Destinos simples da aba Conta. O nome entra na rota.
enum AccountDestination { profile, partners, referral, help, gift, settings }

AccountDestination? accountDestinationByName(String raw) {
  for (final destination in AccountDestination.values) {
    if (destination.name == raw) {
      return destination;
    }
  }
  return null;
}
