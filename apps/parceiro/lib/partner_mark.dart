import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

/// Símbolo aprovado, sem letreiro, com o selo discreto da casa.
class PartnerMark extends StatelessWidget {
  const PartnerMark({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    final onDark = Theme.of(context).brightness == Brightness.dark;
    final sealColor = onDark ? ScapeLogo.pinOnDark : ScapeLogo.copper;
    return Semantics(
      label: 'ScapeMatch Parceiro',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScapeLogo(variant: ScapeLogoVariant.mark, height: height),
          SizedBox(width: height * 0.16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: sealColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: sealColor, width: 1.2),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: height * 0.22,
                vertical: height * 0.08,
              ),
              child: Text(
                'Parceiro',
                style: TextStyle(
                  color: sealColor,
                  fontSize: height * 0.32,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
