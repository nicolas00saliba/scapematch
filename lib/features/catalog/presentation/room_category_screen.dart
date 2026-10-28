import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/presentation/room_card.dart';
import 'package:scapematch/features/catalog/presentation/room_catalog_view_model.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';

/// Todas as salas de um tema na cidade selecionada.
class RoomCategoryScreen extends ConsumerWidget {
  const RoomCategoryScreen({super.key, required this.categoryName});

  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = roomCategoryByName(categoryName);
    final title = category == null ? 'Salas' : roomCategoryLabel(category);
    return AppScaffold(
      appBar: AppBar(title: Text(title)),
      body: category == null
          ? const _Missing(message: 'Esse tema não existe.')
          : _CategoryList(category: category),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.category});

  final RoomCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomCatalogViewModelProvider);
    final cityName = _cityName(ref);
    return rooms.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const _Missing(message: 'Não foi possível carregar as salas.'),
      data: (listings) {
        final inCategory = [
          for (final listing in listings)
            if (listing.room.category == category) listing,
        ];
        if (inCategory.isEmpty) {
          final place = cityName ?? 'esta cidade';
          return _Missing(
            message:
                'Não há salas de ${roomCategoryLabel(category)} em $place.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const ExampleDataBanner(),
            const SizedBox(height: 16),
            Text(
              cityName == null
                  ? 'Salas de exemplo.'
                  : 'Salas de exemplo em $cityName.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < inCategory.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              RoomCard(listing: inCategory[index]),
            ],
          ],
        );
      },
    );
  }

  String? _cityName(WidgetRef ref) {
    final cityId = ref.watch(selectedCityIdProvider);
    final cities = ref.watch(citiesProvider).value;
    if (cities == null) {
      return null;
    }
    for (final city in cities) {
      if (city.id == cityId) {
        return city.name;
      }
    }
    return null;
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
