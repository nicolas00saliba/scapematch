import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/catalog/presentation/room_carousels_section.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';

/// Tela inicial: busca de grupo em cima, feed de novidades embaixo.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeHeader(),
            SizedBox(height: 16),
            CitySelector(),
            SizedBox(height: 12),
            ExampleDataBanner(),
            SizedBox(height: 16),
            FindGroupsSection(),
            SizedBox(height: 22),
            RoomCarouselsSection(),
            SizedBox(height: 22),
            NewsSection(),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ScapeMatch',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Grupos, salas e novidades de escape room na sua cidade.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.muted,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
