import 'package:flutter/material.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:scapematch/features/news/presentation/news_labels.dart';

/// Foto fictícia, URL http(s) ou ilustração desenhada no código.
///
/// O cartão e o detalhe usam este widget. Trocar a origem da imagem não
/// muda a tela que chama. O arquivo já vem perto de 800 px; [cacheWidth]
/// evita decodificar maior do que a tela precisa.
class NewsArtwork extends StatelessWidget {
  const NewsArtwork({
    super.key,
    required this.image,
    required this.category,
    required this.semanticLabel,
    this.illustration = NewsIllustration.category,
  });

  final String? image;
  final NewsCategory category;

  /// Texto de acessibilidade desta figura. Cada notícia manda o próprio,
  /// em geral o título.
  final String semanticLabel;

  final NewsIllustration illustration;

  /// Largura de decode, alinhada ao JPEG de cerca de 800 px.
  static const decodeWidth = 800;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _picture(),
          Positioned(
            left: 12,
            top: 12,
            child: NewsCategoryBadge(category: category),
          ),
        ],
      ),
    );
  }

  Widget _picture() {
    final path = image;
    if (path != null && path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) => _generated(),
      );
    }
    if (path != null &&
        (path.startsWith('https://') || path.startsWith('http://'))) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) => _generated(),
      );
    }
    return _generated();
  }

  Widget _generated() {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: _GeneratedArtwork(
          category: category,
          illustration: illustration,
        ),
      ),
    );
  }
}

class NewsCategoryBadge extends StatelessWidget {
  const NewsCategoryBadge({super.key, required this.category});

  final NewsCategory category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        newsCategoryLabel(category),
        style: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _GeneratedArtwork extends StatelessWidget {
  const _GeneratedArtwork({required this.category, required this.illustration});

  final NewsCategory category;
  final NewsIllustration illustration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fundo e tinta são um par do esquema, para o texto continuar legível
    // no claro e no escuro. Um degradê misturaria pares que não contrastam.
    final (color, icon, ink) = switch (illustration) {
      NewsIllustration.coffee => (
        scheme.secondary,
        Icons.coffee,
        scheme.onSecondary,
      ),
      NewsIllustration.category => switch (category) {
        NewsCategory.newRoom => (
          scheme.primary,
          Icons.meeting_room_outlined,
          scheme.onPrimary,
        ),
        NewsCategory.schedule => (
          scheme.primaryContainer,
          Icons.schedule,
          scheme.onPrimaryContainer,
        ),
        NewsCategory.promotion => (
          scheme.tertiary,
          Icons.local_offer_outlined,
          scheme.onTertiary,
        ),
        NewsCategory.event => (
          scheme.secondaryContainer,
          Icons.celebration_outlined,
          scheme.onSecondaryContainer,
        ),
      },
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: Stack(
        children: [
          Center(child: Icon(icon, color: ink, size: 42)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              'Ilustração fictícia',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
