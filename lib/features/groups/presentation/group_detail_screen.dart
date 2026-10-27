import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/sharing/group_link.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/edit_group_sheet.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_dialogs.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/providers/repositories.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupDetailViewModelProvider(widget.groupId));
    final now = ref.watch(clockProvider).now();
    final userId = ref.watch(currentUserProvider).id;
    return AppScaffold(
      appBar: AppBar(
        title: const Text('Grupo'),
        actions: detail.maybeWhen(
          data: (group) => [
            IconButton(
              key: AppKeys.shareGroup,
              tooltip: 'Copiar link do grupo',
              onPressed: () => _share(group.id),
              icon: const Icon(Icons.link),
            ),
            if (_canEdit(group, userId, now))
              IconButton(
                key: AppKeys.editGroup,
                tooltip: 'Editar grupo',
                onPressed: _busy
                    ? null
                    : () => showEditGroupSheet(context, group: group),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
          orElse: () => const <Widget>[],
        ),
      ),
      body: detail.when(
        loading: () => const LoadingView(message: 'Carregando grupo...'),
        error: (error, stackTrace) => ErrorView(
          message: 'Não foi possível carregar este grupo.',
          onRetry: () =>
              ref.invalidate(groupDetailViewModelProvider(widget.groupId)),
        ),
        data: (group) => _content(group, now, userId),
      ),
      bottomBar: detail.maybeWhen(
        data: (group) => _bar(group, now),
        orElse: () => null,
      ),
    );
  }

  bool _canEdit(Group group, String userId, DateTime now) {
    return group.createdBy(userId) &&
        !group.isCancelled &&
        !GroupRules.hasEnded(endsAt: group.endsAt, now: now);
  }

  Widget _content(Group group, DateTime now, String userId) {
    final theme = Theme.of(context);
    final progress = group.totalSpots == 0
        ? 0.0
        : (group.filledSpots / group.totalSpots).clamp(0, 1).toDouble();
    final me = _local(group);
    final roster = group.isCancelled
        ? group.participants
        : group.participants.where((person) => person.occupiesSeat).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const ExampleDataBanner(),
        if (group.isCancelled) ...[
          const SizedBox(height: 12),
          _Banner(
            color: AppColors.copperSoft,
            foreground: AppColors.copperInk,
            icon: Icons.event_busy,
            text: GroupMessages.cancelledBanner,
          ),
        ],
        if (me != null && me.occupiesSeat && !group.isCancelled) ...[
          const SizedBox(height: 12),
          const _Banner(
            color: AppColors.tealSoft,
            foreground: AppColors.teal,
            icon: Icons.check_circle,
            text: GroupMessages.joinedBanner,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          group.roomName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${group.houseName} · ${group.neighborhood}',
          style: theme.textTheme.titleMedium?.copyWith(color: AppColors.muted),
        ),
        Text(
          group.cityName,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        _InfoPanel(
          icon: Icons.schedule,
          title: formatSession(group.startsAt),
          subtitle:
              '${group.durationMinutes} min · ${group.difficulty.labelPt}',
        ),
        const SizedBox(height: 8),
        Text(
          formatStartsIn(
            startsAt: group.startsAt,
            endsAt: group.endsAt,
            now: now,
          ),
          key: AppKeys.countdown,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.teal,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Text(group.roomTheme, style: theme.textTheme.bodyLarge),
        if (group.note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            group.note,
            key: AppKeys.groupNote,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'O grupo quer ${group.totalSpots} pessoas. A sala comporta até ${group.roomCapacity}.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 12),
        Text(
          formatPrice(group.priceCents),
          key: AppKeys.priceLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'Por pessoa · pagamento simulado. Nada é cobrado de verdade.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        if (me != null) ...[
          const SizedBox(height: 8),
          Text(GroupMessages.paymentLabel),
          if (GroupMessages.refundLabel(me) != null)
            Text(
              GroupMessages.refundLabel(me)!,
              key: AppKeys.refundStatus,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          '${group.filledSpots} de ${group.totalSpots} vagas',
          key: AppKeys.spotSummary,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          GroupMessages.confirmedCount(group.confirmedCount),
          key: AppKeys.confirmedCount,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.tealSoft,
            color: group.isFull ? AppColors.muted : AppColors.teal,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          group.isCancelled ? 'Quem estava' : 'Quem já está',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final person in roster)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppColors.tealSoft,
              foregroundColor: AppColors.teal,
              child: Text(_initial(person.displayName)),
            ),
            title: Text(person.displayName),
            subtitle: Text(_personSubtitle(person)),
            trailing: _canRemove(group, userId, now, person)
                ? TextButton(
                    key: AppKeys.removeMember(person.id),
                    onPressed: _busy ? null : () => _remove(person),
                    child: const Text('Remover'),
                  )
                : null,
          ),
      ],
    );
  }

  String _personSubtitle(Participant person) {
    final refund = GroupMessages.refundLabel(person);
    final status = GroupMessages.participantSubtitle(person);
    if (refund == null) {
      return '$status · ${GroupMessages.paymentLabel}';
    }
    return '$status · $refund';
  }

  bool _canRemove(
    Group group,
    String userId,
    DateTime now,
    Participant person,
  ) {
    return _canEdit(group, userId, now) &&
        !person.isCreator &&
        person.occupiesSeat &&
        !person.isLocalUser;
  }

  Widget? _bar(Group group, DateTime now) {
    final me = _local(group);
    final ended = GroupRules.hasEnded(endsAt: group.endsAt, now: now);
    final started = GroupRules.hasStarted(startsAt: group.startsAt, now: now);
    final buttons = <Widget>[];

    if (me != null && me.occupiesSeat && !group.isCancelled && !ended) {
      if (me.attendance != AttendanceStatus.confirmed) {
        buttons.add(
          FilledButton(
            key: AppKeys.confirmAttendance,
            onPressed: _busy ? null : _confirm,
            child: const Text('Confirmar presença'),
          ),
        );
      }
      if (me.isCreator) {
        buttons.add(
          FilledButton(
            key: AppKeys.deleteGroup,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _busy ? null : _delete,
            child: const Text('Excluir grupo'),
          ),
        );
      } else {
        buttons.add(
          OutlinedButton(
            key: AppKeys.leaveGroup,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : () => _leave(group, now),
            child: const Text('Sair do grupo'),
          ),
        );
      }
    } else if (!group.isCancelled && !ended) {
      if (me != null && !me.occupiesSeat) {
        buttons.add(
          const FilledButton(
            onPressed: null,
            child: Text(GroupMessages.leftBanner),
          ),
        );
      } else if (started) {
        buttons.add(
          const FilledButton(
            onPressed: null,
            child: Text('Este grupo já começou'),
          ),
        );
      } else if (group.isFull) {
        buttons.add(
          const FilledButton(
            key: AppKeys.joinButton,
            onPressed: null,
            child: Text('Grupo cheio'),
          ),
        );
      } else {
        buttons.add(
          FilledButton(
            key: AppKeys.joinButton,
            onPressed: _busy ? null : _join,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Entrar no grupo'),
          ),
        );
      }
    }

    if (buttons.isEmpty) {
      return null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          buttons[index],
        ],
      ],
    );
  }

  Future<void> _join() async {
    await _run(() async {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .join();
      if (!mounted) {
        return;
      }
      final message = reason == null
          ? 'Você entrou no grupo.'
          : GroupMessages.joinFailure(reason);
      _snack(message);
    });
  }

  Future<void> _confirm() async {
    await _run(() async {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .confirmAttendance();
      if (!mounted) {
        return;
      }
      _snack(
        reason == null
            ? GroupMessages.confirmSuccess
            : GroupMessages.actionFailed,
      );
    });
  }

  Future<void> _leave(Group group, DateTime now) async {
    final refunds = GroupRules.refundsOnParticipantCancel(
      startsAt: group.startsAt,
      now: now,
    );
    final accepted = await showLeaveDialog(context, refunds: refunds);
    if (!accepted || !mounted) {
      return;
    }
    await _run(() async {
      final result = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .leave();
      if (!mounted || result == null) {
        return;
      }
      final message = switch (result) {
        LeaveGroupSuccess(:final group) => _leaveSnack(group),
        LeaveGroupFailure() => GroupMessages.actionFailed,
      };
      _snack(message);
    });
  }

  Participant? _local(Group group) {
    for (final person in group.participants) {
      if (person.isLocalUser) {
        return person;
      }
    }
    return null;
  }

  String _leaveSnack(Group group) {
    final me = _local(group);
    if (me?.refundReason == RefundReason.cancelledInTime ||
        me?.refund == RefundStatus.refunded) {
      return GroupMessages.leaveRefunded;
    }
    return GroupMessages.leaveDenied;
  }

  Future<void> _delete() async {
    final accepted = await showDeleteDialog(context);
    if (!accepted || !mounted) {
      return;
    }
    await _run(() async {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .deleteGroup();
      if (!mounted) {
        return;
      }
      _snack(
        reason == null
            ? GroupMessages.deletedSnack
            : GroupMessages.actionFailed,
      );
    });
  }

  Future<void> _remove(Participant person) async {
    final accepted = await showRemoveDialog(context, name: person.displayName);
    if (!accepted || !mounted) {
      return;
    }
    await _run(() async {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .removeMember(person.id);
      if (!mounted) {
        return;
      }
      _snack(
        reason == null
            ? GroupMessages.removedSnack
            : GroupMessages.actionFailed,
      );
    });
  }

  Future<void> _share(String groupId) async {
    try {
      await Clipboard.setData(ClipboardData(text: groupLink(groupId)));
      if (!mounted) {
        return;
      }
      _snack(GroupMessages.linkCopied);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _snack(GroupMessages.linkFailed);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _snack(GroupMessages.actionFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    return trimmed[0].toUpperCase();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.foreground,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color foreground;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
