import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/catalog/presentation/scape_pin_icon.dart';

/// Largura fixa do cartão no carrossel.
const roomCardWidth = 300.0;

const _photoHeight = 168.0;
const _pad = 12.0;
const _textTop = 10.0;
const _pinSize = 16.0;
const _buttonHeight = 48.0;
const _buttonGap = 8.0;

/// Altura do cartão para o carrossel acompanhar o conteúdo, inclusive o
/// textScale. [width] é a largura do quadro. O rodapé quebra os botões
/// quando pino, cidade e os dois rótulos não cabem na mesma linha.
double roomCardHeight(
  BuildContext context,
  RoomListing listing, {
  double width = roomCardWidth,
}) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final contentWidth = width - (_pad * 2);
  final titleStyle = _titleStyle(theme);
  final houseStyle = _houseStyle(theme);
  final footer = _footerHeight(
    listing: listing,
    cityStyle: _cityStyle(theme),
    buttonStyle: _buttonTextStyle,
    scaler: scaler,
    maxWidth: contentWidth,
  );
  return _photoHeight +
      _textTop +
      _textHeight(listing.room.name, titleStyle, scaler, contentWidth, 2) +
      2 +
      _textHeight(listing.houseName, houseStyle, scaler, contentWidth, 1) +
      8 +
      footer +
      _pad;
}

/// Cartão de sala: foto, nomes, cidade e os dois atalhos.
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.listing});

  final RoomListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = listing.room;
    final image = roomCategoryImage(room.category);

    return PressableScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => context.push('/sala/${room.id}'),
              child: Hero(
                tag: roomHeroTag(room.id),
                child: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    height: _photoHeight,
                    child: ScapePhoto(
                      key: AppKeys.roomCard(room.id),
                      asset: image,
                      semanticLabel: room.name,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_pad, _textTop, _pad, _pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(theme),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.houseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _houseStyle(theme),
                  ),
                  const SizedBox(height: 8),
                  _RoomFooter(listing: listing),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFooter extends StatelessWidget {
  const _RoomFooter({required this.listing});

  final RoomListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final room = listing.room;
    return LayoutBuilder(
      builder: (context, constraints) {
        final plan = _footerPlan(
          listing: listing,
          cityStyle: _cityStyle(theme),
          buttonStyle: _buttonTextStyle,
          scaler: scaler,
          maxWidth: constraints.maxWidth,
        );
        final city = _CityLabel(
          name: listing.cityName,
          style: _cityStyle(theme),
        );
        final actions = _RoomActions(
          findKey: AppKeys.roomFindGroup(room.id),
          createKey: AppKeys.roomCreateGroup(room.id),
          stacked: plan.stackButtons,
          onFind: () => context.push('/rooms/${room.id}/groups'),
          onCreate: () => context.push('/groups/new?roomId=${room.id}'),
          findLabel: 'Achar grupo na sala ${room.name}',
          createLabel: 'Criar grupo na sala ${room.name}',
        );
        if (!plan.buttonsOnOwnLine) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: city),
              const SizedBox(width: _buttonGap),
              actions,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            city,
            const SizedBox(height: _buttonGap),
            actions,
          ],
        );
      },
    );
  }
}

class _CityLabel extends StatelessWidget {
  const _CityLabel({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const ScapePinIcon(size: _pinSize),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _RoomActions extends StatelessWidget {
  const _RoomActions({
    required this.findKey,
    required this.createKey,
    required this.stacked,
    required this.onFind,
    required this.onCreate,
    required this.findLabel,
    required this.createLabel,
  });

  final Key findKey;
  final Key createKey;
  final bool stacked;
  final VoidCallback onFind;
  final VoidCallback onCreate;
  final String findLabel;
  final String createLabel;

  @override
  Widget build(BuildContext context) {
    final find = _RoomAction(
      actionKey: findKey,
      label: 'Achar grupo',
      semanticsLabel: findLabel,
      filled: false,
      onPressed: onFind,
    );
    final create = _RoomAction(
      actionKey: createKey,
      label: 'Criar grupo',
      semanticsLabel: createLabel,
      filled: true,
      onPressed: onCreate,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          find,
          const SizedBox(height: _buttonGap),
          create,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        find,
        const SizedBox(width: _buttonGap),
        create,
      ],
    );
  }
}

/// O próprio botão é o controle de acessibilidade. O rótulo longo fica no
/// texto, sem um Semantics por fora que tire o toque do botão.
class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.actionKey,
    required this.label,
    required this.semanticsLabel,
    required this.filled,
    required this.onPressed,
  });

  final Key actionKey;
  final String label;
  final String semanticsLabel;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final inherited = Theme.of(context).textTheme.labelLarge;
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, _buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: _buttonTextStyle.copyWith(fontFamily: inherited?.fontFamily),
    );
    final child = Text(label, semanticsLabel: semanticsLabel);
    if (filled) {
      return FilledButton(
        key: actionKey,
        style: style,
        onPressed: onPressed,
        child: child,
      );
    }
    return FilledButton.tonal(
      key: actionKey,
      style: style,
      onPressed: onPressed,
      child: child,
    );
  }
}

class _FooterPlan {
  const _FooterPlan({
    required this.buttonsOnOwnLine,
    required this.stackButtons,
    required this.height,
  });

  final bool buttonsOnOwnLine;
  final bool stackButtons;
  final double height;
}

_FooterPlan _footerPlan({
  required RoomListing listing,
  required TextStyle cityStyle,
  required TextStyle buttonStyle,
  required TextScaler scaler,
  required double maxWidth,
}) {
  final cityWidth =
      _pinSize + 4 + _textWidth(listing.cityName, cityStyle, scaler);
  final findWidth = _buttonWidth('Achar grupo', buttonStyle, scaler);
  final createWidth = _buttonWidth('Criar grupo', buttonStyle, scaler);
  final pairWidth = findWidth + _buttonGap + createWidth;
  final cityLine = math.max(
    _pinSize,
    _textHeight(
      listing.cityName,
      cityStyle,
      scaler,
      maxWidth - _pinSize - 4,
      1,
    ),
  );
  final buttonLine = math.max(
    _buttonHeight,
    _textHeight('Achar grupo', buttonStyle, scaler, double.infinity, 1),
  );
  // Folga para o botão não estourar a linha por causa do padding do tema.
  final limit = maxWidth - 8;
  final fitsWithCity = cityWidth + _buttonGap + pairWidth <= limit;
  if (fitsWithCity) {
    return _FooterPlan(
      buttonsOnOwnLine: false,
      stackButtons: false,
      height: math.max(cityLine, buttonLine),
    );
  }
  final stackButtons = pairWidth > limit;
  final buttonsHeight = stackButtons
      ? buttonLine + _buttonGap + buttonLine
      : buttonLine;
  return _FooterPlan(
    buttonsOnOwnLine: true,
    stackButtons: stackButtons,
    height: cityLine + _buttonGap + buttonsHeight,
  );
}

double _footerHeight({
  required RoomListing listing,
  required TextStyle cityStyle,
  required TextStyle buttonStyle,
  required TextScaler scaler,
  required double maxWidth,
}) {
  return _footerPlan(
    listing: listing,
    cityStyle: cityStyle,
    buttonStyle: buttonStyle,
    scaler: scaler,
    maxWidth: maxWidth,
  ).height;
}

const _buttonTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w800,
  height: 1.2,
);

TextStyle _titleStyle(ThemeData theme) {
  return theme.textTheme.titleMedium!.copyWith(
    fontWeight: FontWeight.w800,
    height: 1.15,
  );
}

TextStyle _houseStyle(ThemeData theme) {
  return theme.textTheme.bodySmall!.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

TextStyle _cityStyle(ThemeData theme) {
  return theme.textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w700);
}

double _textHeight(
  String text,
  TextStyle style,
  TextScaler scaler,
  double maxWidth,
  int maxLines,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

double _textWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

double _buttonWidth(String label, TextStyle style, TextScaler scaler) {
  return math.max(48, _textWidth(label, style, scaler) + 24);
}
