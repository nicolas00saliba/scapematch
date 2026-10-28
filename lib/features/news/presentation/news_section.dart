import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/relative_time.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/domain/news_query.dart';
import 'package:scapematch/features/news/presentation/news_artwork.dart';
import 'package:scapematch/providers/repositories.dart';

/// Novidades da cidade e do tipo de jogo. O chip de categoria fica em “Ver tudo”.
final homeNewsProvider = FutureProvider.autoDispose<List<NewsItem>>((
  ref,
) async {
  final cityId = ref.watch(selectedCityIdProvider);
  final gameTypeId = ref.watch(selectedGameTypeIdProvider);
  final items = await ref.watch(newsRepositoryProvider).list(cityId: cityId);
  return filterNewsByGameType(items, gameTypeId);
});

/// Foto do cartão. O texto embaixo é que precisa ser lido.
const newsCarouselImageHeight = 112.0;

double newsCarouselCardHeight(BuildContext context, double cardWidth) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final contentWidth = math.max(40.0, cardWidth - 24);
  final chip = _lineHeight(
    'Jogos de tabuleiro',
    _chipStyle(theme),
    scaler,
    contentWidth,
    1,
  );
  final title = _lineHeight('Ag', _titleStyle(theme), scaler, contentWidth, 1);
  final summary = _lineHeight(
    'Ag',
    _summaryStyle(theme),
    scaler,
    contentWidth,
    1,
  );
  final when = _lineHeight(
    'há 30 min · 27 out',
    _whenStyle(theme),
    scaler,
    contentWidth,
    1,
  );
  return (newsCarouselImageHeight +
          8 +
          chip +
          6 +
          8 +
          (title * 2) +
          4 +
          (summary * 2) +
          4 +
          when +
          12)
      .ceilToDouble();
}

double _lineHeight(
  String sample,
  TextStyle style,
  TextScaler scaler,
  double maxWidth,
  int maxLines,
) {
  final painter = TextPainter(
    text: TextSpan(text: sample, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

TextStyle _titleStyle(ThemeData theme) {
  return theme.textTheme.titleSmall!.copyWith(
    fontWeight: FontWeight.w800,
    height: 1.2,
  );
}

TextStyle _summaryStyle(ThemeData theme) {
  return theme.textTheme.bodyMedium!.copyWith(
    color: AppColors.muted,
    height: 1.35,
  );
}

TextStyle _whenStyle(ThemeData theme) {
  return theme.textTheme.bodySmall!.copyWith(color: AppColors.muted);
}

TextStyle _chipStyle(ThemeData theme) {
  return theme.textTheme.labelMedium!.copyWith(
    color: AppColors.teal,
    fontWeight: FontWeight.w800,
  );
}

/// Carrossel de novidades da Home.
class NewsSection extends ConsumerWidget {
  const NewsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final news = ref.watch(homeNewsProvider);
    final now = ref.watch(clockProvider).now();
    final gameTypeId = ref.watch(selectedGameTypeIdProvider);

    return Column(
      key: AppKeys.newsFeed,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Novidades',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              key: AppKeys.newsSeeAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: const Size(40, 40),
              ),
              onPressed: () => context.push('/news'),
              child: const Text('Ver tudo'),
            ),
          ],
        ),
        news.when(
          skipLoadingOnReload: true,
          loading: () => const InlineNotice(
            message: 'Carregando novidades...',
            loading: true,
          ),
          error: (error, stackTrace) => InlineNotice(
            message: 'Não foi possível carregar as novidades.',
            actionKey: AppKeys.newsRetry,
            actionLabel: 'Tentar de novo',
            onAction: () => ref.invalidate(homeNewsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              final kind = gameTypeId == GameTypes.all
                  ? ''
                  : ' de ${GameTypes.labelOf(gameTypeId)}';
              return InlineNotice(
                message: 'Ainda não há novidades de exemplo$kind nesta cidade.',
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final layout = CarouselLayout.fit(
                  viewport: constraints.maxWidth,
                  itemCount: items.length,
                  preferredItemWidth: carouselPreferredItemWidth,
                );
                final height = math.max(
                  160.0,
                  newsCarouselCardHeight(context, layout.itemWidth),
                );
                return ArrowCarousel(
                  id: 'news',
                  height: height,
                  itemCount: items.length,
                  preferredItemWidth: carouselPreferredItemWidth,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _NewsStripCard(
                      item: item,
                      now: now,
                      onTap: () => context.push('/news/${item.id}'),
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

class _NewsStripCard extends StatelessWidget {
  const _NewsStripCard({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final NewsItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = formatRelativeTime(publishedAt: item.publishedAt, now: now);
    final date = formatShortDate(item.publishedAt);
    final genre = GameTypes.labelOf(item.gameType);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: AppKeys.newsCard(item.id),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: newsCarouselImageHeight,
              width: double.infinity,
              child: Image(
                image: _image(item),
                fit: BoxFit.cover,
                semanticLabel: item.title,
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: AppColors.tealSoft),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(genre, style: _chipStyle(theme)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(theme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _summaryStyle(theme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$when · $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _whenStyle(theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider _image(NewsItem item) {
    final path = item.image;
    if (path != null && path.startsWith('assets/')) {
      return ResizeImage(AssetImage(path), width: NewsArtwork.decodeWidth);
    }
    return const AssetImage('assets/images/news/grupo.jpg');
  }
}
