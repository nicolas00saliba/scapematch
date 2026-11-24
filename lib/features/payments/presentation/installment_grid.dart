import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/features/payments/domain/card_installments.dart';

/// Grade de parcelas no estilo de uma loja: um card por opção.
class InstallmentGrid extends StatelessWidget {
  const InstallmentGrid({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<CardInstallmentOption> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        final gap = 8.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in options)
              SizedBox(
                width: width,
                child: _InstallmentCard(
                  key: ValueKey('parcela-${option.count}'),
                  option: option,
                  selected: option.enabled && option.count == selected,
                  onTap: option.enabled ? () => onSelect(option.count) : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CardInstallmentOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const freeFill = Color(0xFF1E7046);
    final enabled = option.enabled;
    final title = option.count == 1 ? 'À vista' : '${option.count}x';
    final parcel = formatPrice(option.installmentCents);
    final reason = enabled ? null : option.disabledReason;
    final label = StringBuffer(title)
      ..write(', ')
      ..write(parcel);
    if (option.showsTotal) {
      label.write(', total ${formatPrice(option.totalCents)}');
    }
    if (enabled && option.interestFree) label.write(', sem juros');
    if (enabled && !option.interestFree) label.write(', com juros');
    if (reason != null) label.write(', $reason');
    if (selected) label.write(', selecionado');

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label.toString(),
      child: ExcludeSemantics(
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: enabled
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle,
                            size: 20,
                            color: scheme.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.count == 1 ? parcel : '$title de $parcel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (option.showsTotal) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Total ${formatPrice(option.totalCents)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (enabled)
                      _Badge(
                        text: option.interestFree ? 'sem juros' : 'com juros',
                        background: option.interestFree
                            ? freeFill
                            : scheme.surfaceContainerHighest,
                        foreground: option.interestFree
                            ? Colors.white
                            : scheme.onSurfaceVariant,
                        strong: option.interestFree,
                      )
                    else
                      Text(
                        reason ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
    required this.strong,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: strong ? 10 : 8,
          vertical: strong ? 6 : 3,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: foreground,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            fontSize: strong ? 14 : 12,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
