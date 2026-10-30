import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/sharing/external_places.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/edit_group_sheet.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_dialogs.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/invite_sheet.dart';
import 'package:scapematch/features/groups/presentation/my_groups_view_model.dart';
import 'package:scapematch/providers/repositories.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  var _busy = false;
  var _shownNotice = false;

  /// Refund the leave dialog promised. Compared with the repository result
  /// after the person confirms, because the clock may have moved.
  bool? _leavePreview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (_shownNotice || extra is! String || extra.isEmpty) {
      return;
    }
    _shownNotice = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _snack(extra);
      }
    });
  }

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
    final scheme = theme.colorScheme;
    final status = ScapeStatusColors.of(context);
    final progress = group.totalSpots == 0
        ? 0.0
        : (group.filledSpots / group.totalSpots).clamp(0, 1).toDouble();
    final me = _local(group);
    final roster = group.isCancelled
        ? group.participants
        : group.participants.where((person) => person.occupiesSeat).toList();
    final category = categoryForCover(group.coverAsset);
    final photos = category == null
        ? (group.coverAsset.isEmpty
              ? const <String>[]
              : <String>[group.coverAsset])
        : roomGallery(category);
    final categoryLabel = category == null ? null : roomCategoryLabel(category);
    final started = !now.isBefore(group.startsAt);
    final addressQuery =
        '${group.streetAddress}, ${group.neighborhood}, ${group.cityName}';

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _GroupCover(group: group, categoryLabel: categoryLabel),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ExampleDataBanner(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: AppKeys.inviteGroup,
                onPressed: () => showInviteSheet(context, group),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.secondary,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Convidar'),
              ),
              if (group.isCancelled) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: status.alertContainer,
                  foreground: status.onAlertContainer,
                  icon: Icons.event_busy,
                  text:
                      group.participants.any(
                        (person) =>
                            person.refundReason ==
                            RefundReason.groupDidNotClose,
                      )
                      ? GroupMessages.missedCloseBanner
                      : GroupMessages.cancelledBanner,
                ),
              ],
              if (me != null && me.occupiesSeat && !group.isCancelled) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: status.successContainer,
                  foreground: status.onSuccessContainer,
                  icon: Icons.check_circle,
                  text: GroupMessages.joinedBanner,
                ),
              ],
              if (_leaveMismatch(me) case final mismatch?) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: status.alertContainer,
                  foreground: status.onAlertContainer,
                  icon: Icons.update,
                  text: mismatch,
                ),
              ],
              const SizedBox(height: 16),
              _SectionCard(
                icon: Icons.schedule,
                title: 'Quando',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatSession(group.startsAt),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.durationMinutes} min · ${group.difficulty.labelPt}',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatStartsIn(
                        startsAt: group.startsAt,
                        endsAt: group.endsAt,
                        now: now,
                      ),
                      key: AppKeys.countdown,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.groups_outlined,
                title: 'Vagas',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${group.filledSpots} de ${group.totalSpots} vagas',
                      key: AppKeys.spotSummary,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: scheme.primaryContainer,
                        color: group.isFull
                            ? scheme.onSurfaceVariant
                            : scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      GroupMessages.phaseLabel(
                        group.phaseAt(now),
                        missing: group.spotsUntilClose,
                        started: started,
                      ),
                      key: AppKeys.groupPhase,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (group.showCloseDeadline(now))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          GroupMessages.closesAtLabel(
                            formatSession(group.closesAtResolved),
                          ),
                          key: AppKeys.closeDeadline,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'O grupo quer ${group.totalSpots} pessoas. '
                      'A sala comporta até ${group.roomCapacity}.',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                    if (me != null &&
                        me.occupiesSeat &&
                        !group.isCancelled &&
                        now.isBefore(group.startsAt))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(GroupMessages.attendanceOptional),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      GroupMessages.confirmedCount(group.confirmedCount),
                      key: AppKeys.confirmedCount,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.payments_outlined,
                title: 'Pagamento',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPrice(group.priceCents),
                      key: AppKeys.priceLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Por pessoa · pagamento simulado. Nada é cobrado de verdade.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
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
                    const SizedBox(height: 8),
                    Text(
                      GroupMessages.cancelWindowLabel(
                        group.cancelWindow.inHours,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              if (group.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Recado',
                  child: Text(
                    group.note,
                    key: AppKeys.groupNote,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _RoomProfile(
                group: group,
                photos: photos,
                addressQuery: addressQuery,
              ),
              const SizedBox(height: 20),
              _SectionCard(
                icon: Icons.people_outline,
                title: group.isCancelled ? 'Quem estava' : 'Quem já está',
                child: Column(
                  children: [
                    for (final person in roster)
                      if (_visible(person))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: Text(_initial(person.displayName)),
                          ),
                          title: Text(person.displayName),
                          subtitle: Text(_personSubtitle(person)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_canModerate(person))
                                PopupMenuButton<String>(
                                  key: AppKeys.memberMenu(person.id),
                                  onSelected: (value) {
                                    if (value == 'block') {
                                      _block(person);
                                    } else {
                                      _report(person);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'report',
                                      child: Text(GroupMessages.report),
                                    ),
                                    PopupMenuItem(
                                      value: 'block',
                                      child: Text(GroupMessages.block),
                                    ),
                                  ],
                                ),
                              if (_canRemove(group, userId, now, person))
                                TextButton(
                                  key: AppKeys.removeMember(person.id),
                                  onPressed: _busy
                                      ? null
                                      : () => _remove(person),
                                  child: const Text('Remover'),
                                ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
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

  bool _visible(Participant person) {
    final viewer = ref.read(authSessionProvider);
    if (viewer == null) {
      return true;
    }
    final key = CommunityBoard.personKey(
      userId: person.userId,
      seatId: person.id,
    );
    return !ref.read(communityBoardProvider).isBlocked(viewer.id, key);
  }

  bool _canModerate(Participant person) {
    final viewer = ref.read(authSessionProvider);
    if (viewer == null) {
      return false;
    }
    return person.userId != viewer.id;
  }

  void _block(Participant person) {
    final viewer = ref.read(authSessionProvider);
    if (viewer == null) {
      return;
    }
    ref
        .read(communityBoardProvider)
        .block(
          viewer.id,
          CommunityBoard.personKey(userId: person.userId, seatId: person.id),
        );
    ref.read(communityTickProvider.notifier).bump();
    setState(() {});
    _snack(GroupMessages.blockedSnack);
  }

  Future<void> _report(Participant person) async {
    final viewer = ref.read(authSessionProvider);
    if (viewer == null) {
      return;
    }
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text(GroupMessages.report),
          children: [
            for (final item in ReportReason.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Text(_reportLabel(item)),
              ),
          ],
        );
      },
    );
    if (reason == null) {
      return;
    }
    ref
        .read(communityBoardProvider)
        .report(
          byUserId: viewer.id,
          targetKey: CommunityBoard.personKey(
            userId: person.userId,
            seatId: person.id,
          ),
          reason: reason,
          at: ref.read(clockProvider).now(),
        );
    if (mounted) {
      _snack(GroupMessages.reportedSnack);
    }
  }

  String _reportLabel(ReportReason reason) {
    return switch (reason) {
      ReportReason.harassment => 'Assédio',
      ReportReason.spam => 'Spam',
      ReportReason.noShow => 'Falta sem aviso',
      ReportReason.other => 'Outro motivo',
    };
  }

  bool _canRemove(
    Group group,
    String userId,
    DateTime now,
    Participant person,
  ) {
    return _canEdit(group, userId, now) &&
        !GroupRules.hasStarted(startsAt: group.startsAt, now: now) &&
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
        if (started) {
          buttons.add(
            Text(
              GroupMessages.sessionAlreadyStarted,
              key: AppKeys.sessionStarted,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          );
        } else {
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
        }
      } else {
        buttons.add(
          OutlinedButton(
            key: AppKeys.leaveGroup,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : () => _leave(group),
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
      } else if (_openOffer(group, now) != null) {
        buttons.add(
          FilledButton(
            key: AppKeys.waitlistAccept,
            onPressed: _busy ? null : () => _acceptOffer(group),
            child: const Text(GroupMessages.waitlistAccept),
          ),
        );
        buttons.add(
          OutlinedButton(
            key: AppKeys.waitlistDecline,
            onPressed: _busy ? null : () => _declineOffer(group),
            child: const Text(GroupMessages.waitlistDecline),
          ),
        );
      } else if (started) {
        buttons.add(
          const FilledButton(
            onPressed: null,
            child: Text('Este grupo já começou'),
          ),
        );
      } else if (_seatReserved(group, now)) {
        buttons.add(
          const FilledButton(
            onPressed: null,
            child: Text(GroupMessages.seatReserved),
          ),
        );
        buttons.add(
          OutlinedButton(
            key: AppKeys.joinWaitlist,
            onPressed: _busy ? null : () => _wait(group),
            child: const Text(GroupMessages.waitlistJoin),
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
        buttons.add(
          OutlinedButton(
            key: AppKeys.joinWaitlist,
            onPressed: _busy ? null : () => _wait(group),
            child: const Text(GroupMessages.waitlistJoin),
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

  WaitlistEntry? _openOffer(Group group, DateTime now) {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      return null;
    }
    final entry = ref
        .read(communityBoardProvider)
        .entryFor(group.id, session.id);
    if (entry == null ||
        !ref.read(communityBoardProvider).offerStillOpen(entry, now)) {
      return null;
    }
    return entry;
  }

  bool _seatReserved(Group group, DateTime now) {
    final session = ref.read(authSessionProvider);
    final held = ref
        .read(communityBoardProvider)
        .openOfferCount(group.id, now, exceptUserId: session?.id);
    return group.openSeats > 0 && group.openSeats <= held;
  }

  Future<void> _acceptOffer(Group group) async {
    final user = ref.read(authSessionProvider);
    if (user == null) {
      return;
    }
    await _run(() async {
      final result = await ref
          .read(groupRepositoryProvider)
          .acceptWaitlist(
            groupId: group.id,
            userId: user.id,
            displayName: user.displayName,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(groupDetailViewModelProvider(group.id));
      ref.invalidate(findGroupsViewModelProvider);
      ref.invalidate(myGroupsViewModelProvider);
      final message = switch (result) {
        JoinSuccess() => 'Você entrou no grupo.',
        JoinFailure(:final reason) => GroupMessages.joinFailure(reason),
      };
      _snack(message);
    });
  }

  Future<void> _declineOffer(Group group) async {
    final user = ref.read(authSessionProvider);
    if (user == null) {
      return;
    }
    await _run(() async {
      await ref
          .read(groupRepositoryProvider)
          .declineWaitlist(groupId: group.id, userId: user.id);
      if (!mounted) {
        return;
      }
      ref.read(communityTickProvider.notifier).bump();
      ref.invalidate(groupDetailViewModelProvider(group.id));
      _snack(GroupMessages.waitlistDeclined);
    });
  }

  Future<void> _wait(Group group) async {
    final user = ref.read(authSessionProvider);
    if (user == null) {
      return;
    }
    final message = await ref
        .read(groupRepositoryProvider)
        .joinWaitlist(
          groupId: group.id,
          userId: user.id,
          displayName: user.displayName,
        );
    if (!mounted) {
      return;
    }
    _snack(message ?? GroupMessages.waitlistJoined);
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

  Future<void> _leave(Group group) async {
    final previewRefunds = GroupRules.refundsOnParticipantCancel(
      startsAt: group.startsAt,
      now: ref.read(clockProvider).now(),
      window: group.cancelWindow,
    );
    final accepted = await showLeaveDialog(context, refunds: previewRefunds);
    if (!accepted || !mounted) {
      return;
    }
    setState(() => _leavePreview = previewRefunds);
    await _run(() async {
      final result = await ref
          .read(groupDetailViewModelProvider(widget.groupId).notifier)
          .leave();
      if (!mounted || result == null) {
        return;
      }
      final message = switch (result) {
        LeaveGroupSuccess(:final group) => _leaveSnack(
          group,
          previewRefunds: previewRefunds,
        ),
        LeaveGroupFailure() => GroupMessages.actionFailed,
      };
      _snack(message);
    });
  }

  String? _leaveMismatch(Participant? me) {
    final preview = _leavePreview;
    if (preview == null || me == null || me.occupiesSeat) {
      return null;
    }
    final refunded = me.refund == RefundStatus.refunded;
    if (refunded == preview) {
      return null;
    }
    return GroupMessages.leavePreviewChanged(refunded: refunded);
  }

  Participant? _local(Group group) {
    for (final person in group.participants) {
      if (person.isLocalUser) {
        return person;
      }
    }
    return null;
  }

  String _leaveSnack(Group group, {required bool previewRefunds}) {
    final refunded = _local(group)?.refund == RefundStatus.refunded;
    if (refunded != previewRefunds) {
      return GroupMessages.leavePreviewChanged(refunded: refunded);
    }
    return refunded ? GroupMessages.leaveRefunded : GroupMessages.leaveDenied;
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
            : GroupMessages.deleteFailure(reason),
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
            : GroupMessages.removeFailure(reason),
      );
    });
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

/// Capa da sala escolhida. O Hero continua a foto do cartão.
class _GroupCover extends StatelessWidget {
  const _GroupCover({required this.group, this.categoryLabel});

  final Group group;
  final String? categoryLabel;

  static const height = 300.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = group.coverAsset;
    final photo = cover.isEmpty
        ? const ColoredBox(color: Color(0xFF0E1716))
        : ScapePhoto(asset: cover, semanticLabel: group.roomName);
    final framed = cover.isEmpty
        ? photo
        : HeroMode(
            enabled: scapeAnimationsEnabled(context),
            child: Hero(
              tag: groupHeroTag(group.id),
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox.expand(child: photo),
              ),
            ),
          );

    return SizedBox(
      key: AppKeys.groupCover,
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          framed,
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x330E1716),
                  Color(0x000E1716),
                  Color(0xCC0E1716),
                  Color(0xF20E1716),
                ],
                stops: [0, 0.28, 0.62, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categoryLabel != null) ...[
                  _CoverChip(label: categoryLabel!),
                  const SizedBox(height: 8),
                ],
                Text(
                  group.roomName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.houseName} · ${group.neighborhood}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                Text(
                  group.cityName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
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

class _CoverChip extends StatelessWidget {
  const _CoverChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Perfil da sala escolhida: fotos, história e a ficha, com o link completo.
class _RoomProfile extends StatelessWidget {
  const _RoomProfile({
    required this.group,
    required this.photos,
    required this.addressQuery,
  });

  final Group group;
  final List<String> photos;
  final String addressQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final address =
        '${group.streetAddress} · ${group.neighborhood} · ${group.cityName}';
    return _SectionCard(
      icon: Icons.meeting_room_outlined,
      title: 'Sobre a sala',
      child: Column(
        key: AppKeys.roomProfile,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photos.isNotEmpty) ...[
            SizedBox(
              key: AppKeys.groupRoomGallery,
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 148,
                      child: ScapePhoto(
                        asset: photos[index],
                        semanticLabel: '${group.roomName}, foto ${index + 1}',
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (group.roomTheme.isNotEmpty) ...[
            Text(
              'História',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              group.roomTheme,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 8),
          ],
          _FactRow(
            icon: Icons.timer_outlined,
            label: 'Duração',
            value: '${group.durationMinutes} min',
          ),
          _FactRow(
            icon: Icons.speed,
            label: 'Dificuldade',
            value: group.difficulty.labelPt,
          ),
          _FactRow(
            icon: Icons.groups_outlined,
            label: 'Capacidade',
            value: 'Até ${group.roomCapacity} pessoas',
          ),
          _FactRow(
            icon: Icons.payments_outlined,
            label: 'Preço',
            value: '${formatPrice(group.priceCents)} por pessoa',
          ),
          _FactRow(
            icon: Icons.storefront_outlined,
            label: 'Casa',
            value: group.houseName,
          ),
          if (group.streetAddress.isNotEmpty) ...[
            _FactRow(
              icon: Icons.place_outlined,
              label: 'Endereço',
              value: address,
              valueKey: AppKeys.roomAddress,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: AppKeys.openMaps,
                  onPressed: () => openExternalUrl(googleMapsUri(addressQuery)),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text(GroupMessages.openMaps),
                ),
                OutlinedButton.icon(
                  key: AppKeys.openWaze,
                  onPressed: () => openExternalUrl(wazeUri(addressQuery)),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text(GroupMessages.openWaze),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            key: AppKeys.openRoomDetail,
            onPressed: () => context.push('/salas/${group.roomId}'),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Ver a sala completa'),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  key: valueKey,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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
