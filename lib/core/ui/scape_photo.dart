import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Foto local. Enquanto o arquivo não entra, fica um bloco de cor.
class ScapePhoto extends StatelessWidget {
  const ScapePhoto({
    super.key,
    this.asset = '',
    this.bytes,
    this.semanticLabel,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String asset;

  /// Foto da sessão, já encaixada. Tem prioridade sobre [asset].
  final Uint8List? bytes;
  final String? semanticLabel;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final memory = bytes;
    final Widget image;
    if (memory != null && memory.isNotEmpty) {
      image = Image.memory(
        memory,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          return _framed(scheme, child, frame, wasSynchronouslyLoaded);
        },
        errorBuilder: (context, error, stackTrace) {
          return _PhotoPlaceholder(color: scheme.primaryContainer);
        },
      );
    } else {
      image = Image.asset(
        asset,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        semanticLabel: semanticLabel,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          return _framed(scheme, child, frame, wasSynchronouslyLoaded);
        },
        errorBuilder: (context, error, stackTrace) {
          return _PhotoPlaceholder(color: scheme.primaryContainer);
        },
      );
    }
    return RepaintBoundary(child: image);
  }

  Widget _framed(
    ColorScheme scheme,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    final ready = wasSynchronouslyLoaded || frame != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        _PhotoPlaceholder(color: scheme.primaryContainer),
        if (ready) child,
      ],
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
