import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/presentation/rooms_carousel.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/groups/presentation/game_type_selector.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

/// Home: cidade e jogo, grupos, promoções, novidades e um carrossel de salas.
/// No site, promoções e novidades ficam lado a lado e os grupos viram grade.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final desktop = isScapeDesktop(context);
    return AppScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeHeader(showWordmark: !desktop),
            const SizedBox(height: 6),
            const ExampleDataBanner(),
            const SizedBox(height: 6),
            const FindGroupsSection(),
            const SizedBox(height: 12),
            if (desktop)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: PromoCarousel()),
                  SizedBox(width: 20),
                  Expanded(child: NewsSection()),
                ],
              )
            else ...const [
              PromoCarousel(),
              SizedBox(height: 12),
              NewsSection(),
            ],
            const SizedBox(height: 12),
            const RoomsCarousel(),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.showWordmark});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showWordmark) ...const [
          ScapeLogo(variant: ScapeLogoVariant.mark, height: 28),
          SizedBox(width: 8),
        ],
        // A cidade encolhe com reticências. O jogo fica da largura do rótulo.
        const Expanded(child: CitySelector(compact: true)),
        const SizedBox(width: 8),
        const GameTypeSelector(),
      ],
    );
  }
}
