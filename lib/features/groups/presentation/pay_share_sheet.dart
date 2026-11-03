import 'dart:math' as math;

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/payments/domain/payment_method.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Cartão de teste. Não pede número, validade nem CVV.
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
  required Future<bool> Function(PaymentMethodKind kind) onPay,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return PayShareSheet(
        amountCents: amountCents,
        reference: reference,
        onPay: onPay,
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
  });

  final int amountCents;
  final String reference;
  final Future<bool> Function(PaymentMethodKind kind) onPay;

  @override
  ConsumerState<PayShareSheet> createState() => _PayShareSheetState();
}

class _PayShareSheetState extends ConsumerState<PayShareSheet> {
  var _method = PaymentMethodKind.pix;
  var _busy = false;
  var _done = false;
  var _copied = false;
  String? _cardId = payTestCard.id;

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

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final ok = await widget.onPay(_method);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _done = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height;
    final saved = ref.watch(paymentMethodsProvider).asData?.value ?? const [];
    final cards = [payTestCard, ...saved];
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
                              onSelect: (id) => setState(() => _cardId = id),
                            ),
                    ),
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
        const _FakeQr(size: 168),
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
    required this.onSelect,
  });

  final List<PaymentMethod> cards;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escolha um cartão. Esta tela não pede número nem código de segurança.',
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
            tween: Tween(begin: 0.6, end: 1),
            duration: scapeDuration(context, const Duration(milliseconds: 420)),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
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
            'Pagamento confirmado',
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

/// Grade fictícia no formato de um QR. Não é um código que um banco lê.
class _FakeQr extends StatelessWidget {
  const _FakeQr({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final paper = Theme.of(context).colorScheme.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: CustomPaint(
          size: Size.square(size),
          painter: _QrPainter(ink: ink, paper: paper),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.ink, required this.paper});

  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 25;
    final cell = size.width / cells;
    final paint = Paint()..color = ink;
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        if (_finder(x, y, cells) || _module(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell - 0.4, cell - 0.4),
            paint,
          );
        }
      }
    }
  }

  bool _finder(int x, int y, int cells) {
    return _eye(x, y) || _eye(x - (cells - 7), y) || _eye(x, y - (cells - 7));
  }

  bool _eye(int x, int y) {
    if (x < 0 || y < 0 || x > 6 || y > 6) {
      return false;
    }
    final edge = x == 0 || y == 0 || x == 6 || y == 6;
    final core = x >= 2 && x <= 4 && y >= 2 && y <= 4;
    return edge || core;
  }

  bool _module(int x, int y) {
    if (x < 8 && y < 8) {
      return false;
    }
    if (x > 16 && y < 8) {
      return false;
    }
    if (x < 8 && y > 16) {
      return false;
    }
    return math.sin(x * 12.9898 + y * 78.233).abs() > 0.45;
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.paper != paper;
}
