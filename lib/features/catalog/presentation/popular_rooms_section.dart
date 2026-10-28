import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/popular_rooms.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';

/// Carrossel terciário de descoberta, no lugar da lista vertical de grupos.
class PopularRoomsSection extends ConsumerWidget {
  const PopularRoomsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return rooms.maybeWhen(
      data: (listings) {
        final popular = rankPopularRooms(listings);
        if (popular.isEmpty) {
          return const SizedBox.shrink();
        }
        return _PopularCarousel(rooms: popular);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PopularCarousel extends StatelessWidget {
  const _PopularCarousel({required this.rooms});

  final List<RoomListing> rooms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = rooms
        .map((listing) => roomCardHeight(context, listing))
        .reduce(math.max)
        .ceilToDouble();
    return Column(
      key: AppKeys.popularRooms,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Salas mais procuradas',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              key: AppKeys.popularSeeAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(40, 40),
              ),
              onPressed: () => context.push('/rooms/popular'),
              child: const Text('Ver tudo'),
            ),
          ],
        ),
        ArrowCarousel(
          id: 'popular',
          height: height,
          itemCount: rooms.length,
          itemBuilder: (context, index) => RoomCard(listing: rooms[index]),
        ),
      ],
    );
  }
}
