import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';
import 'package:scapematch/features/auth/presentation/password_change_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_statement.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_agenda_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_payout_panel.dart';
import 'package:scapematch_parceiro/features/partner/presentation/empty_slot_card.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_referral_code.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_invoices_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_palette.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_room_form.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:scapematch_parceiro/partner_mark.dart';

class PartnerHome extends ConsumerWidget {
  const PartnerHome({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(partnerSectionProvider);
    final wide = isScapeDesktop(context);
    final body = switch (section) {
      PartnerSection.balance => _BalanceSection(snapshot: snapshot),
      PartnerSection.reservations => _ReservationsSection(snapshot: snapshot),
      PartnerSection.agenda => PartnerAgenda(snapshot: snapshot),
      PartnerSection.rooms => _RoomsSection(snapshot: snapshot),
      PartnerSection.invoices => PartnerInvoices(snapshot: snapshot),
    };
    return Scaffold(
      body: Column(
        children: [
          _PartnerBar(houseName: snapshot.house.name),
          if (!snapshot.house.receivesPayments) const PayoutPendingBanner(),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PartnerRail(selected: section),
                      Expanded(child: body),
                    ],
                  )
                : Column(
                    children: [
                      _PartnerTabs(selected: section),
                      Expanded(child: body),
                    ],
                  ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

class _PartnerBar extends ConsumerWidget {
  const _PartnerBar({required this.houseName});

  final String houseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final wide = isScapeDesktop(context);
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: wide ? 72 : 64,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12),
              child: Row(
                children: [
                  PartnerMark(height: wide ? 36 : 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (wide)
                          Text(
                            'EscapeMatch Parceiro',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        Text(
                          houseName,
                          key: PartnerKeys.partnerHouseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (wide
                                      ? Theme.of(context).textTheme.bodySmall
                                      : Theme.of(context).textTheme.titleMedium)
                                  ?.copyWith(
                                    color: wide
                                        ? scheme.onSurfaceVariant
                                        : null,
                                    fontWeight: wide ? null : FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (scapeUsesLiveBackend)
                    IconButton(
                      key: PartnerKeys.partnerChangePassword,
                      tooltip: 'Trocar senha',
                      onPressed: () {
                        showPasswordChangeDialog(
                          context: context,
                          changePassword: _changePartnerPassword,
                        );
                      },
                      icon: const Icon(Icons.password_outlined),
                    ),
                  if (wide)
                    TextButton(
                      key: PartnerKeys.partnerSignOut,
                      onPressed: () => _leave(ref),
                      child: const Text(PartnerMessages.signOut),
                    )
                  else
                    IconButton(
                      key: PartnerKeys.partnerSignOut,
                      tooltip: PartnerMessages.signOut,
                      onPressed: () => _leave(ref),
                      icon: const Icon(Icons.logout),
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

String _sectionLabel(PartnerSection section) {
  return switch (section) {
    PartnerSection.balance => PartnerMessages.balance,
    PartnerSection.reservations => PartnerMessages.reservations,
    PartnerSection.agenda => PartnerMessages.agenda,
    PartnerSection.rooms => PartnerMessages.rooms,
    PartnerSection.invoices => PartnerMessages.invoices,
  };
}

void _leave(WidgetRef ref) {
  ref.read(partnerSectionProvider.notifier).select(PartnerSection.balance);
  ref.read(partnerSessionProvider.notifier).signOut();
}

Future<String?> _changePartnerPassword(String password) async {
  final rejected = await rejectPassword(password);
  if (rejected != null) return rejected;
  try {
    await scapeSupabase.auth.updateUser(UserAttributes(password: password));
    return null;
  } on Object catch (error) {
    return authErrorMessage(
      error,
      fallback: 'Não foi possível trocar a senha. Tente de novo.',
    );
  }
}

class _PartnerRail extends ConsumerWidget {
  const _PartnerRail({required this.selected});

  final PartnerSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selected.index,
      onDestinationSelected: (index) {
        ref
            .read(partnerSectionProvider.notifier)
            .select(PartnerSection.values[index]);
      },
      labelType: NavigationRailLabelType.all,
      backgroundColor: scheme.surface,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: Text(PartnerMessages.balance),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note),
          label: Text(PartnerMessages.reservations),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: Text(PartnerMessages.agenda),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.meeting_room_outlined),
          selectedIcon: Icon(Icons.meeting_room),
          label: Text(PartnerMessages.rooms),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long),
          label: Text(PartnerMessages.invoices),
        ),
      ],
    );
  }
}

class _PartnerTabs extends ConsumerWidget {
  const _PartnerTabs({required this.selected});

  final PartnerSection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in PartnerSection.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  label: Text(_sectionLabel(section)),
                  selected: section == selected,
                  onSelected: (_) {
                    ref.read(partnerSectionProvider.notifier).select(section);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BalanceSection extends StatelessWidget {
  const _BalanceSection({required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 20, wide ? 32 : 16, 32),
      children: [
        const ExampleDataBanner(),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.balanceTitle,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          PartnerMessages.balanceBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 16),
        const VenueReferralCode(),
        const SizedBox(height: 16),
        EmptySlotCard(venueId: snapshot.house.id),
        const SizedBox(height: 16),
        _MoneyGrid(snapshot: snapshot),
        const SizedBox(height: 24),
        Text(
          PartnerMessages.statement,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (snapshot.lines.isEmpty)
          const Text(PartnerMessages.statementEmpty)
        else
          for (final line in snapshot.lines) ...[
            _StatementTile(line: line),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _MoneyGrid extends StatelessWidget {
  const _MoneyGrid({required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MoneyCard(
        label: PartnerMessages.netLabel,
        amount: formatPrice(snapshot.netCents),
        amountKey: PartnerKeys.partnerNet,
        emphasized: true,
      ),
      _MoneyCard(
        label: PartnerMessages.grossLabel,
        amount: formatPrice(snapshot.grossCents),
        amountKey: PartnerKeys.partnerGross,
      ),
      _MoneyCard(
        label: PartnerMessages.commissionLabel,
        amount: formatPrice(snapshot.commissionCents),
        amountKey: PartnerKeys.partnerCommission,
      ),
      _MoneyCard(
        label: PartnerMessages.reservedLabel,
        amount: formatPrice(snapshot.reservedCents),
        amountKey: PartnerKeys.partnerReserved,
        caption: PartnerMessages.reservedBody,
      ),
    ];
    final wide = isScapeDesktop(context);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final card in cards) ...[card, const SizedBox(height: 10)],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(child: cards[index]),
        ],
      ],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.label,
    required this.amount,
    required this.amountKey,
    this.caption,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final Key amountKey;
  final String? caption;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      color: emphasized ? scheme.primary : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: emphasized ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              key: amountKey,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: emphasized ? scheme.onPrimary : scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.line});

  final StatementLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.refund ? PartnerMessages.refund : PartnerMessages.capture,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              line.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '${PartnerMessages.grossLabel} ${formatPrice(line.grossCents)}',
                ),
                Text(
                  '${PartnerMessages.commissionLabel} ${formatPrice(line.commissionCents)}',
                ),
                Text(
                  '${PartnerMessages.netLabel} ${formatPrice(line.netCents)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReservationBucket { upcoming, done, cancelled }

class _ReservationsSection extends StatefulWidget {
  const _ReservationsSection({required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  State<_ReservationsSection> createState() => _ReservationsSectionState();
}

class _ReservationsSectionState extends State<_ReservationsSection> {
  var _bucket = _ReservationBucket.upcoming;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final wide = isScapeDesktop(context);
    final groups = snapshot.groups.where((group) {
      final ended = !snapshot.now.isBefore(group.endsAt);
      return switch (_bucket) {
        _ReservationBucket.cancelled => group.isCancelled,
        _ReservationBucket.done => !group.isCancelled && ended,
        _ReservationBucket.upcoming => !group.isCancelled && !ended,
      };
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 20, wide ? 32 : 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PartnerMessages.reservationsTitle,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final bucket in _ReservationBucket.values)
                    ChoiceChip(
                      key: _bucketKey(bucket),
                      label: Text(_bucketLabel(bucket)),
                      selected: bucket == _bucket,
                      onSelected: (_) => setState(() => _bucket = bucket),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(PartnerMessages.noReservations),
                )
              : ListView(
                  key: PartnerKeys.agendaList,
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 16,
                    12,
                    wide ? 32 : 16,
                    32,
                  ),
                  children: [
                    for (var i = 0; i < groups.length; i += wide ? 2 : 1) ...[
                      if (wide && i + 1 < groups.length)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _card(snapshot, groups[i])),
                            const SizedBox(width: 12),
                            Expanded(child: _card(snapshot, groups[i + 1])),
                          ],
                        )
                      else
                        _card(snapshot, groups[i]),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _card(PartnerSnapshot snapshot, Group group) {
    return _GroupCard(
      group: group,
      snapshot: snapshot,
      onOpen: () =>
          showPartnerGroupSheet(context, snapshot: snapshot, group: group),
    );
  }
}

Key _bucketKey(_ReservationBucket bucket) {
  return switch (bucket) {
    _ReservationBucket.upcoming => PartnerKeys.agendaUpcoming,
    _ReservationBucket.done => PartnerKeys.agendaDone,
    _ReservationBucket.cancelled => PartnerKeys.agendaCancelled,
  };
}

String _bucketLabel(_ReservationBucket bucket) {
  return switch (bucket) {
    _ReservationBucket.upcoming => PartnerMessages.upcoming,
    _ReservationBucket.done => PartnerMessages.done,
    _ReservationBucket.cancelled => PartnerMessages.cancelledTab,
  };
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.snapshot,
    required this.onOpen,
  });

  final Group group;
  final PartnerSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final started = !snapshot.now.isBefore(group.startsAt);
    final confirmed = group.isConfirmed && !group.isCancelled;
    final badge = group.isCancelled
        ? PartnerMessages.cancelled
        : group.isFull
        ? PartnerMessages.closedGroup
        : confirmed
        ? PartnerMessages.confirmedGroup
        : PartnerMessages.openGroup;
    final progress = group.isCancelled
        ? PartnerMessages.cancelled
        : confirmed
        ? PartnerMessages.paidOf(group.paidSeats, group.totalSpots)
        : PartnerMessages.reservedOf(group.reservedSeats, group.totalSpots);
    final money = snapshot.moneyFor(group.id);
    final people = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];
    final absences = [
      for (final person in people)
        if (snapshot.markedAbsent(group.id, playerIdOf(person)))
          person.displayName,
    ];
    final roomIndex = snapshot.rooms.indexWhere(
      (room) => room.id == group.roomId,
    );
    final accent = roomIndex < 0
        ? scheme.primary
        : roomColor(snapshot.rooms[roomIndex], roomIndex);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(color: accent, child: const SizedBox(width: 6)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _hm(group.startsAt),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          _StatusBadge(label: badge),
                        ],
                      ),
                      Text(
                        formatSession(group.startsAt),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.roomNameFor(group),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        progress,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        PartnerMessages.perPerson(
                          formatPrice(group.priceCents),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          Text(
                            '${PartnerMessages.grossLabel} ${formatPrice(money.grossCents)}',
                          ),
                          Text(
                            '${PartnerMessages.commissionLabel} ${formatPrice(money.commissionCents)}',
                          ),
                          Text(
                            '${PartnerMessages.netLabel} ${formatPrice(money.netCents)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      if (group.isCancelled &&
                          group.cancelReason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(group.cancelReason),
                      ],
                      if (absences.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${PartnerMessages.noShows}: ${absences.join(', ')}',
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (people.isEmpty && !group.isCancelled)
                        const Text(PartnerMessages.nobodyYet)
                      else if (people.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final person in people)
                              _PlayerChip(
                                group: group,
                                person: person,
                                snapshot: snapshot,
                                canMark: started && !group.isCancelled,
                              ),
                          ],
                        ),
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

String _hm(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closed = label == PartnerMessages.closedGroup;
    final cancelled = label == PartnerMessages.cancelled;
    final background = closed
        ? scheme.primary
        : cancelled
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = closed
        ? scheme.onPrimary
        : cancelled
        ? scheme.onErrorContainer
        : scheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PlayerChip extends ConsumerWidget {
  const _PlayerChip({
    required this.group,
    required this.person,
    required this.snapshot,
    required this.canMark,
  });

  final Group group;
  final Participant person;
  final PartnerSnapshot snapshot;
  final bool canMark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final playerId = playerIdOf(person);
    final marked = snapshot.markedAbsent(group.id, playerId);
    final count = snapshot.absenceCount(playerId);
    final standing = snapshot.standingOf(playerId);
    final status = GroupMessages.paymentStatus(person.payment);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${person.displayName} · $status',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (marked)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  PartnerMessages.absenceLine(count, standing),
                  key: PartnerKeys.partnerAbsenceStanding(group.id, playerId),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              )
            else if (canMark)
              TextButton(
                key: PartnerKeys.partnerAbsence(group.id, playerId),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                onPressed: () => _mark(context, ref, playerId),
                child: const Text(PartnerMessages.markAbsence),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _mark(
    BuildContext context,
    WidgetRef ref,
    String playerId,
  ) async {
    final houseId = snapshot.house.id;
    final result = await ref
        .read(partnerRepositoryProvider)
        .markAbsence(houseId: houseId, groupId: group.id, playerId: playerId);
    if (!context.mounted) return;
    if (result is AbsenceRejected) {
      _snack(context, result.message);
      return;
    }
    ref.read(partnerRevisionProvider.notifier).bump();
  }
}

class _RoomsSection extends StatelessWidget {
  const _RoomsSection({required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 20, wide ? 32 : 16, 32),
      children: [
        Text(
          PartnerMessages.roomsTitle,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          PartnerMessages.roomsBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: PartnerKeys.agendaAddRoom,
            onPressed: () async {
              final saved = await showPartnerRoomForm(
                context,
                snapshot: snapshot,
              );
              if (saved == true && context.mounted) {
                _snack(context, PartnerMessages.roomSaved);
              }
            },
            icon: const Icon(Icons.add),
            label: const Text(PartnerMessages.newRoom),
          ),
        ),
        const SizedBox(height: 16),
        for (final room in snapshot.rooms) ...[
          _RoomEditor(
            snapshot: snapshot,
            room: room,
            slots: snapshot.slotsByRoom[room.id] ?? const [],
            now: snapshot.now,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _RoomEditor extends ConsumerStatefulWidget {
  const _RoomEditor({
    required this.snapshot,
    required this.room,
    required this.slots,
    required this.now,
  });

  final PartnerSnapshot snapshot;
  final EscapeRoom room;
  final List<TimeSlot> slots;
  final DateTime now;

  @override
  ConsumerState<_RoomEditor> createState() => _RoomEditorState();
}

class _RoomEditorState extends ConsumerState<_RoomEditor> {
  late final TextEditingController _price;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: reaisField(widget.room.priceCents));
  }

  @override
  void didUpdateWidget(covariant _RoomEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.priceCents != widget.room.priceCents &&
        reaisField(widget.room.priceCents) != _price.text) {
      _price.text = reaisField(widget.room.priceCents);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseReais(_price.text);
    if (cents == null) {
      setState(() => _error = 'Informe o preço em reais.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(partnerRepositoryProvider)
        .updatePrice(roomId: widget.room.id, priceCents: cents);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _snack(context, PartnerMessages.priceSaved);
    ref.read(partnerRevisionProvider.notifier).bump();
  }

  Future<void> _addSlot() async {
    final startsAt = _nextOpening(widget.now);
    await ref
        .read(partnerRepositoryProvider)
        .addSlot(roomId: widget.room.id, startsAt: startsAt);
    if (!mounted) {
      return;
    }
    _snack(context, PartnerMessages.slotOpened);
    ref.read(partnerRevisionProvider.notifier).bump();
  }

  Future<void> _removeSlot(TimeSlot slot) async {
    final label = formatSession(slot.startsAt);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: PartnerKeys.removeSlotDialog,
          title: const Text(PartnerMessages.removeSlotTitle),
          content: Text(PartnerMessages.removeSlotBody(label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(PartnerMessages.removeSlotCancel),
            ),
            FilledButton(
              key: PartnerKeys.confirmRemoveSlot,
              onPressed: () => Navigator.pop(context, true),
              child: const Text(PartnerMessages.removeSlotConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final error = await ref
        .read(partnerRepositoryProvider)
        .removeSlot(roomId: widget.room.id, slotId: slot.id);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    _snack(context, error ?? PartnerMessages.slotRemoved);
    if (error == null) {
      ref.read(partnerRevisionProvider.notifier).bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final future = <TimeSlot>[];
    var past = 0;
    for (final slot in widget.slots) {
      if (!slot.startsAt.isAfter(widget.now)) {
        past += 1;
        continue;
      }
      future.add(slot);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.room.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final saved = await showPartnerRoomForm(
                      context,
                      snapshot: widget.snapshot,
                      room: widget.room,
                    );
                    if (saved == true && context.mounted) {
                      _snack(context, PartnerMessages.roomSaved);
                    }
                  },
                  child: const Text(PartnerMessages.editRoom),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.room.difficulty.labelPt} · ${widget.room.durationMinutes} min · ${widget.room.minimumPlayers} a ${widget.room.capacity}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: PartnerKeys.partnerPrice(widget.room.id),
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: PartnerMessages.priceLabel,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: PartnerKeys.partnerSavePrice(widget.room.id),
                onPressed: _busy ? null : _save,
                child: const Text(PartnerMessages.savePrice),
              ),
            ),
            const SizedBox(height: 12),
            if (future.isEmpty)
              Text(
                PartnerMessages.noFutureSlots,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final slot in future)
                    InputChip(
                      key: PartnerKeys.partnerRemoveSlot(slot.id),
                      label: Text(formatSession(slot.startsAt)),
                      deleteIcon: Icon(
                        Icons.close,
                        size: 18,
                        key: PartnerKeys.partnerRemoveSlotIcon(slot.id),
                      ),
                      deleteButtonTooltipMessage:
                          PartnerMessages.removeSlotTooltip,
                      onDeleted: _busy ? null : () => _removeSlot(slot),
                    ),
                ],
              ),
            if (past > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$past ${PartnerMessages.pastSlots}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              key: PartnerKeys.partnerAddSlot(widget.room.id),
              onPressed: _addSlot,
              child: const Text(PartnerMessages.addSlot),
            ),
          ],
        ),
      ),
    );
  }
}

DateTime _nextOpening(DateTime now) {
  const hours = <(int, int)>[(14, 0), (16, 30), (19, 0), (21, 0)];
  var day = DateTime(now.year, now.month, now.day);
  final earliest = now.add(const Duration(hours: 2));
  for (var i = 0; i < 14; i++) {
    for (final (hour, minute) in hours) {
      final candidate = DateTime(day.year, day.month, day.day, hour, minute);
      if (candidate.isAfter(earliest)) {
        return candidate;
      }
    }
    day = day.add(const Duration(days: 1));
  }
  return earliest;
}

void _snack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  final wide = MediaQuery.sizeOf(context).width >= scapeDesktopMinWidth;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: wide ? 480 : null,
        content: Text(message, textAlign: TextAlign.center),
      ),
    );
}
