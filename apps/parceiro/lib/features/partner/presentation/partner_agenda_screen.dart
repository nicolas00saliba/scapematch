import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const agendaPalette = <int>[
  0xFF0F4C4A,
  0xFFD2642A,
  0xFF1F6F8A,
  0xFF8A4B2F,
  0xFF3E6B4F,
  0xFFB45309,
  0xFF5C4B8A,
  0xFF8A3A4B,
];

const agendaHours = <(int, int)>[(14, 0), (16, 30), (19, 0), (21, 0)];

Color roomColor(EscapeRoom room, int index) {
  final value = room.accent == 0
      ? agendaPalette[index % agendaPalette.length]
      : room.accent;
  return Color(value);
}

class PartnerAgenda extends ConsumerStatefulWidget {
  const PartnerAgenda({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  ConsumerState<PartnerAgenda> createState() => _PartnerAgendaState();
}

enum _AgendaMode { calendar, list }

enum _ListBucket { upcoming, done, cancelled }

class _PartnerAgendaState extends ConsumerState<PartnerAgenda> {
  var _mode = _AgendaMode.calendar;
  var _bucket = _ListBucket.upcoming;
  late DateTime _weekStart;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(widget.snapshot.now);
    _weekStart = _monday(today);
    _day = today;
  }

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    final colors = {
      for (var i = 0; i < widget.snapshot.rooms.length; i++)
        widget.snapshot.rooms[i].id: roomColor(widget.snapshot.rooms[i], i),
    };
    final body = _mode == _AgendaMode.list
        ? _TicketList(
            snapshot: widget.snapshot,
            colors: colors,
            bucket: _bucket,
            onBucket: (bucket) => setState(() => _bucket = bucket),
            onOpen: (group) => _showGroup(context, group),
          )
        : wide
        ? _WeekBoard(
            snapshot: widget.snapshot,
            colors: colors,
            weekStart: _weekStart,
            onPrevious: () => setState(() {
              _weekStart = _weekStart.subtract(const Duration(days: 7));
            }),
            onNext: () => setState(() {
              _weekStart = _weekStart.add(const Duration(days: 7));
            }),
            onOpen: (item) => _openItem(context, item),
          )
        : _DayBoard(
            snapshot: widget.snapshot,
            colors: colors,
            weekStart: _weekStart,
            day: _day,
            onDay: (day) => setState(() => _day = day),
            onOpen: (item) => _openItem(context, item),
          );
    return Stack(
      children: [
        Column(
          children: [
            _AgendaBar(
              mode: _mode,
              onMode: (mode) => setState(() => _mode = mode),
              onAdd: () => _showAddSession(context),
              onRooms: () => _showRooms(context),
            ),
            Expanded(child: body),
          ],
        ),
        if (!wide)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              key: PartnerKeys.agendaAdd,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              shape: const CircleBorder(),
              onPressed: () => _showAddSession(context),
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Future<void> _openItem(BuildContext context, _AgendaItem item) async {
    final group = item.group;
    if (group == null) {
      await _showAddSession(
        context,
        roomId: item.room.id,
        startsAt: item.startsAt,
      );
      return;
    }
    await _showGroup(context, group);
  }

  Future<void> _showGroup(BuildContext context, Group group) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _SessionSheet(snapshot: widget.snapshot, group: group);
      },
    );
  }

  Future<void> _showAddSession(
    BuildContext context, {
    String? roomId,
    DateTime? startsAt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _AddSessionSheet(
          snapshot: widget.snapshot,
          roomId: roomId,
          startsAt: startsAt,
        );
      },
    );
  }

  Future<void> _showRooms(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RoomsSheet(snapshot: widget.snapshot),
    );
  }
}

class _AgendaBar extends StatelessWidget {
  const _AgendaBar({
    required this.mode,
    required this.onMode,
    required this.onAdd,
    required this.onRooms,
  });

  final _AgendaMode mode;
  final ValueChanged<_AgendaMode> onMode;
  final VoidCallback onAdd;
  final VoidCallback onRooms;

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          SegmentedButton<_AgendaMode>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            selected: {mode},
            onSelectionChanged: (next) => onMode(next.first),
            segments: const [
              ButtonSegment(
                value: _AgendaMode.calendar,
                label: Text(PartnerMessages.agenda),
                icon: Icon(Icons.calendar_view_week),
              ),
              ButtonSegment(
                value: _AgendaMode.list,
                label: Text(PartnerMessages.agendaList),
                icon: Icon(Icons.confirmation_number_outlined),
              ),
            ],
          ),
          const Spacer(),
          if (wide) ...[
            FilledButton.tonalIcon(
              key: PartnerKeys.agendaAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(PartnerMessages.addSession),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: PartnerKeys.agendaRooms,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onRooms,
              icon: const Icon(Icons.meeting_room_outlined),
              label: const Text(PartnerMessages.manageRooms),
            ),
          ] else
            PopupMenuButton<String>(
              key: PartnerKeys.agendaRooms,
              onSelected: (_) => onRooms(),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'rooms',
                  child: Text(PartnerMessages.manageRooms),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WeekBoard extends StatelessWidget {
  const _WeekBoard({
    required this.snapshot,
    required this.colors,
    required this.weekStart,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
  });

  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final DateTime weekStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<_AgendaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))];
    final end = days.last;
    final title =
        '${DateFormat('d MMM', 'pt_BR').format(weekStart)} – ${DateFormat('d MMM', 'pt_BR').format(end)}';
    final rooms = [
      for (final room in snapshot.rooms)
        if (days.any(
          (day) => _itemsOn(snapshot, colors, day).any(
            (item) => item.room.id == room.id && item.group != null,
          ),
        ))
          room,
    ];
    return ListView(
      key: PartnerKeys.agendaCalendar,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: 132),
            for (final day in days)
              Expanded(
                child: Center(
                  child: Text(
                    _dayHeading(day),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final room in rooms) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors[room.id],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          room.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _DayCell(
                      items: _itemsOn(snapshot, colors, day)
                          .where((item) => item.room.id == room.id)
                          .toList(),
                      onOpen: onOpen,
                      showRoom: false,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.items,
    required this.onOpen,
    this.showRoom = true,
  });

  final List<_AgendaItem> items;
  final ValueChanged<_AgendaItem> onOpen;
  final bool showRoom;

  @override
  Widget build(BuildContext context) {
    final booked = [for (final item in items) if (item.group != null) item];
    final free = items.length - booked.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in booked)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _BlockTile(
              item: item,
              showRoom: showRoom,
              onTap: () => onOpen(item),
            ),
          ),
        if (free > 0)
          _FreeChip(
            count: free,
            onTap: () => onOpen(items.firstWhere((item) => item.group == null)),
          ),
      ],
    );
  }
}

class _FreeChip extends StatelessWidget {
  const _FreeChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count == 1 ? '+ livre' : '$count livres';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: _DashedRRectPainter(scheme.outlineVariant),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _DayBoard extends StatelessWidget {
  const _DayBoard({
    required this.snapshot,
    required this.colors,
    required this.weekStart,
    required this.day,
    required this.onDay,
    required this.onOpen,
  });

  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final DateTime weekStart;
  final DateTime day;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<_AgendaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))];
    final items = _itemsOn(snapshot, colors, day);
    final byRoom = <String, List<_AgendaItem>>{};
    for (final item in items) {
      byRoom.putIfAbsent(item.room.id, () => []).add(item);
    }
    return ListView(
      key: PartnerKeys.agendaCalendar,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final date in days)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_dayHeading(date)),
                    selected: _sameDay(date, day),
                    onSelected: (_) => onDay(date),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Legend(
          snapshot: snapshot,
          colors: colors,
          onlyRoomIds: {
            for (final item in items)
              if (item.group != null) item.room.id,
          },
        ),
        const SizedBox(height: 12),
        if (byRoom.isEmpty)
          const Text(PartnerMessages.noSessions)
        else
          for (final room in snapshot.rooms)
            if (byRoom[room.id] != null) ...[
              Text(
                room.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _DayCell(items: byRoom[room.id]!, onOpen: onOpen, showRoom: false),
              const SizedBox(height: 16),
            ],
      ],
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.item,
    required this.onTap,
    this.showRoom = true,
  });

  final _AgendaItem item;
  final VoidCallback onTap;
  final bool showRoom;

  @override
  Widget build(BuildContext context) {
    final tone = Colors.white;
    return Material(
      key: PartnerKeys.agendaBlock(item.id),
      color: item.color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showRoom)
                Text(
                  item.room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: tone,
                  ),
                ),
              Text(
                '${_hm(item.startsAt.hour, item.startsAt.minute)} · ${item.group!.filledSpots}/${item.group!.totalSpots}',
                style: TextStyle(fontSize: 11, color: tone, fontWeight: FontWeight.w700),
              ),
              Text(
                item.status,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.snapshot, required this.colors, this.onlyRoomIds});

  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final Set<String>? onlyRoomIds;

  @override
  Widget build(BuildContext context) {
    final rooms = [
      for (final room in snapshot.rooms)
        if (onlyRoomIds == null || onlyRoomIds!.contains(room.id)) room,
    ];
    if (rooms.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final room in rooms)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors[room.id],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(room.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({
    required this.snapshot,
    required this.colors,
    required this.bucket,
    required this.onBucket,
    required this.onOpen,
  });

  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final _ListBucket bucket;
  final ValueChanged<_ListBucket> onBucket;
  final ValueChanged<Group> onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = snapshot.groups.where((group) {
      final ended = !snapshot.now.isBefore(group.endsAt);
      return switch (bucket) {
        _ListBucket.cancelled => group.isCancelled,
        _ListBucket.done => !group.isCancelled && ended,
        _ListBucket.upcoming => !group.isCancelled && !ended,
      };
    }).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return ListView(
      key: PartnerKeys.agendaList,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final item in _ListBucket.values)
              ChoiceChip(
                label: Text(_bucketLabel(item)),
                selected: item == bucket,
                onSelected: (_) => onBucket(item),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const Text(PartnerMessages.noSessions)
        else
          for (final group in groups) ...[
            _Ticket(
              snapshot: snapshot,
              group: group,
              color: colors[group.roomId] ?? Theme.of(context).colorScheme.primary,
              onTap: () => onOpen(group),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.snapshot,
    required this.group,
    required this.color,
    required this.onTap,
  });

  final PartnerSnapshot snapshot;
  final Group group;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = snapshot.moneyFor(group.id);
    final status = _statusOf(group);
    final absences = [
      for (final person in group.participants)
        if (person.occupiesSeat &&
            snapshot.markedAbsent(group.id, playerIdOf(person)))
          person.displayName,
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ClipPath(
          clipper: const _TicketClipper(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 6)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hm(group.startsAt.hour, group.startsAt.minute),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _dateLine(group.startsAt),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot.roomNameFor(group),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${group.filledSpots}/${group.totalSpots} · ${PartnerMessages.netLabel} ${formatPrice(money.netCents)}',
              ),
              if (absences.isNotEmpty)
                Text('${PartnerMessages.noShows}: ${absences.join(', ')}'),
              if (group.isCancelled)
                Text(
                  group.cancelReason.isEmpty
                      ? 'O grupo não fechou'
                      : group.cancelReason,
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

class _SessionSheet extends ConsumerWidget {
  const _SessionSheet({required this.snapshot, required this.group});

  final PartnerSnapshot snapshot;
  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = snapshot.moneyFor(group.id);
    final started = !snapshot.now.isBefore(group.startsAt);
    final people = [
      for (final person in group.participants)
        if (person.occupiesSeat) person,
    ];
    return Padding(
      key: PartnerKeys.agendaSheet,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            snapshot.roomNameFor(group),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(formatSession(group.startsAt)),
          const SizedBox(height: 8),
          Text(
            '${_statusOf(group)} · ${group.filledSpots}/${group.totalSpots}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            '${PartnerMessages.grossLabel} ${formatPrice(money.grossCents)} · ${PartnerMessages.commissionLabel} ${formatPrice(money.commissionCents)} · ${PartnerMessages.netLabel} ${formatPrice(money.netCents)}',
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            const Text('Ninguém entrou ainda.')
          else
            for (final person in people)
              _SheetPerson(
                snapshot: snapshot,
                group: group,
                person: person,
                canMark: started && !group.isCancelled,
              ),
          if (!group.isCancelled && snapshot.now.isBefore(group.startsAt)) ...[
            const SizedBox(height: 12),
            FilledButton(
              key: PartnerKeys.agendaCancel,
              onPressed: () async {
                final error = await ref.read(partnerRepositoryProvider).cancelSession(
                  houseId: snapshot.house.id,
                  groupId: group.id,
                  reason: 'Cancelada pela casa',
                );
                if (!context.mounted) {
                  return;
                }
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                  return;
                }
                ref.read(partnerRevisionProvider.notifier).bump();
                Navigator.pop(context);
              },
              child: const Text(PartnerMessages.cancelSession),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetPerson extends ConsumerWidget {
  const _SheetPerson({
    required this.snapshot,
    required this.group,
    required this.person,
    required this.canMark,
  });

  final PartnerSnapshot snapshot;
  final Group group;
  final Participant person;
  final bool canMark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerId = playerIdOf(person);
    final marked = snapshot.markedAbsent(group.id, playerId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${person.displayName} · ${GroupMessages.paymentStatus(person.payment)}'),
      subtitle: marked
          ? Text(
              PartnerMessages.absenceLine(
                snapshot.absenceCount(playerId),
                snapshot.standingOf(playerId),
              ),
              key: PartnerKeys.partnerAbsenceStanding(group.id, playerId),
            )
          : null,
      trailing: !marked && canMark
          ? TextButton(
              key: PartnerKeys.partnerAbsence(group.id, playerId),
              onPressed: () {
                final result = ref.read(partnerRepositoryProvider).markAbsence(
                  houseId: snapshot.house.id,
                  groupId: group.id,
                  playerId: playerId,
                );
                if (result is AbsenceRejected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.message)),
                  );
                  return;
                }
                ref.read(partnerRevisionProvider.notifier).bump();
                Navigator.pop(context);
              },
              child: const Text(PartnerMessages.markAbsence),
            )
          : null,
    );
  }
}

class _AddSessionSheet extends ConsumerStatefulWidget {
  const _AddSessionSheet({
    required this.snapshot,
    this.roomId,
    this.startsAt,
  });

  final PartnerSnapshot snapshot;
  final String? roomId;
  final DateTime? startsAt;

  @override
  ConsumerState<_AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends ConsumerState<_AddSessionSheet> {
  late String _roomId;
  late DateTime _day;
  late (int, int) _hour;
  late final TextEditingController _price;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final rooms = widget.snapshot.rooms;
    _roomId = widget.roomId ?? rooms.first.id;
    final start = widget.startsAt ?? _nextOpening(widget.snapshot.now);
    _day = _dateOnly(start);
    _hour = (start.hour, start.minute);
    final room = rooms.firstWhere((item) => item.id == _roomId);
    _price = TextEditingController(text: reaisField(room.priceCents));
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
    final startsAt = DateTime(_day.year, _day.month, _day.day, _hour.$1, _hour.$2);
    final error = await ref.read(partnerRepositoryProvider).openSession(
      houseId: widget.snapshot.house.id,
      roomId: _roomId,
      startsAt: startsAt,
      priceCents: cents,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.read(partnerRevisionProvider.notifier).bump();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 0; i < 7; i++)
        _dateOnly(widget.snapshot.now).add(Duration(days: i)),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            PartnerMessages.addSession,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _roomId,
            decoration: const InputDecoration(
              labelText: 'Sala',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final room in widget.snapshot.rooms)
                DropdownMenuItem(value: room.id, child: Text(room.name)),
            ],
            onChanged: (id) {
              if (id == null) {
                return;
              }
              final room = widget.snapshot.rooms.firstWhere((item) => item.id == id);
              setState(() {
                _roomId = id;
                _price.text = reaisField(room.priceCents);
              });
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final day in days)
                ChoiceChip(
                  label: Text(_dayHeading(day)),
                  selected: _sameDay(day, _day),
                  onSelected: (_) => setState(() => _day = day),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final hour in agendaHours)
                ChoiceChip(
                  key: PartnerKeys.agendaTime(_hm(hour.$1, hour.$2)),
                  label: Text(_hm(hour.$1, hour.$2)),
                  selected: _hour == hour,
                  onSelected: (_) => setState(() => _hour = hour),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: PartnerMessages.priceLabel,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: PartnerKeys.agendaSaveSession,
            onPressed: _busy ? null : _save,
            child: const Text(PartnerMessages.openSession),
          ),
        ],
      ),
    );
  }
}

class _RoomsSheet extends ConsumerStatefulWidget {
  const _RoomsSheet({required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  ConsumerState<_RoomsSheet> createState() => _RoomsSheetState();
}

class _RoomsSheetState extends ConsumerState<_RoomsSheet> {
  EscapeRoom? _editing;
  var _creating = false;

  @override
  Widget build(BuildContext context) {
    if (_creating || _editing != null) {
      return _RoomForm(
        snapshot: widget.snapshot,
        room: _editing,
        onClose: () => setState(() {
          _creating = false;
          _editing = null;
        }),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            PartnerMessages.manageRooms,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: PartnerKeys.agendaAddRoom,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => setState(() => _creating = true),
              icon: const Icon(Icons.add),
              label: const Text('Nova sala'),
            ),
          ),
          for (var i = 0; i < widget.snapshot.rooms.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: roomColor(widget.snapshot.rooms[i], i),
                radius: 8,
              ),
              title: Text(widget.snapshot.rooms[i].name),
              subtitle: Text(
                '${widget.snapshot.rooms[i].difficulty.labelPt} · ${widget.snapshot.rooms[i].minimumPlayers} a ${widget.snapshot.rooms[i].capacity} · ${formatPrice(widget.snapshot.rooms[i].priceCents)}',
              ),
              onTap: () => setState(() => _editing = widget.snapshot.rooms[i]),
            ),
        ],
      ),
    );
  }
}

class _RoomForm extends ConsumerStatefulWidget {
  const _RoomForm({
    required this.snapshot,
    required this.room,
    required this.onClose,
  });

  final PartnerSnapshot snapshot;
  final EscapeRoom? room;
  final VoidCallback onClose;

  @override
  ConsumerState<_RoomForm> createState() => _RoomFormState();
}

class _RoomFormState extends ConsumerState<_RoomForm> {
  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _price;
  late Difficulty _difficulty;
  late int _accent;
  String? _error;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room?.name ?? '');
    _duration = TextEditingController(
      text: '${room?.durationMinutes ?? 60}',
    );
    _minimum = TextEditingController(text: '${room?.minimumPlayers ?? 2}');
    _maximum = TextEditingController(text: '${room?.capacity ?? 6}');
    _price = TextEditingController(
      text: reaisField(room?.priceCents ?? 10900),
    );
    _difficulty = room?.difficulty ?? Difficulty.medium;
    final index = room == null
        ? widget.snapshot.rooms.length
        : widget.snapshot.rooms.indexWhere((item) => item.id == room.id);
    _accent = room == null || room.accent == 0
        ? agendaPalette[index % agendaPalette.length]
        : room.accent;
  }

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final price = parseReais(_price.text);
    final error = ref.read(partnerRepositoryProvider).saveRoom(
      houseId: widget.snapshot.house.id,
      roomId: widget.room?.id,
      name: _name.text,
      difficulty: _difficulty,
      durationMinutes: int.tryParse(_duration.text.trim()) ?? 0,
      minimumPlayers: int.tryParse(_minimum.text.trim()) ?? 0,
      capacity: int.tryParse(_maximum.text.trim()) ?? 0,
      priceCents: price ?? 0,
      accent: _accent,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.read(partnerRevisionProvider.notifier).bump();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            widget.room == null ? 'Nova sala' : widget.room!.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: PartnerKeys.agendaRoomName,
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final level in Difficulty.values)
                ChoiceChip(
                  label: Text(level.labelPt),
                  selected: _difficulty == level,
                  onSelected: (_) => setState(() => _difficulty = level),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Duração (min)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mínimo',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maximum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Máximo',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: PartnerMessages.priceLabel,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final value in agendaPalette)
                GestureDetector(
                  onTap: () => setState(() => _accent = value),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _accent == value
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: PartnerKeys.agendaSaveRoom,
            onPressed: _save,
            child: const Text('Salvar sala'),
          ),
          TextButton(onPressed: widget.onClose, child: const Text('Voltar')),
        ],
      ),
    );
  }
}

class _AgendaItem {
  const _AgendaItem({
    required this.id,
    required this.room,
    required this.startsAt,
    required this.color,
    required this.status,
    this.group,
  });

  final String id;
  final EscapeRoom room;
  final DateTime startsAt;
  final Color color;
  final String status;
  final Group? group;
}

List<_AgendaItem> _itemsOn(
  PartnerSnapshot snapshot,
  Map<String, Color> colors,
  DateTime day,
) {
  final items = <_AgendaItem>[];
  final taken = <String>{};
  for (final group in snapshot.groups) {
    if (!_sameDay(group.startsAt, day)) {
      continue;
    }
    final room = _room(snapshot, group.roomId);
    if (room == null) {
      continue;
    }
    taken.add('${room.id}|${group.startsAt.toIso8601String()}');
    items.add(
      _AgendaItem(
        id: group.id,
        room: room,
        startsAt: group.startsAt,
        color: colors[room.id] ?? const Color(0xFF0F4C4A),
        status: _statusOf(group),
        group: group,
      ),
    );
  }
  for (final room in snapshot.rooms) {
    for (final slot in snapshot.slotsByRoom[room.id] ?? const []) {
      if (!_sameDay(slot.startsAt, day)) {
        continue;
      }
      final key = '${room.id}|${slot.startsAt.toIso8601String()}';
      if (taken.contains(key) || !slot.startsAt.isAfter(snapshot.now)) {
        continue;
      }
      if (!_houseHour(slot.startsAt)) {
        continue;
      }
      items.add(
        _AgendaItem(
          id: slot.id,
          room: room,
          startsAt: slot.startsAt,
          color: colors[room.id] ?? const Color(0xFF0F4C4A),
          status: PartnerMessages.free,
        ),
      );
    }
  }
  items.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return items;
}

EscapeRoom? _room(PartnerSnapshot snapshot, String id) {
  for (final room in snapshot.rooms) {
    if (room.id == id) {
      return room;
    }
  }
  return null;
}

String _bucketLabel(_ListBucket bucket) {
  return switch (bucket) {
    _ListBucket.upcoming => PartnerMessages.upcoming,
    _ListBucket.done => PartnerMessages.done,
    _ListBucket.cancelled => PartnerMessages.cancelledTab,
  };
}

String _statusOf(Group group) {
  if (group.isCancelled) {
    return PartnerMessages.cancelled;
  }
  if (group.isFull) {
    return PartnerMessages.closedGroup;
  }
  return PartnerMessages.openGroup;
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _monday(DateTime day) {
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateLine(DateTime day) {
  final raw = DateFormat("EEE, d 'de' MMM", 'pt_BR').format(day);
  if (raw.isEmpty) {
    return raw;
  }
  return raw[0].toUpperCase() + raw.substring(1);
}

bool _houseHour(DateTime time) {
  for (final hour in agendaHours) {
    if (time.hour == hour.$1 && time.minute == hour.$2) {
      return true;
    }
  }
  return false;
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 4;
        dashed.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + 3;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper();

  @override
  Path getClip(Size size) {
    const notch = 8.0;
    const radius = 14.0;
    final mid = size.height / 2;
    final card = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(radius),
        ),
      );
    final bites = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, mid), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(size.width, mid), radius: notch));
    return Path.combine(PathOperation.difference, card, bites);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

String _hm(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _dayHeading(DateTime day) {
  final raw = DateFormat('EEE d', 'pt_BR').format(day);
  if (raw.isEmpty) {
    return raw;
  }
  return raw[0].toUpperCase() + raw.substring(1);
}

DateTime _nextOpening(DateTime now) {
  var day = _dateOnly(now);
  for (var i = 0; i < 10; i++) {
    for (final hour in agendaHours) {
      final candidate = DateTime(day.year, day.month, day.day, hour.$1, hour.$2);
      if (candidate.isAfter(now.add(const Duration(hours: 1)))) {
        return candidate;
      }
    }
    day = day.add(const Duration(days: 1));
  }
  return now.add(const Duration(days: 1));
}
