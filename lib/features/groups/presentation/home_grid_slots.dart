import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/sharing/site_links.dart';
import 'package:scapematch/core/ui/scape_grid.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';

/// Quantos cartões a grade da Home no site precisa para fechar as linhas.
///
/// Abaixo de duas colunas a lista fica como está. Com duas ou mais, completa
/// pelo menos [minRows] e, se já passou disso, só a última linha incompleta.
int homeGridSlotCount({
  required int itemCount,
  required int columns,
  int minRows = 3,
}) {
  if (columns < 2) {
    return itemCount;
  }
  final minimum = columns * minRows;
  if (itemCount <= minimum) {
    return minimum;
  }
  final remainder = itemCount % columns;
  if (remainder == 0) {
    return itemCount;
  }
  return itemCount + (columns - remainder);
}

/// Colunas da grade de grupos no site. A partir de 1280 são quatro,
/// como a Home já fazia. Abaixo disso segue a largura útil da grade.
int homeGroupGridColumns({
  required double windowWidth,
  required double gridWidth,
}) {
  if (windowWidth >= homeWebGridFourColumns) {
    return 4;
  }
  return scapeGridColumns(gridWidth, maxColumns: 3);
}

enum HomeGridSlotKind { createGroup, comingSoon, partner, inviteFriends }

const homeGridCreateMessage = 'Crie um grupo';
const homeGridPartnerMessage = 'Tem uma casa de jogos? Seja parceiro';
const homeGridInviteMessage = 'Convide seus amigos';

const _slotKinds = <HomeGridSlotKind>[
  HomeGridSlotKind.createGroup,
  HomeGridSlotKind.comingSoon,
  HomeGridSlotKind.partner,
  HomeGridSlotKind.inviteFriends,
];

HomeGridSlotKind homeGridSlotKind(int index) {
  final safe = index < 0 ? 0 : index;
  return _slotKinds[safe % _slotKinds.length];
}

/// Cada frase entra uma vez. O restante da grade é esqueleto.
bool homeGridSlotIsMessage(int index) {
  return index >= 0 && index < _slotKinds.length;
}

String homeGridSlotMessage(
  HomeGridSlotKind kind, {
  String? cityName,
  String gameTypeId = GameTypes.all,
}) {
  return switch (kind) {
    HomeGridSlotKind.createGroup => homeGridCreateMessage,
    HomeGridSlotKind.comingSoon => homeGridComingSoonMessage(
      cityName: cityName,
      gameTypeId: gameTypeId,
    ),
    HomeGridSlotKind.partner => homeGridPartnerMessage,
    HomeGridSlotKind.inviteFriends => homeGridInviteMessage,
  };
}

/// A frase de exemplo, com a cidade e o tipo quando o filtro já escolheu um.
String homeGridComingSoonMessage({
  String? cityName,
  String gameTypeId = GameTypes.all,
}) {
  final place = cityName == null || cityName.trim().isEmpty
      ? 'na sua cidade'
      : 'em ${cityName.trim()}';
  if (gameTypeId == GameTypes.all) {
    return 'Novas salas chegando em breve $place';
  }
  return 'Novas salas de ${GameTypes.labelOf(gameTypeId)} '
      'chegando em breve $place';
}

/// Grade da Home no site. Os filhos reais vêm primeiro. O que faltar para
/// fechar as linhas entra por [placeholderBuilder], na ordem da vaga.
class HomeGroupGrid extends StatelessWidget {
  const HomeGroupGrid({
    super.key,
    required this.children,
    required this.placeholderBuilder,
    this.gap = 12,
    this.minRows = 3,
  });

  final List<Widget> children;
  final Widget Function(int index) placeholderBuilder;
  final double gap;
  final int minRows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = homeGroupGridColumns(
          windowWidth: MediaQuery.sizeOf(context).width,
          gridWidth: constraints.maxWidth,
        );
        final total = homeGridSlotCount(
          itemCount: children.length,
          columns: columns,
          minRows: minRows,
        );
        final cells = <Widget>[
          ...children,
          for (var index = 0; index < total - children.length; index++)
            placeholderBuilder(index),
        ];
        return _layOut(cells, columns, constraints.maxWidth);
      },
    );
  }

  Widget _layOut(List<Widget> cells, int columns, double maxWidth) {
    if (columns <= 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cells.length; index++) ...[
            if (index > 0) SizedBox(height: gap),
            cells[index],
          ],
        ],
      );
    }
    final itemWidth = (maxWidth - gap * (columns - 1)) / columns;
    final rowCount = (cells.length / columns).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: gap),
                  SizedBox(
                    width: itemWidth,
                    child: cells[row * columns + column],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Vaga da grade. Mesma faixa do cartão denso: capa estreita e texto.
/// O tracejado e as barras usam o verde e o cobre do tema.
class HomeGridSlotCard extends StatelessWidget {
  const HomeGridSlotCard({
    super.key,
    required this.kind,
    this.cityName,
    this.gameTypeId = GameTypes.all,
  });

  final HomeGridSlotKind kind;
  final String? cityName;
  final String gameTypeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = homeGridSlotMessage(
      kind,
      cityName: cityName,
      gameTypeId: gameTypeId,
    );
    return Semantics(
      button: true,
      label: message,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: CustomPaint(
            foregroundPainter: _DashedRRectPainter(
              color: scheme.primary.withValues(alpha: 0.7),
              radius: 24,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: groupCardDenseCoverWidth,
                    child: ColoredBox(
                      color: scheme.primaryContainer,
                      child: Icon(_icon(kind), color: scheme.primary, size: 26),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TwoLineMessage(message: message),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 15,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _hint(kind, cityName),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          _SoftBar(
                            color: scheme.secondary.withValues(alpha: 0.22),
                            widthFactor: 0.55,
                            height: 15,
                          ),
                          const SizedBox(height: 4),
                          _SoftBar(
                            color: scheme.primary.withValues(alpha: 0.28),
                            widthFactor: 1,
                            height: 4,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _open(context),
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.secondary,
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(40, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              child: Text(_actionLabel(kind)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _hint(HomeGridSlotKind kind, String? cityName) {
    final place = cityName == null || cityName.trim().isEmpty
        ? 'na sua cidade'
        : 'em ${cityName.trim()}';
    return switch (kind) {
      HomeGridSlotKind.createGroup => 'Abre o formulário $place',
      HomeGridSlotKind.comingSoon => 'A grade espera a próxima sala',
      HomeGridSlotKind.partner => 'Abre o app da casa',
      HomeGridSlotKind.inviteFriends => 'Copia um convite do ScapeMatch',
    };
  }

  String _actionLabel(HomeGridSlotKind kind) {
    return switch (kind) {
      HomeGridSlotKind.createGroup => 'Criar',
      HomeGridSlotKind.comingSoon => 'Em breve',
      HomeGridSlotKind.partner => 'Abrir',
      HomeGridSlotKind.inviteFriends => 'Convidar',
    };
  }

  IconData _icon(HomeGridSlotKind kind) {
    return switch (kind) {
      HomeGridSlotKind.createGroup => Icons.group_add_outlined,
      HomeGridSlotKind.comingSoon => Icons.upcoming_outlined,
      HomeGridSlotKind.partner => Icons.storefront_outlined,
      HomeGridSlotKind.inviteFriends => Icons.ios_share,
    };
  }

  Future<void> _open(BuildContext context) async {
    switch (kind) {
      case HomeGridSlotKind.createGroup:
        context.push('/groups/new');
      case HomeGridSlotKind.comingSoon:
        final place = cityName == null || cityName!.trim().isEmpty
            ? 'na sua cidade'
            : 'em ${cityName!.trim()}';
        _snack(context, 'Quando abrir uma sala $place, ela entra nesta grade.');
      case HomeGridSlotKind.partner:
        final target = partnerAppUri();
        final opened = await openExternalUrl(target);
        if (!context.mounted || opened) {
          return;
        }
        final where = target.host.isEmpty ? target.path : target.host;
        _snack(
          context,
          'Não foi possível abrir o app da casa. O endereço é $where.',
        );
      case HomeGridSlotKind.inviteFriends:
        final text = friendInviteText();
        final messenger = ScaffoldMessenger.of(context);
        final shared = await sharePlainText(text);
        if (!shared) {
          await Clipboard.setData(ClipboardData(text: text));
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              shared
                  ? 'Convite enviado.'
                  : 'Convite copiado. Manda para os seus amigos.',
            ),
          ),
        );
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Vaga sem frase. O tracejado e as barras mantêm o tamanho do cartão.
class HomeGridSkeletonCard extends StatelessWidget {
  const HomeGridSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quiet = scheme.primary.withValues(alpha: 0.22);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        foregroundPainter: _DashedRRectPainter(
          color: scheme.primary.withValues(alpha: 0.35),
          radius: 24,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: groupCardDenseCoverWidth,
                child: ColoredBox(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  child: Icon(Icons.hourglass_empty, color: quiet, size: 22),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SoftBar(color: quiet, widthFactor: 0.72, height: 14),
                      const SizedBox(height: 6),
                      _SoftBar(color: quiet, widthFactor: 0.46, height: 14),
                      const SizedBox(height: 8),
                      _SoftBar(color: quiet, widthFactor: 0.62, height: 15),
                      const SizedBox(height: 8),
                      _SoftBar(color: quiet, widthFactor: 0.4, height: 15),
                      const SizedBox(height: 8),
                      _SoftBar(
                        color: scheme.primary.withValues(alpha: 0.16),
                        widthFactor: 1,
                        height: 4,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoLineMessage extends StatelessWidget {
  const _TwoLineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w800, height: 1.15);
    final painter = TextPainter(
      text: TextSpan(text: 'A\nA', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _SoftBar extends StatelessWidget {
  const _SoftBar({
    required this.color,
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _stroke = 1.5;
  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final inset = _stroke;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0, size.width - inset * 2),
      math.max(0, size.height - inset * 2),
    );
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius - inset)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
