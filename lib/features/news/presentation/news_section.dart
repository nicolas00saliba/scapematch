import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/presentation/news_card.dart';
import 'package:scapematch/features/news/presentation/news_feed_view_model.dart';
import 'package:scapematch/features/news/presentation/news_labels.dart';
import 'package:scapematch/providers/repositories.dart';

/// Feed de novidades, logo abaixo da busca de grupos.
class NewsSection extends ConsumerWidget {
  const NewsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cityId = ref.watch(selectedCityIdProvider);
    final category = ref.watch(newsCategoryProvider);
    final news = ref.watch(newsFeedViewModelProvider);
    final now = ref.watch(clockProvider).now();
    final cityName = _cityName(ref, cityId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Novidades',
          key: AppKeys.newsFeed,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Salas, horários, promoções e eventos da cidade.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              key: AppKeys.newsCategoryAll,
              label: const Text('Todas'),
              selected: category == null,
              onSelected: (_) {
                ref.read(newsCategoryProvider.notifier).select(null);
              },
            ),
            for (final item in NewsCategory.values)
              FilterChip(
                key: AppKeys.newsCategory(item.name),
                label: Text(newsCategoryLabel(item)),
                selected: category == item,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(newsCategoryProvider.notifier).select(item);
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        _body(context, ref, cityId, cityName, category, news, now),
      ],
    );
  }

  String? _cityName(WidgetRef ref, String? cityId) {
    if (cityId == null) {
      return null;
    }
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

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    String? cityId,
    String? cityName,
    NewsCategory? category,
    AsyncValue<List<NewsItem>> news,
    DateTime now,
  ) {
    if (cityId == null) {
      return const InlineNotice(
        message: 'Escolha a cidade acima para ver as novidades.',
      );
    }

    return news.when(
      loading: () =>
          const InlineNotice(message: 'Carregando novidades...', loading: true),
      error: (error, stackTrace) => InlineNotice(
        message: 'Não foi possível carregar as novidades.',
        actionKey: AppKeys.newsRetry,
        actionLabel: 'Tentar de novo',
        onAction: () => ref.invalidate(newsFeedViewModelProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          final place = cityName ?? 'esta cidade';
          final message = category == null
              ? 'Ainda não há novidades de exemplo em $place.'
              : 'Nenhuma novidade de ${newsCategoryLabel(category).toLowerCase()} em $place.';
          return InlineNotice(message: message);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              NewsCard(
                item: items[index],
                now: now,
                onTap: () => context.push('/news/${items[index].id}'),
              ),
            ],
          ],
        );
      },
    );
  }
}
