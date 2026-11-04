import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/group_seat_facts.dart';

/// Voo da capa: do cartão do grupo até a tela do grupo.
///
/// Não usa a tag da sala. As duas capas podem estar na mesma Home.
String groupHeroTag(String groupId) => 'group-cover-$groupId';

/// Largura da capa no celular e nas listas.
const groupCardCoverWidth = 112.0;

/// Capa da grade da Home no site: estreita, para quatro colunas.
const groupCardDenseCoverWidth = 64.0;

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.onTap,
    required this.now,
    this.onInvite,
    this.dense = false,
    this.friendInside = false,
  });

  final Group group;
  final VoidCallback onTap;
  final DateTime now;
  final VoidCallback? onInvite;

  /// Grade da Home no site: capa menor e só nome, local, data,
  /// vagas e Convidar.
  final bool dense;

  /// Verdadeiro quando alguém sentado é amigo de quem está olhando.
  final bool friendInside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spots = GroupMessages.seatCount(group.filledSpots, group.totalSpots);
    final started = !now.isBefore(group.startsAt);

    final seated = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];
    final coverWidth = dense ? groupCardDenseCoverWidth : groupCardCoverWidth;
    final pad = dense
        ? const EdgeInsets.fromLTRB(8, 6, 8, 4)
        : const EdgeInsets.fromLTRB(14, 14, 14, 16);
    final titleGap = dense ? 2.0 : 4.0;
    final blockGap = dense ? 2.0 : 8.0;

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
                            width: coverWidth,
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
                      padding: pad,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (friendInside) ...[
                            _FriendBadge(groupId: group.id, dense: dense),
                            SizedBox(height: titleGap),
                          ],
                          Text(
                            group.roomName,
                            maxLines: dense ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (dense
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      height: dense ? 1.15 : null,
                                    ),
                          ),
                          SizedBox(height: titleGap),
                          if (!dense) ...[
                            _StatusPill(group: group, dense: dense),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            '${group.houseName} · ${group.neighborhood}',
                            maxLines: dense ? 1 : null,
                            overflow: dense ? TextOverflow.ellipsis : null,
                            style:
                                (dense
                                        ? theme.textTheme.bodySmall
                                        : theme.textTheme.bodyMedium)
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: dense ? 1.2 : null,
                                    ),
                          ),
                          SizedBox(height: blockGap),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: dense ? 15 : 16,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  formatSession(group.startsAt),
                                  maxLines: dense ? 1 : null,
                                  overflow: dense
                                      ? TextOverflow.ellipsis
                                      : null,
                                  style: dense
                                      ? theme.textTheme.bodySmall
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: blockGap),
                          GroupSeatFacts(
                            group: group,
                            compact: true,
                            dense: dense,
                          ),
                          if (started &&
                              group.phaseAt(now) == GroupPhase.forming) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Sessão já começou',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.secondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          if (!dense) ...[
                            const SizedBox(height: 6),
                            _AvatarRow(
                              people: seated,
                              filled: group.filledSpots,
                              dense: dense,
                            ),
                          ],
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
                                  minimumSize: dense
                                      ? const Size(40, 32)
                                      : null,
                                  padding: dense
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        )
                                      : null,
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

class _FriendBadge extends StatelessWidget {
  const _FriendBadge({required this.groupId, required this.dense});

  final String groupId;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: AppKeys.friendBadge(groupId),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8,
          vertical: dense ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Tem amigo',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: dense ? 10 : null,
          ),
        ),
      ),
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({
    required this.people,
    required this.filled,
    required this.dense,
  });

  final List<Participant> people;
  final int filled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = people.take(4).toList();
    final extra = people.length - shown.length;
    final radius = dense ? 12.0 : 14.0;
    final step = dense ? 16.0 : 18.0;
    final size = radius * 2;
    return Row(
      children: [
        if (shown.isNotEmpty)
          SizedBox(
            width: size + (shown.length - 1) * step + (extra > 0 ? step : 0),
            height: size,
            child: Stack(
              children: [
                for (var index = 0; index < shown.length; index++)
                  Positioned(
                    left: index * step,
                    child: StaggerIn(
                      index: index,
                      child: _Avatar(
                        name: shown[index].displayName,
                        portrait: index,
                        radius: radius,
                      ),
                    ),
                  ),
                if (extra > 0)
                  Positioned(
                    left: shown.length * step,
                    child: CircleAvatar(
                      radius: radius,
                      backgroundColor: scheme.secondaryContainer,
                      child: Text(
                        '+$extra',
                        style: TextStyle(
                          fontSize: dense ? 9 : 10,
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
  const _Avatar({
    required this.name,
    required this.portrait,
    required this.radius,
  });

  final String name;
  final int portrait;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return PersonAvatar(name: name, radius: radius, portrait: portrait);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.group, required this.dense});

  final Group group;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground, border) = switch ((
      group.isFull,
      group.isAlmostFull,
    )) {
      (true, _) => (
        'Fechado',
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
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 4,
      ),
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
