import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';

/// Chips de tipo de jogo. Os mesmos da introdução e do mapa.
///
/// [scrollable] rola na horizontal, para a faixa caber no celular.
/// Sem isso, os chips quebram linha, como na introdução.
class GameTypeChips extends ConsumerWidget {
  const GameTypeChips({super.key, this.scrollable = false});

  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedGameTypeIdProvider);
    final chips = [
      for (final choice in GameTypes.choices)
        ChoiceChip(
          key: AppKeys.gameTypeOption(choice.id),
          label: Text(choice.shortLabel),
          selected: selected == choice.id,
          onSelected: (_) {
            ref.read(selectedGameTypeIdProvider.notifier).select(choice.id);
          },
        ),
    ];
    if (!scrollable) {
      return Wrap(spacing: 8, runSpacing: 8, children: chips);
    }
    return SizedBox(
      height: 40,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < chips.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                chips[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
