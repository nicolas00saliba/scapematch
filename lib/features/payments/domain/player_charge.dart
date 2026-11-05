/// Cobrança que o jogador pode ver na conta. Sem dado do provedor.
class PlayerCharge {
  const PlayerCharge({
    required this.id,
    required this.amountCents,
    required this.roomName,
    required this.chargedAt,
    required this.status,
    required this.refunded,
  });

  final String id;
  final int amountCents;
  final String roomName;
  final DateTime chargedAt;
  final String status;
  final bool refunded;

  String get statusLabel {
    if (refunded || status == 'refunded') return 'Reembolsado';
    return switch (status) {
      'paid' => 'Pago',
      'pending' => 'Pendente',
      'failed' => 'Falhou',
      'cancelled' => 'Cancelado',
      _ => status,
    };
  }
}
