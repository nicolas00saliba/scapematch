import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/providers/repositories.dart';

/// Grupos da cidade que jogam nesta sala.
class RoomGroupsScreen extends ConsumerWidget {
  const RoomGroupsScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(roomListingProvider(roomId));
    final groups = ref.watch(roomGroupsProvider(roomId));
    final title = listing.asData?.value?.room.name ?? 'Grupos da sala';

    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: groups.when(
        skipLoadingOnReload: true,
        loading: () =>
            const LoadingView(message: 'Carregando grupos desta sala...'),
        error: (error, stackTrace) => ErrorView(
          message: 'Não foi possível carregar os grupos desta sala.',
          onRetry: () => ref.invalidate(roomGroupsProvider(roomId)),
        ),
        data: (items) {
          final room = listing.asData?.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const ExampleDataBanner(),
              const SizedBox(height: 12),
              if (room != null)
                Text(
                  '${room.houseName} · ${room.cityName}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                InlineNotice(
                  message: room == null
                      ? 'Essa sala não está no catálogo de exemplo.'
                      : 'Ainda não há grupo nesta sala. Crie um.',
                )
              else
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  GroupCard(
                    group: items[index],
                    onTap: () => context.push('/groups/${items[index].id}'),
                  ),
                ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: AppKeys.roomCreateGroup(roomId),
                onPressed: room == null
                    ? null
                    : () => context.push('/groups/new?roomId=$roomId'),
                icon: const Icon(Icons.add),
                label: const Text('Criar grupo'),
              ),
            ],
          );
        },
      ),
    );
  }
}

final roomListingProvider = FutureProvider.autoDispose
    .family<RoomListing?, String>((ref, roomId) {
      return ref.watch(catalogRepositoryProvider).findRoom(roomId);
    });

final roomGroupsProvider = FutureProvider.autoDispose
    .family<List<Group>, String>((ref, roomId) async {
      final cityId = ref.watch(selectedCityIdProvider);
      final groups = await ref
          .watch(groupRepositoryProvider)
          .listByCity(cityId);
      return [
        for (final group in groups)
          if (group.roomId == roomId) group,
      ];
    });
