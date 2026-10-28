import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';

/// Flyer fictício. A arte já traz o texto. Não há desconto de verdade.
class PromoFlyer {
  const PromoFlyer({
    required this.id,
    required this.title,
    required this.asset,
  });

  final String id;
  final String title;
  final String asset;
}

const promoFlyers = <PromoFlyer>[
  PromoFlyer(
    id: 'promo-quarta',
    title: '2 por 1 às quartas',
    asset: 'assets/images/promos/promo-quarta.jpg',
  ),
  PromoFlyer(
    id: 'promo-dez',
    title: '10% off no primeiro jogo',
    asset: 'assets/images/promos/promo-dez.jpg',
  ),
  PromoFlyer(
    id: 'promo-combo',
    title: 'Combo grupo de 6',
    asset: 'assets/images/promos/promo-combo.jpg',
  ),
  PromoFlyer(
    id: 'promo-sexta',
    title: 'Sexta do terror',
    asset: 'assets/images/promos/promo-sexta.jpg',
  ),
];

/// Promoções sem página própria: título curto, flyer, setas e pontos.
class PromoCarousel extends StatelessWidget {
  const PromoCarousel({super.key});

  static const gap = 12.0;
  static const preferredItemWidth = carouselPreferredItemWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: AppKeys.promoCarousel,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Promoções',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final layout = CarouselLayout.fit(
              viewport: constraints.maxWidth,
              itemCount: promoFlyers.length,
              gap: gap,
              preferredItemWidth: preferredItemWidth,
            );
            final height = layout.itemWidth * 9 / 16;
            return ArrowCarousel(
              id: 'promos',
              height: height,
              itemCount: promoFlyers.length,
              gap: gap,
              preferredItemWidth: preferredItemWidth,
              showDots: true,
              itemBuilder: (context, index) {
                final flyer = promoFlyers[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    flyer.asset,
                    width: double.infinity,
                    height: height,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    semanticLabel: flyer.title,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
