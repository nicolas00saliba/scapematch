import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';

/// Temas com sala na cidade, na ordem do produto.
List<RoomCategory> visibleRoomCategories(List<RoomListing> listings) {
  return [
    for (final category in roomCategoryOrder)
      if (listings.any((listing) => listing.room.category == category))
        category,
  ];
}

/// Um trecho dos carrosséis de tema.
///
/// [start] é o índice entre os temas visíveis. [count] nulo vai até o fim.
/// Os dois primeiros são secundários; o restante, terciário.
class RoomThemeSpan extends ConsumerWidget {
  const RoomThemeSpan({super.key, required this.start, this.count});

  final int start;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    return rooms.when(
      skipLoadingOnReload: true,
      loading: () => start == 0
          ? const InlineNotice(message: 'Carregando salas...', loading: true)
          : const SizedBox.shrink(),
      error: (error, stackTrace) => start == 0
          ? InlineNotice(
              message: 'Não foi possível carregar as salas.',
              actionLabel: 'Tentar de novo',
              onAction: () => ref.invalidate(roomCatalogViewModelProvider),
            )
          : const SizedBox.shrink(),
      data: (listings) {
        final categories = visibleRoomCategories(listings);
        if (start >= categories.length) {
          return const SizedBox.shrink();
        }
        final end = count == null
            ? categories.length
            : math.min(categories.length, start + count!);
        final slice = categories.sublist(start, end);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < slice.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _ThemeCarousel(
                category: slice[index],
                rooms: [
                  for (final listing in listings)
                    if (listing.room.category == slice[index]) listing,
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeCarousel extends StatelessWidget {
  const _ThemeCarousel({required this.category, required this.rooms});

  final RoomCategory category;
  final List<RoomListing> rooms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = roomCategoryLabel(category);
    final height = rooms
        .map((listing) => roomCardHeight(context, listing))
        .reduce(math.max)
        .ceilToDouble();
    return Column(
      key: AppKeys.roomCarousel(category.name),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              key: AppKeys.roomSeeAll(category.name),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(40, 40),
              ),
              onPressed: () {
                context.push('/rooms/category/${category.name}');
              },
              child: const Text('Ver tudo'),
            ),
          ],
        ),
        ArrowCarousel(
          id: category.name,
          height: height,
          itemCount: rooms.length,
          itemBuilder: (context, index) => RoomCard(listing: rooms[index]),
        ),
      ],
    );
  }
}
