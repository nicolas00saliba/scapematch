import 'package:scapematch/features/payments/data/payment_methods_repository.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';

/// Nenhum cartão de exemplo. A tela mostra o estado vazio.
class FakePaymentMethodsRepository implements PaymentMethodsRepository {
  FakePaymentMethodsRepository({
    List<PaymentMethod>? methods,
    this.latency = Duration.zero,
  }) : _methods = List<PaymentMethod>.unmodifiable(methods ?? const []);

  final List<PaymentMethod> _methods;
  final Duration latency;

  @override
  Future<List<PaymentMethod>> list() async {
    if (latency != Duration.zero) {
      await Future<void>.delayed(latency);
    }
    return _methods;
  }
}
