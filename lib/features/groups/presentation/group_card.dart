import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

/// Voo da capa: do cartão do grupo até a tela do grupo.
///
/// Não usa a tag da sala. As duas capas podem estar na mesma Home.
String groupHeroTag(String groupId) => 'group-cover-$groupId';

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
    required this.now,
    this.onInvite,
  });

  final Group group;
  final VoidCallback onTap;
  final DateTime now;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spots = '${group.filledSpots} de ${group.totalSpots} vagas';
    final started = !now.isBefore(group.startsAt);

    final seated = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];

    return PressableScale(
      child: Semantics(
        button: true,
        identifier: 'group-card-${group.id}',
        label:
            '${group.roomName}, ${group.houseName}, ${formatSession(group.startsAt)}, $spots',
        excludeSemantics: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: AppKeys.groupCard(group.id),
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (group.coverAsset.isNotEmpty)
                    HeroMode(
                      enabled: scapeAnimationsEnabled(context),
                      child: Hero(
                        tag: groupHeroTag(group.id),
                        child: Material(
                          type: MaterialType.transparency,
                          child: SizedBox(
                            width: 112,
                            child: ScapePhoto(
                              asset: group.coverAsset,
                              semanticLabel: group.roomName,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.roomName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _StatusPill(group: group),
                          const SizedBox(height: 2),
                          Text(
                            '${group.houseName} · ${group.neighborhood}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 16,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(formatSession(group.startsAt)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            spots,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _AvatarRow(people: seated, filled: group.filledSpots),
                          const SizedBox(height: 2),
                          Text(
                            GroupMessages.phaseLabel(
                              group.phaseAt(now),
                              missing: group.spotsUntilClose,
                              started: started,
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.secondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (onInvite != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: AppKeys.inviteOnCard(group.id),
                                onPressed: onInvite,
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.secondary,
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Convidar'),
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
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.people, required this.filled});

  final List<Participant> people;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = people.take(4).toList();
    final extra = people.length - shown.length;
    return Row(
      children: [
        if (shown.isNotEmpty)
          SizedBox(
            width: 28 + (shown.length - 1) * 18.0 + (extra > 0 ? 18 : 0),
            height: 28,
            child: Stack(
              children: [
                for (var index = 0; index < shown.length; index++)
                  Positioned(
                    left: index * 18,
                    child: StaggerIn(
                      index: index,
                      child: _Avatar(name: shown[index].displayName),
                    ),
                  ),
                if (extra > 0)
                  Positioned(
                    left: shown.length * 18,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: scheme.secondaryContainer,
                      child: Text(
                        '+$extra',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        AnimatedCount(
          value: filled,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return PersonAvatar(name: name, radius: 14);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground, border) = switch ((
      group.isFull,
      group.isAlmostFull,
    )) {
      (true, _) => (
        'Cheio',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        scheme.outline,
      ),
      (false, true) => (
        'Quase cheio',
        scheme.tertiary,
        scheme.onTertiary,
        scheme.onTertiary,
      ),
      _ => (
        'Aberto',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
