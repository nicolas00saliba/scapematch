import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/features/theme/domain/theme_choice.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_controller.dart';

/// Claro, escuro ou automático, no mesmo controle.
class ThemeChoiceControl extends ConsumerWidget {
  const ThemeChoiceControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final choice = ref.watch(themeChoiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aparência',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Claro, escuro ou o tema do aparelho. A escolha fica neste aparelho.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final option in ThemeChoice.values)
                  Expanded(
                    child: _ThemeSegment(
                      option: option,
                      selected: option == choice,
                      onTap: () =>
                          ref.read(themeChoiceProvider.notifier).select(option),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ThemeChoice option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: option.labelPt,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: AppKeys.themeChoice(option.name),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: scapeDuration(context, const Duration(milliseconds: 220)),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Icon(option.icon, size: 22, color: foreground),
                const SizedBox(height: 4),
                Text(
                  option.labelPt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
