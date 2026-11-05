import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/payments/domain/player_charge.dart';
import 'package:scapematch/features/wallet/presentation/payment_methods_body.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Carteira do modo real: cartões salvos e pagamentos da conta.
/// Sem saldo fictício e sem "Adicionar saldo".
class RealAccountWallet extends ConsumerWidget {
  const RealAccountWallet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payments = ref.watch(playerPaymentsProvider);
    return Material(
      key: AppKeys.accountWallet,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Carteira',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const PaymentMethodsBody(),
            const SizedBox(height: 20),
            Text(
              'Meus pagamentos',
              key: AppKeys.myPayments,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            payments.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) =>
                  const Text('Não foi possível carregar os pagamentos.'),
              data: (items) {
                if (items.isEmpty) {
                  return const Text('Nenhum pagamento ainda.');
                }
                return Column(
                  children: [
                    for (final charge in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PaymentTile(charge: charge),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.charge});

  final PlayerCharge charge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = _date(charge.chargedAt);
    return ListTile(
      key: AppKeys.paymentRow(charge.id),
      contentPadding: EdgeInsets.zero,
      title: Text(charge.roomName),
      subtitle: Text('$when · ${charge.statusLabel}'),
      trailing: Text(
        formatPrice(charge.amountCents),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}
