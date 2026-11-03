import 'package:flutter/widgets.dart';

/// Colunas de cartão conforme a largura útil. No celular fica uma coluna.
int scapeGridColumns(double width, {int maxColumns = 3}) {
  var columns = 1;
  if (width >= 680) {
    columns = 2;
  }
  if (width >= 1080) {
    columns = 3;
  }
  if (columns > maxColumns) {
    return maxColumns;
  }
  return columns;
}

/// Grade que vira lista quando só cabe uma coluna.
class ScapeWrapGrid extends StatelessWidget {
  const ScapeWrapGrid({
    super.key,
    required this.children,
    this.gap = 16,
    this.maxColumns = 3,
  });

  final List<Widget> children;
  final double gap;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = scapeGridColumns(
          constraints.maxWidth,
          maxColumns: maxColumns,
        );
        if (columns <= 1) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) SizedBox(height: gap),
                children[index],
              ],
            ],
          );
        }
        final itemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
