import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/providers/repositories.dart';
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
    asset: 'assets/images/promos/promo-quarta.png',
  ),
  PromoFlyer(
    id: 'promo-dez',
    title: '10% off no primeiro jogo',
    asset: 'assets/images/promos/promo-dez.png',
  ),
  PromoFlyer(
    id: 'promo-combo',
    title: 'Combo grupo de 6',
    asset: 'assets/images/promos/promo-combo.png',
  ),
  PromoFlyer(
    id: 'promo-sexta',
    title: 'Sexta do terror',
    asset: 'assets/images/promos/promo-sexta.png',
  ),
];

/// Flyers fictícios só na demonstração. O modo real não os carrega.
final visiblePromoFlyersProvider = Provider<List<PromoFlyer>>((ref) {
  if (kAllowSampleData && ref.watch(backendPlanProvider).loadsSampleDatabase) {
    return promoFlyers;
  }
  return const [];
});

/// Promoções sem página própria: título curto, flyer, setas e pontos.
class PromoCarousel extends ConsumerWidget {
  const PromoCarousel({super.key});

  static const gap = 12.0;
  static const preferredItemWidth = carouselPreferredItemWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flyers = ref.watch(visiblePromoFlyersProvider);
    if (flyers.isEmpty) return const SizedBox.shrink();
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
              itemCount: flyers.length,
              gap: gap,
              preferredItemWidth: preferredItemWidth,
            );
            final height = layout.itemWidth * 9 / 16;
            return ArrowCarousel(
              id: 'promos',
              height: height,
              itemCount: flyers.length,
              gap: gap,
              preferredItemWidth: preferredItemWidth,
              showDots: true,
              loop: true,
              autoAdvance: true,
              itemBuilder: (context, index) {
                final flyer = flyers[index];
                return PressableScale(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: ScapePhoto(
                      asset: flyer.asset,
                      semanticLabel: flyer.title,
                      // Mestre 1920×1080. Medium reduz o quadro sem borrar.
                      filterQuality: FilterQuality.medium,
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
