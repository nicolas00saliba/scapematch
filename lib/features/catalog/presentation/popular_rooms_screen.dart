import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/catalog/presentation/popular_rooms.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';

/// Lista vertical do ranking fictício de procura.
class PopularRoomsScreen extends ConsumerWidget {
  const PopularRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return AppScaffold(
      appBar: AppBar(title: const Text('Salas mais procuradas')),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Não foi possível carregar as salas.')),
        data: (listings) {
          final popular = rankPopularRooms(listings);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const ExampleDataBanner(),
              const SizedBox(height: 12),
              Text(
                'Ranking fictício de procura nesta cidade.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < popular.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                RoomCard(listing: popular[index]),
              ],
            ],
          );
        },
      ),
    );
  }
}
