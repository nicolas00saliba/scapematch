import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/catalog/presentation/rooms_carousel.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/groups/presentation/game_type_selector.dart';
import 'package:scapematch/features/map/presentation/home_surface.dart';
import 'package:scapematch/features/map/presentation/live_map_view.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

/// Home: lista da cidade, ou o mapa ao vivo com a gaveta de grupos.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(homeSurfaceProvider) == HomeSurface.map) {
      return const LiveMapView();
    }
    return const AppScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeHeader(),
            SizedBox(height: 8),
            HomeSurfaceToggle(),
            SizedBox(height: 6),
            ExampleDataBanner(),
            SizedBox(height: 6),
            FindGroupsSection(),
            SizedBox(height: 12),
            PromoCarousel(),
            SizedBox(height: 12),
            NewsSection(),
            SizedBox(height: 12),
            RoomsCarousel(),
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
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'ScapeMatch',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // A cidade encolhe com reticências. O jogo fica da largura do rótulo.
        const Expanded(child: CitySelector(compact: true)),
        const SizedBox(width: 8),
        const GameTypeSelector(),
      ],
    );
  }
}
