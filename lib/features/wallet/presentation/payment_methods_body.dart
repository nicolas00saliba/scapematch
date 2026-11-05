import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/account/presentation/cpf_screen.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/payments/presentation/card_entry_fields.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';
import 'package:scapematch/providers/repositories.dart';

/// Lista de cartões salvos e o formulário que chama `tokenize-card`.
class PaymentMethodsBody extends ConsumerStatefulWidget {
  const PaymentMethodsBody({super.key});

  @override
  ConsumerState<PaymentMethodsBody> createState() => _PaymentMethodsBodyState();
}

class _PaymentMethodsBodyState extends ConsumerState<PaymentMethodsBody> {
  final _entry = CardEntryControllers();
  var _showForm = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Future<void> _remove(String id) async {
    final removed = await ref.read(paymentMethodsRepositoryProvider).remove(id);
    if (!mounted) return;
    if (!removed) {
      setState(() => _error = 'Não foi possível remover o cartão.');
      return;
    }
    ref.invalidate(paymentMethodsProvider);
  }

  Future<void> _save() async {
    final draft = _entry.draft;
    if (draft == null) {
      setState(() {
        _error = 'Preencha nome, número, validade e o código de segurança.';
      });
      return;
    }
    if (!await ensurePlayerCpf(context, ref) || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(paymentMethodsRepositoryProvider).save(draft);
      _entry.clear();
      ref.invalidate(paymentMethodsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível guardar o cartão.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

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
            final canRemove = ref.watch(backendPlanProvider).connectsSupabase;
            return Column(
              children: [
                for (final method in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MethodTile(
                      method: method,
                      onRemove: canRemove ? () => _remove(method.id) : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: AppKeys.addCard,
          onPressed: () => setState(() => _showForm = true),
          child: const Text('Adicionar cartão'),
        ),
        if (_showForm) ...[
          const SizedBox(height: 12),
          Text(
            'A lista mostra a bandeira e os 4 últimos dígitos. '
            'O número segue só para a tokenização.',
            key: AppKeys.addCardNotice,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          CardEntryFields(controllers: _entry),
          const SizedBox(height: 12),
          FilledButton(
            key: AppKeys.addCardSave,
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar cartão'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.method, this.onRemove});

  final PaymentMethod method;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${method.nickname} · ${cardBrandLabel(method.brand)} · ${method.last4}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onRemove != null)
              IconButton(
                key: AppKeys.removeSavedCard(method.id),
                tooltip: 'Remover cartão',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }
}
