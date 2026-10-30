import 'package:flutter/material.dart';

/// Foto local. Enquanto o arquivo não entra, fica um bloco de cor.
class ScapePhoto extends StatelessWidget {
  const ScapePhoto({
    super.key,
    required this.asset,
    this.semanticLabel,
    this.fit = BoxFit.cover,
  });

  final String asset;
  final String? semanticLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Image.asset(
        asset,
        fit: fit,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          final ready = wasSynchronouslyLoaded || frame != null;
          return Stack(
            fit: StackFit.expand,
            children: [
              _PhotoPlaceholder(color: scheme.primaryContainer),
              if (ready) child,
            ],
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _PhotoPlaceholder(color: scheme.primaryContainer);
        },
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, scheme.secondaryContainer],
        ),
      ),
    );
  }
}
