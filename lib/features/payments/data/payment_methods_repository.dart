import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';

/// Cartões que a conta já cadastrou, só metadados.
///
/// [save] manda o número para `tokenize-card` e devolve o id, os 4 dígitos
/// e a bandeira. A lista não guarda o número.
abstract class PaymentMethodsRepository {
  Future<List<PaymentMethod>> list();

  Future<PaymentMethod> save(CardDraft card);
}
