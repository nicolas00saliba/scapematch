import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/relative_time.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/presentation/news_artwork.dart';
import 'package:scapematch/providers/repositories.dart';

/// Novidades da cidade, sem o filtro de chip. O chip fica em “Ver tudo”.
final homeNewsProvider = FutureProvider.autoDispose<List<NewsItem>>((ref) {
  final cityId = ref.watch(selectedCityIdProvider);
  return ref.watch(newsRepositoryProvider).list(cityId: cityId);
});

/// Altura da foto no carrossel primário. O valor deixa a faixa inteira na
/// primeira tela de 390×844 e corta o tema seguinte.
const newsCarouselImageHeight = 280.0;
const newsCarouselCardWidth = 340.0;

double newsCarouselCardHeight(BuildContext context) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  const width = newsCarouselCardWidth;
  const pad = 12.0;
  final contentWidth = width - pad * 2;
  final titleStyle = theme.textTheme.titleSmall!.copyWith(
    fontWeight: FontWeight.w800,
    height: 1.2,
  );
  // A amostra curta cabe em uma linha e a altura vinha menor que o título
  // real. Duas linhas ficam reservadas em qualquer textScale.
  final title = _lineHeight('Ag', titleStyle, scaler, contentWidth, 1) * 2;
  final meta = _lineHeight(
    'Portal do Batel',
    theme.textTheme.labelMedium!,
    scaler,
    contentWidth,
    1,
  );
  final when = _lineHeight(
    'há 30 min',
    theme.textTheme.bodySmall!,
    scaler,
    contentWidth,
    1,
  );
  return (newsCarouselImageHeight + 8 + meta + 4 + title + 2 + when + pad)
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

/// Carrossel primário da Home.
class NewsSection extends ConsumerWidget {
  const NewsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final news = ref.watch(homeNewsProvider);
    final now = ref.watch(clockProvider).now();
    final cardHeight = newsCarouselCardHeight(context);

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
              return const InlineNotice(
                message: 'Ainda não há novidades de exemplo nesta cidade.',
              );
            }
            final height = cardHeight < 120 ? 120.0 : cardHeight;
            return ArrowCarousel(
              id: 'news',
              height: height,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _NewsStripCard(
                  item: item,
                  now: now,
                  height: height,
                  onTap: () => context.push('/news/${item.id}'),
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
    required this.height,
    required this.onTap,
  });

  final NewsItem item;
  final DateTime now;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = formatRelativeTime(publishedAt: item.publishedAt, now: now);
    return SizedBox(
      width: newsCarouselCardWidth,
      height: height,
      child: Card(
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
                    Text(
                      item.houseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      when,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
