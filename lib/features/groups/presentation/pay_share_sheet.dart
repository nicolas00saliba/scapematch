import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/payments/data/card_payment_flow.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/payments/presentation/card_entry_fields.dart';
import 'package:scapematch/features/payments/presentation/own_card_holder.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Cartão de exemplo. O pagamento simulado não envia número.
final payTestCard = PaymentMethod(
  id: 'card-test-visa',
  brand: CardBrand.visa,
  last4: '4242',
  nickname: 'Cartão de teste',
);

/// Abre o pagamento simulado. Devolve verdadeiro quando a parte foi paga.
Future<bool> showPayShareSheet({
  required BuildContext context,
  required int amountCents,
  required String reference,
  required Future<bool> Function(PaymentMethodKind kind, {String? savedCardId})
  onPay,
  Future<bool> Function(CardDraft card)? onPayNewCard,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) {
      return PayShareSheet(
        amountCents: amountCents,
        reference: reference,
        onPay: onPay,
        onPayNewCard: onPayNewCard,
      );
    },
  );
  return paid ?? false;
}

class PayShareSheet extends ConsumerStatefulWidget {
  const PayShareSheet({
    super.key,
    required this.amountCents,
    required this.reference,
    required this.onPay,
    this.onPayNewCard,
  });

  final int amountCents;
  final String reference;
  final Future<bool> Function(PaymentMethodKind kind, {String? savedCardId})
  onPay;
  final Future<bool> Function(CardDraft card)? onPayNewCard;

  @override
  ConsumerState<PayShareSheet> createState() => _PayShareSheetState();
}

class _PayShareSheetState extends ConsumerState<PayShareSheet> {
  var _method = PaymentMethodKind.pix;
  var _busy = false;
  var _done = false;
  var _copied = false;
  String? _error;
  String? _cardId = payTestCard.id;
  final _entry = CardEntryControllers();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  String get _pixCode {
    final cents = widget.amountCents.toString().padLeft(4, '0');
    return '00020126580014BR.GOV.BCB.PIX0136scapematch.${widget.reference}'
        '.52040000530398654$cents';
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _pixCode));
    } catch (_) {
      // O teste do widget nem sempre entrega a área de transferência.
    }
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
  }

  Future<void> _toggleOwn(bool checked) async {
    setState(() => _entry.ownCard = checked);
    if (!checked) return;
    final ok = await fillOwnCardHolder(
      context: context,
      ref: ref,
      entry: _entry,
    );
    if (!mounted) return;
    setState(() {
      _entry.ownCard = ok;
      _error = ok ? null : 'Não foi possível usar os dados do perfil.';
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final real = ref.read(backendPlanProvider).connectsSupabase;
    _entry.requireHolderDocument = real;
    final bool ok;
    final draft = _method == PaymentMethodKind.card && _entry.started
        ? _entry.draft
        : null;
    if (_method == PaymentMethodKind.card && _entry.started && draft == null) {
      ok = false;
      if (real && _entry.holderDocumentProblem != null) {
        setState(() {
          _busy = false;
          _error = _entry.holderDocumentProblem;
        });
        return;
      }
    } else if (draft != null) {
      final payNew = widget.onPayNewCard;
      ok = payNew == null ? false : await payNew(draft);
    } else {
      final savedCardId =
          _method == PaymentMethodKind.card &&
              _cardId != null &&
              _cardId != payTestCard.id
          ? _cardId
          : null;
      ok = await widget.onPay(_method, savedCardId: savedCardId);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _done = ok;
      _error = ok ? null : 'Não foi possível pagar com este cartão.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height;
    final saved = ref.watch(paymentMethodsProvider).asData?.value ?? const [];
    final cards = scapeUsesLiveBackend ? saved : [payTestCard, ...saved];
    final realHolder = ref.watch(backendPlanProvider).connectsSupabase;
    _entry.requireHolderDocument = realHolder;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.92),
        child: AnimatedSwitcher(
          duration: scapeDuration(context, const Duration(milliseconds: 320)),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _done
              ? _Confirmed(
                  key: AppKeys.payConfirmed,
                  amount: formatPrice(widget.amountCents),
                )
              : ListView(
                  key: AppKeys.paySheet,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    Text(
                      'Pagar minha parte',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatPrice(widget.amountCents),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      GroupMessages.simulatedNotice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _MethodTile(
                            key: AppKeys.payMethodPix,
                            icon: Icons.qr_code_2,
                            label: 'Pix',
                            selected: _method == PaymentMethodKind.pix,
                            onTap: () => setState(() {
                              _method = PaymentMethodKind.pix;
                            }),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MethodTile(
                            key: AppKeys.payMethodCard,
                            icon: Icons.credit_card,
                            label: 'Cartão',
                            selected: _method == PaymentMethodKind.card,
                            onTap: () => setState(() {
                              _method = PaymentMethodKind.card;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: scapeDuration(
                        context,
                        const Duration(milliseconds: 240),
                      ),
                      child: _method == PaymentMethodKind.pix
                          ? _PixPanel(
                              key: const Key('pay-pix-panel'),
                              code: _pixCode,
                              copied: _copied,
                              onCopy: _copy,
                            )
                          : _CardPanel(
                              key: const Key('pay-card-panel'),
                              cards: cards,
                              selectedId: _cardId,
                              entry: _entry,
                              onOwnCard: realHolder ? _toggleOwn : null,
                              onSelect: (id) => setState(() => _cardId = id),
                            ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      key: AppKeys.paySimulate,
                      onPressed: _busy ? null : _confirm,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('Simular pagamento'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixPanel extends StatelessWidget {
  const _PixPanel({
    super.key,
    required this.code,
    required this.copied,
    required this.onCopy,
  });

  final String code;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: QrImageView(
              data: code,
              size: 168,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Pix simulado. O código abaixo não cobra.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              code,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: AppKeys.payCopyPix,
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check : Icons.copy),
            label: Text(copied ? 'Código copiado' : 'Copiar código'),
          ),
        ),
      ],
    );
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    super.key,
    required this.cards,
    required this.selectedId,
    required this.entry,
    required this.onSelect,
    this.onOwnCard,
  });

  final List<PaymentMethod> cards;
  final String? selectedId;
  final CardEntryControllers entry;
  final ValueChanged<String> onSelect;
  final ValueChanged<bool>? onOwnCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escolha um cartão salvo ou preencha um novo. '
          'A lista mostra a bandeira e os 4 últimos dígitos.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CardChoice(
              key: card.id == payTestCard.id ? AppKeys.payTestCard : null,
              card: card,
              selected: card.id == selectedId,
              onTap: () => onSelect(card.id),
            ),
          ),
        const SizedBox(height: 8),
        CardEntryFields(controllers: entry, onOwnCard: onOwnCard),
      ],
    );
  }
}

class _CardChoice extends StatelessWidget {
  const _CardChoice({
    super.key,
    required this.card,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.credit_card, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${card.nickname} · ${cardBrandLabel(card.brand)} •••• ${card.last4}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Confirmed extends StatelessWidget {
  const _Confirmed({super.key, required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: scapeDuration(context, const Duration(milliseconds: 420)),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              final scale = 0.72 + (0.28 * value);
              return Opacity(
                opacity: value.clamp(0, 1),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 48, color: scheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Valor reservado',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            GroupMessages.simulatedNotice,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            key: AppKeys.payDone,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
