import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';

/// Salas da cidade que combinam com o tipo de jogo. [GameTypes.all] mostra todas.
List<RoomListing> filterRoomsByGameType(
  List<RoomListing> listings,
  String gameTypeId,
) {
  if (gameTypeId == GameTypes.all) {
    return listings;
  }
  return [
    for (final listing in listings)
      if (listing.room.gameType == gameTypeId) listing,
  ];
}

/// Um único carrossel de salas. Cada cartão cria grupo ou acha um já aberto.
class RoomsCarousel extends ConsumerWidget {
  const RoomsCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rooms = ref.watch(roomCatalogViewModelProvider);
    final gameTypeId = ref.watch(selectedGameTypeIdProvider);

    return Column(
      key: AppKeys.roomsCarousel,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Salas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        rooms.when(
          skipLoadingOnReload: true,
          loading: () =>
              const InlineNotice(message: 'Carregando salas...', loading: true),
          error: (error, stackTrace) => InlineNotice(
            message: 'Não foi possível carregar as salas.',
            actionLabel: 'Tentar de novo',
            onAction: () => ref.invalidate(roomCatalogViewModelProvider),
          ),
          data: (listings) {
            final filtered = filterRoomsByGameType(listings, gameTypeId);
            if (filtered.isEmpty) {
              final kind = gameTypeId == GameTypes.all
                  ? ''
                  : ' de ${GameTypes.labelOf(gameTypeId)}';
              return InlineNotice(
                message: 'Ainda não há salas de exemplo$kind nesta cidade.',
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final layout = CarouselLayout.fit(
                  viewport: constraints.maxWidth,
                  itemCount: filtered.length,
                  preferredItemWidth: carouselPreferredItemWidth,
                );
                final height = filtered
                    .map(
                      (listing) => roomCardHeight(
                        context,
                        listing,
                        width: layout.itemWidth,
                      ),
                    )
                    .reduce(math.max)
                    .ceilToDouble();
                return ArrowCarousel(
                  id: 'rooms',
                  height: height,
                  itemCount: filtered.length,
                  preferredItemWidth: carouselPreferredItemWidth,
                  itemBuilder: (context, index) {
                    return StaggerIn(
                      index: index,
                      child: RoomCard(listing: filtered[index]),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}
