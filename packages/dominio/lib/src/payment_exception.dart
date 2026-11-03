/// Erro das regras de reserva e comissão. A mensagem já está em português.
class PaymentException implements Exception {
  PaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Quem não é da equipe tentou mudar a taxa.
class PlatformPermissionException extends PaymentException {
  PlatformPermissionException()
    : super('Só a equipe da plataforma pode alterar a comissão.');
}

/// A mesma chave de idempotência voltou para outra cobrança.
class IdempotencyConflictException extends PaymentException {
  IdempotencyConflictException()
    : super('Essa chave de idempotência já foi usada em outra cobrança.');
}
