import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';

/// A Home abre na lista. O mapa é a outra face da mesma cidade.
enum HomeSurface { list, map }

class HomeSurfaceController extends Notifier<HomeSurface> {
  @override
  HomeSurface build() => HomeSurface.list;

  void show(HomeSurface value) {
    if (state == value) {
      return;
    }
    state = value;
  }
}

final homeSurfaceProvider =
    NotifierProvider<HomeSurfaceController, HomeSurface>(
      HomeSurfaceController.new,
    );

class HomeSurfaceToggle extends ConsumerWidget {
  const HomeSurfaceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(homeSurfaceProvider);
    final scheme = Theme.of(context).colorScheme;
    return SegmentedButton<HomeSurface>(
      key: AppKeys.homeSurfaceToggle,
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
      ),
      segments: const [
        ButtonSegment<HomeSurface>(
          value: HomeSurface.list,
          label: Text(LiveMapMessages.list),
        ),
        ButtonSegment<HomeSurface>(
          value: HomeSurface.map,
          label: Text(LiveMapMessages.map),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (value) {
        ref.read(homeSurfaceProvider.notifier).show(value.first);
      },
    );
  }
}
