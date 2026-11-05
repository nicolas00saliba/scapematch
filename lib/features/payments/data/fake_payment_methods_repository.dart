import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:scapematch/features/payments/data/payment_methods_repository.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';

/// Lista de exemplo. Guarda só os 4 últimos dígitos e a bandeira.
class FakePaymentMethodsRepository implements PaymentMethodsRepository {
  FakePaymentMethodsRepository({
    List<PaymentMethod>? methods,
    this.latency = Duration.zero,
  }) : _methods = [...?methods];

  final List<PaymentMethod> _methods;
  final Duration latency;

  @override
  Future<List<PaymentMethod>> list() async {
    if (latency != Duration.zero) {
      await Future<void>.delayed(latency);
    }
    return List<PaymentMethod>.unmodifiable(_methods);
  }

  @override
  Future<PaymentMethod> save(CardDraft card) async {
    final digits = card.number.replaceAll(RegExp(r'\D'), '');
    final last4 = digits.substring(digits.length - 4);
    final method = PaymentMethod(
      id: 'card-local-$last4-${_methods.length}',
      brand: _brand(digits),
      last4: last4,
      nickname: card.holderName,
    );
    _methods.add(method);
    return method;
  }

  @override
  Future<bool> remove(String id) async {
    final before = _methods.length;
    _methods.removeWhere((method) => method.id == id);
    return _methods.length < before;
  }
}

CardBrand _brand(String digits) {
  if (digits.startsWith('4')) {
    return CardBrand.visa;
  }
  if (digits.startsWith('5')) {
    return CardBrand.mastercard;
  }
  if (digits.startsWith('6')) {
    return CardBrand.elo;
  }
  return CardBrand.other;
}
