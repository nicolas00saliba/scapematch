import 'package:flutter/material.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/map/domain/nearby_group.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';

/// Ficha que sobe ao tocar no pino: a sala em cima, o grupo embaixo.
class GroupPinSheet extends StatelessWidget {
  const GroupPinSheet({
    super.key,
    required this.item,
    required this.now,
    required this.scrollController,
    required this.onOpen,
  });

  final NearbyGroup item;
  final DateTime now;
  final ScrollController scrollController;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final group = item.group;
    final seated = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];
    final gallery = categoryForCover(group.coverAsset);
    final thumbs = <String>[
      if (gallery != null)
        for (final asset in roomGallery(gallery))
          if (asset.isNotEmpty && asset != group.coverAsset) asset,
    ];
    return Material(
      key: AppKeys.groupPinSheet,
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (group.coverAsset.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 180,
                  child: ScapePhoto(
                    asset: group.coverAsset,
                    semanticLabel: group.roomName,
                  ),
                ),
              ),
            ),
          if (thumbs.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  for (final asset in thumbs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 88,
                          height: 62,
                          child: ScapePhoto(
                            asset: asset,
                            semanticLabel: group.roomName,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.roomName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.houseName} · ${formatDistanceKm(item.distanceKm)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _SheetFact(
                  icon: Icons.timer_outlined,
                  label: 'Duração',
                  value: '${group.durationMinutes} min',
                ),
                _SheetFact(
                  icon: Icons.speed,
                  label: 'Dificuldade',
                  value: group.difficulty.labelPt,
                ),
                _SheetFact(
                  icon: Icons.payments_outlined,
                  label: 'Preço',
                  value: '${formatPrice(group.priceCents)} por pessoa',
                ),
                const SizedBox(height: 18),
                Text(
                  'O grupo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(formatSession(group.startsAt)),
                const SizedBox(height: 6),
                Text(
                  '${group.filledSpots} de ${group.totalSpots} vagas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _SheetAvatars(people: seated),
                if (group.showCloseDeadline(now)) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${GroupMessages.spotsUntilClose(group.spotsUntilClose)} · até ${formatSession(group.closesAtResolved)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: AppKeys.groupPinOpen,
                  onPressed: onOpen,
                  child: const Text(LiveMapMessages.seeGroup),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFact extends StatelessWidget {
  const _SheetFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAvatars extends StatelessWidget {
  const _SheetAvatars({required this.people});

  final List<Participant> people;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(5).toList();
    return Row(
      children: [
        for (var index = 0; index < shown.length; index++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: PersonAvatar(
              name: shown[index].displayName.isEmpty
                  ? '?'
                  : shown[index].displayName,
              radius: 16,
              portrait: index,
            ),
          ),
      ],
    );
  }
}
