import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';

/// Sala aberta a partir do cartão. A capa continua o voo do Hero.
class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return rooms.when(
      loading: () =>
          const AppScaffold(body: LoadingView(message: 'Carregando sala...')),
      error: (error, stackTrace) => AppScaffold(
        body: ErrorView(
          message: 'Não foi possível carregar esta sala.',
          onRetry: () => ref.invalidate(roomCatalogViewModelProvider),
        ),
      ),
      data: (listings) {
        RoomListing? listing;
        for (final item in listings) {
          if (item.room.id == roomId) {
            listing = item;
            break;
          }
        }
        if (listing == null) {
          return const AppScaffold(
            body: EmptyView(
              title: 'Sala não encontrada',
              message: 'Essa sala não está no catálogo desta cidade.',
              icon: Icons.meeting_room_outlined,
            ),
          );
        }
        return _RoomDetail(listing: listing);
      },
    );
  }
}

class _RoomDetail extends StatelessWidget {
  const _RoomDetail({required this.listing});

  final RoomListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = listing.room;
    final photos = roomGallery(room.category);
    return AppScaffold(
      body: ListView(
        key: AppKeys.roomDetail(room.id),
        padding: EdgeInsets.zero,
        children: [
          Hero(
            tag: roomHeroTag(room.id),
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                height: 280,
                child: ScapePhoto(
                  asset: photos.first,
                  semanticLabel: room.name,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${listing.houseName} · ${listing.cityName}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(room.theme, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text(
                  '${room.durationMinutes} min · até ${room.capacity} pessoas · ${formatPrice(room.priceCents)} por pessoa',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Fotos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  key: AppKeys.roomGallery,
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 148,
                          child: ScapePhoto(
                            asset: photos[index],
                            semanticLabel: '${room.name}, foto ${index + 1}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: AppKeys.roomFindGroup(room.id),
                  onPressed: () => context.push('/rooms/${room.id}/groups'),
                  child: const Text('Achar grupo'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: AppKeys.roomCreateGroup(room.id),
                  onPressed: () =>
                      context.push('/groups/new?roomId=${room.id}'),
                  child: const Text('Criar grupo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
