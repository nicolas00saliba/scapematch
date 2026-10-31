import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/arrow_carousel.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_photo.dart';

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
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.onTertiary),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.local_offer_outlined,
                  size: 16,
                  color: theme.colorScheme.onTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Promoções',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
                return PressableScale(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: ScapePhoto(
                      asset: flyer.asset,
                      semanticLabel: flyer.title,
                    ),
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
