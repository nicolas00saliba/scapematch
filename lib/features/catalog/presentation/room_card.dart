import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/catalog/presentation/scape_pin_icon.dart';

/// Cartão de sala: foto, nomes, cidade e os dois atalhos.
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.listing});

  final RoomListing listing;

  static const width = 300.0;
  static const decodeWidth = 800;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = listing.room;
    final image = roomCategoryImage(room.category);

    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 132,
              child: Image.asset(
                image,
                key: AppKeys.roomCard(room.id),
                fit: BoxFit.cover,
                cacheWidth: decodeWidth,
                semanticLabel: room.name,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.houseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const ScapePinIcon(size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          listing.cityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Flexible(
                        child: _RoomAction(
                          actionKey: AppKeys.roomFindGroup(room.id),
                          label: 'Achar grupo',
                          semanticLabel: 'Achar grupo na sala ${room.name}',
                          filled: false,
                          onPressed: () {
                            context.push('/rooms/${room.id}/groups');
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _RoomAction(
                          actionKey: AppKeys.roomCreateGroup(room.id),
                          label: 'Criar grupo',
                          semanticLabel: 'Criar grupo na sala ${room.name}',
                          filled: true,
                          onPressed: () {
                            context.push('/groups/new?roomId=${room.id}');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.actionKey,
    required this.label,
    required this.semanticLabel,
    required this.filled,
    required this.onPressed,
  });

  final Key actionKey;
  final String label;
  final String semanticLabel;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    );
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    );
    final button = filled
        ? FilledButton(
            key: actionKey,
            style: style,
            onPressed: onPressed,
            child: child,
          )
        : FilledButton.tonal(
            key: actionKey,
            style: style,
            onPressed: onPressed,
            child: child,
          );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: FittedBox(fit: BoxFit.scaleDown, child: button),
    );
  }
}
