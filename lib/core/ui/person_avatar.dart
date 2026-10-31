import 'package:flutter/material.dart';

/// Retratos de exemplo, recortados da ilustração do grupo.
///
/// O mesmo rosto aparece no cartão da Home e na ficha do mapa.
abstract final class PersonPortraits {
  static const assets = <String>[
    'assets/images/people/01.jpg',
    'assets/images/people/02.jpg',
    'assets/images/people/03.jpg',
    'assets/images/people/04.jpg',
  ];

  static String forName(String name) {
    final index = name.hashCode.abs() % assets.length;
    return assets[index];
  }
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.radius = 14});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: AssetImage(PersonPortraits.forName(name)),
    );
  }
}
