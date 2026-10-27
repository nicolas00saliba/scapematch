import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/relative_time.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/presentation/news_artwork.dart';
import 'package:scapematch/features/news/presentation/news_feed_view_model.dart';
import 'package:scapematch/features/news/presentation/news_labels.dart';
import 'package:scapematch/providers/repositories.dart';

class NewsDetailScreen extends ConsumerWidget {
  const NewsDetailScreen({super.key, required this.newsId});

  final String newsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(newsDetailViewModelProvider(newsId));
    final now = ref.watch(clockProvider).now();

    return AppScaffold(
      appBar: AppBar(title: const Text('Novidade')),
      body: detail.when(
        loading: () => const LoadingView(message: 'Carregando a novidade...'),
        error: (error, stackTrace) => ErrorView(
          message: 'Não foi possível abrir a novidade.',
          onRetry: () => ref.invalidate(newsDetailViewModelProvider(newsId)),
        ),
        data: (item) {
          if (item == null) {
            return const EmptyView(
              title: 'Novidade não encontrada',
              message: 'Esse link não aponta para uma notícia de exemplo.',
              icon: Icons.newspaper_outlined,
            );
          }
          return _Detail(item: item, now: now);
        },
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.item, required this.now});

  final NewsItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = formatRelativeTime(publishedAt: item.publishedAt, now: now);
    final source = newsSourceLabel(item.sourceKind);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: NewsArtwork(image: item.image, category: item.category),
        ),
        const SizedBox(height: 16),
        Text(
          item.houseName,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.teal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${item.cityName} · $when · $source',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        Text(
          item.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          item.summary,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
        ),
        if (item.sourceUrl != null) ...[
          const SizedBox(height: 16),
          Text(
            'Link de origem (fictício)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            item.sourceUrl!,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.teal),
          ),
          const SizedBox(height: 4),
          Text(
            'O app mostra o endereço e não abre o navegador.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
        const SizedBox(height: 20),
        const ExampleDataBanner(),
      ],
    );
  }
}
