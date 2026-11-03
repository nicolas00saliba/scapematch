import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/features/catalog/presentation/rooms_carousel.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/groups/presentation/find_groups_section.dart';
import 'package:scapematch/features/groups/presentation/game_type_selector.dart';
import 'package:scapematch/features/news/presentation/news_section.dart';
import 'package:scapematch/features/promos/presentation/promo_carousel.dart';

/// Home: cidade e jogo, grupos, promoções, novidades e um carrossel de salas.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeHeader(),
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
    final wide = MediaQuery.sizeOf(context).width >= scapeWideLogoWidth;
    if (wide) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ScapeLogo(height: 44),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: CitySelector(compact: true)),
              SizedBox(width: 8),
              GameTypeSelector(),
            ],
          ),
        ],
      );
    }
    return const Row(
      children: [
        ScapeLogo(variant: ScapeLogoVariant.mark, height: 28),
        SizedBox(width: 8),
        // A cidade encolhe com reticências. O jogo fica da largura do rótulo.
        Expanded(child: CitySelector(compact: true)),
        SizedBox(width: 8),
        GameTypeSelector(),
      ],
    );
  }
}
