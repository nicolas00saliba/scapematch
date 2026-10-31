import 'package:flutter/material.dart';

/// Retratos de exemplo, recortes de pessoas diferentes nas fotos do app.
///
/// O mesmo rosto aparece no cartão da Home e na ficha do mapa. O índice
/// escolhe a pessoa: no grupo, cada membro fica com um retrato distinto.
abstract final class PersonPortraits {
  static const assets = <String>[
    'assets/images/people/01.jpg',
    'assets/images/people/02.jpg',
    'assets/images/people/03.jpg',
    'assets/images/people/04.jpg',
    'assets/images/people/05.jpg',
    'assets/images/people/06.jpg',
    'assets/images/people/07.jpg',
    'assets/images/people/08.jpg',
  ];

  static String at(int index) {
    final safe = index < 0 ? -index : index;
    return assets[safe % assets.length];
  }

  static String forName(String name) {
    return at(name.hashCode);
  }
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.radius = 14,
    this.portrait,
  });

  final String name;
  final double radius;

  /// Posição na lista de retratos. Sem isto, o nome escolhe um rosto.
  final int? portrait;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = portrait == null
        ? PersonPortraits.forName(name)
        : PersonPortraits.at(portrait!);
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: AssetImage(asset),
    );
  }
}
