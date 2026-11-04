import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/player_range.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

/// Sala aberta a partir do cartão. A capa continua o voo do Hero.
class RoomDetailScreen extends ConsumerWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return rooms.when(
      loading: () => AppScaffold(
        appBar: AppBar(
          leading: const ScapeBackButton(),
          title: const Text('Sala'),
        ),
        body: const LoadingView(message: 'Carregando sala...'),
      ),
      error: (error, stackTrace) => AppScaffold(
        appBar: AppBar(leading: ScapeBackButton(), title: Text('Sala')),
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
          return AppScaffold(
            appBar: AppBar(
              leading: const ScapeBackButton(),
              title: const Text('Sala'),
            ),
            body: const EmptyView(
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
    final desktop = isScapeDesktop(context);
    final story = _story(context, wideGallery: desktop, actions: !desktop);
    if (!desktop) {
      return AppScaffold(body: story);
    }
    return AppScaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: story),
          SizedBox(
            width: 340,
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 24, 4, 28),
                child: _actionCard(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _story(
    BuildContext context, {
    required bool wideGallery,
    required bool actions,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = listing.room;
    final heroFrame = wideGallery ? RoomFrame.heroWide : RoomFrame.hero;
    final thumbFrame = wideGallery ? RoomFrame.galleryWide : RoomFrame.gallery;
    final heroBytes = room.pictureBytes(heroFrame);
    final shots = _gallery(room, thumbFrame);
    return ListView(
      key: AppKeys.roomDetail(room.id),
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: heroFrame.height.toDouble(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: roomHeroTag(room.id),
                child: Material(
                  type: MaterialType.transparency,
                  child: ScapePhoto(
                    bytes: heroBytes,
                    asset: heroBytes == null ? roomCategoryImage(room.category) : '',
                    semanticLabel: room.name,
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                top: 0,
                child: ScapeCoverBackButton(),
              ),
            ],
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
                GroupMessages.roomBounds(
                  minimum: room.minimumPlayers,
                  maximum: room.capacity,
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
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
                '${room.durationMinutes} min · ${playerRangeLabel(minimum: room.minimumPlayers, maximum: room.capacity)} · ${formatPrice(room.priceCents)} por pessoa',
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
              if (wideGallery)
                Wrap(
                  key: AppKeys.roomGallery,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final shot in shots)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: thumbFrame.width.toDouble(),
                          height: thumbFrame.height.toDouble(),
                          child: shot,
                        ),
                      ),
                  ],
                )
              else
                SizedBox(
                  key: AppKeys.roomGallery,
                  height: thumbFrame.height.toDouble(),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: shots.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: thumbFrame.width.toDouble(),
                          child: shots[index],
                        ),
                      );
                    },
                  ),
                ),
              if (actions) ...[
                const SizedBox(height: 20),
                _actions(context),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _gallery(EscapeRoom room, RoomFrame frame) {
    final pictures = room.pictures;
    if (pictures.isEmpty) {
      final assets = roomGallery(room.category);
      return [
        for (var index = 0; index < assets.length; index++)
          ScapePhoto(
            asset: assets[index],
            semanticLabel: '${room.name}, foto ${index + 1}',
          ),
      ];
    }
    return [
      for (var index = 0; index < pictures.length; index++)
        ScapePhoto(
          bytes: pictures[index].bytesFor(frame),
          semanticLabel: '${room.name}, foto ${index + 1}',
        ),
    ];
  }

  Widget _actionCard(BuildContext context) {
    final theme = Theme.of(context);
    final room = listing.room;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              listing.houseName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPrice(room.priceCents)} por pessoa',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final room = listing.room;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: AppKeys.roomFindGroup(room.id),
          onPressed: () => context.push('/rooms/${room.id}/groups'),
          child: const Text('Achar grupo'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: AppKeys.roomCreateGroup(room.id),
          onPressed: () => context.push('/groups/new?roomId=${room.id}'),
          child: const Text('Criar grupo'),
        ),
      ],
    );
  }
}
