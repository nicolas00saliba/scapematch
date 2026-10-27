import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/relative_time.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/presentation/news_artwork.dart';
import 'package:scapematch/features/news/presentation/news_labels.dart';

/// Cartão do feed: imagem, selo, casa, tempo, título e resumo curto.
class NewsCard extends StatelessWidget {
  const NewsCard({
    super.key,
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
    final source = newsSourceLabel(item.sourceKind);

    return Semantics(
      button: true,
      identifier: 'news-card-${item.id}',
      label:
          '${newsCategoryLabel(item.category)}. ${item.title}. ${item.houseName}. $when.',
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: AppKeys.newsCard(item.id),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NewsArtwork(image: item.image, category: item.category),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.houseName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$when · $source',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        height: 1.35,
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
}
