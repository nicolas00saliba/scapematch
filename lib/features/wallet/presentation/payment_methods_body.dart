import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Lista de cartões. Vazia nesta versão. O botão não abre formulário.
class PaymentMethodsBody extends ConsumerStatefulWidget {
  const PaymentMethodsBody({super.key});

  @override
  ConsumerState<PaymentMethodsBody> createState() => _PaymentMethodsBodyState();
}

class _PaymentMethodsBodyState extends ConsumerState<PaymentMethodsBody> {
  bool _showNotice = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods = ref.watch(paymentMethodsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        methods.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) =>
              const Text('Não foi possível carregar os cartões de exemplo.'),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'Nenhum cartão cadastrado',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              );
            }
            return Column(
              children: [
                for (final method in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MethodTile(method: method),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: AppKeys.addCard,
          onPressed: () => setState(() => _showNotice = true),
          child: const Text('Adicionar cartão'),
        ),
        if (_showNotice) ...[
          const SizedBox(height: 12),
          Text(
            'O cadastro de cartão chega em breve. Esta versão não pede '
            'número, validade nem código de segurança. Nada é cobrado.',
            key: AppKeys.addCardNotice,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method});

  final PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '${method.nickname} · ${cardBrandLabel(method.brand)} · ${method.last4}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
