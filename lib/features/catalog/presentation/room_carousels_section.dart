import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';

/// Carrosséis de salas da cidade, um por tema que tenha pelo menos uma sala.
class RoomCarouselsSection extends ConsumerWidget {
  const RoomCarouselsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return rooms.when(
      skipLoadingOnReload: true,
      loading: () =>
          const InlineNotice(message: 'Carregando salas...', loading: true),
      error: (error, stackTrace) => InlineNotice(
        message: 'Não foi possível carregar as salas.',
        actionLabel: 'Tentar de novo',
        onAction: () => ref.invalidate(roomCatalogViewModelProvider),
      ),
      data: (listings) {
        if (listings.isEmpty) {
          return const InlineNotice(
            message: 'Ainda não há salas de exemplo nesta cidade.',
          );
        }
        final sections = <Widget>[];
        for (final category in roomCategoryOrder) {
          final inCategory = [
            for (final listing in listings)
              if (listing.room.category == category) listing,
          ];
          if (inCategory.isEmpty) {
            continue;
          }
          if (sections.isNotEmpty) {
            sections.add(const SizedBox(height: 18));
          }
          sections.add(_Carousel(category: category, rooms: inCategory));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: sections,
        );
      },
    );
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({required this.category, required this.rooms});

  final RoomCategory category;
  final List<RoomListing> rooms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = roomCategoryLabel(category);
    return Column(
      key: AppKeys.roomCarousel(category.name),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              key: AppKeys.roomSeeAll(category.name),
              onPressed: () {
                context.push('/rooms/category/${category.name}');
              },
              child: const Text('Ver tudo'),
            ),
          ],
        ),
        SizedBox(
          height: 360,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rooms.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => RoomCard(listing: rooms[index]),
          ),
        ),
      ],
    );
  }
}
