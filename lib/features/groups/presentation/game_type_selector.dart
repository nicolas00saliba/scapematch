import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';

/// Seletor provisório, no mesmo espírito do seletor de cidade compacto.
class GameTypeSelector extends ConsumerWidget {
  const GameTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(selectedGameTypeIdProvider);
    final label = GameTypes.labelOf(selectedId);
    return Semantics(
      button: true,
      label: 'Tipo de jogo selecionado: $label. Toque para trocar.',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.teal),
        ),
        child: InkWell(
          key: AppKeys.gameTypeSelector,
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pick(context, ref, selectedId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.casino_outlined,
                  color: AppColors.teal,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.expand_more, color: AppColors.teal, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    String selectedId,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Tipo de jogo',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final choice in GameTypes.choices)
                ListTile(
                  key: AppKeys.gameTypeOption(choice.$1),
                  title: Text(choice.$2),
                  trailing: choice.$1 == selectedId
                      ? const Icon(Icons.check, color: AppColors.teal)
                      : null,
                  onTap: () => Navigator.of(context).pop(choice.$1),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null) {
      return;
    }
    ref.read(selectedGameTypeIdProvider.notifier).select(picked);
  }
}
