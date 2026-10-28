import 'package:scapematch/features/payments/domain/payment_method.dart';

/// Cartões que a conta já cadastrou, só metadados.
///
/// A lista de preparativos lê [list]. Cadastrar de verdade entra depois,
/// com o token do provedor, não com o número digitado no app.
abstract class PaymentMethodsRepository {
  Future<List<PaymentMethod>> list();
}
