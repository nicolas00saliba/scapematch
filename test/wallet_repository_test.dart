import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/payments/data/fake_payment_methods_repository.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/wallet/data/fake_wallet_repository.dart';
import 'package:scapematch/features/wallet/domain/money.dart';
import 'package:scapematch/features/wallet/domain/wallet_transaction.dart';

void main() {
  test(
    'sample balance is the sum of the ledger and a top-up does nothing',
    () async {
      final wallet = FakeWalletRepository();
      final before = await wallet.balance();
      final lines = await wallet.transactions();
      final summed = lines.fold<int>(0, (sum, line) => sum + line.signedCents);

      expect(before, const Money(4000));
      expect(summed, before.cents);
      expect(lines, hasLength(1));
      expect(lines.single.kind, WalletTransactionKind.credit);

      final outcome = await wallet.addBalance(
        amount: const Money(5000),
        idempotencyKey: 'top-up-1',
      );
      expect(outcome.applied, isFalse);
      expect(await wallet.balance(), before);
      expect(await wallet.transactions(), hasLength(1));
    },
  );

  test('a payment method keeps only the last four digits', () {
    final method = PaymentMethod(
      id: 'card-1',
      brand: CardBrand.visa,
      last4: '4242',
      nickname: 'Pessoal',
    );
    expect(method.last4, '4242');
    expect(cardBrandLabel(method.brand), 'Visa');
    expect(
      () => PaymentMethod(
        id: 'card-2',
        brand: CardBrand.elo,
        last4: '4242424242424242',
        nickname: 'Não',
      ),
      throwsArgumentError,
    );
    expect(
      () => PaymentMethod(
        id: 'card-3',
        brand: CardBrand.other,
        last4: '42',
        nickname: 'Curto',
      ),
      throwsArgumentError,
    );
  });

  test('the sample payment list is empty', () async {
    final methods = await FakePaymentMethodsRepository().list();
    expect(methods, isEmpty);
  });
}
