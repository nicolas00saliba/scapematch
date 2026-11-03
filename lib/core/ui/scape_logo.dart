import 'package:flutter/material.dart';

/// Marca do ScapeMatch. A Home, a barra do site e as próximas telas
/// (landing e Parceiro) usam só este widget.
///
/// O logo de hoje é o wordmark. Quando a arte final existir, ela entra em
/// `assets/brand/` e o desenho muda apenas aqui.
class ScapeLogo extends StatelessWidget {
  const ScapeLogo({super.key, this.onTap});

  final VoidCallback? onTap;

  static const wordmark = 'ScapeMatch';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = Text(
      wordmark,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
    if (onTap == null) {
      return mark;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: mark,
      ),
    );
  }
}
