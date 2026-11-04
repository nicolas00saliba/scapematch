import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_palette.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const _weekdayLetters = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
const _gutterWidth = 56.0;
const _nowColor = Color(0xFFE04F3A);

enum _AgendaView { day, threeDays, week, month }

Future<void> showPartnerGroupSheet(
  BuildContext context, {
  required PartnerSnapshot snapshot,
  required Group group,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SessionSheet(snapshot: snapshot, group: group),
  );
}

class PartnerAgenda extends ConsumerStatefulWidget {
  const PartnerAgenda({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  ConsumerState<PartnerAgenda> createState() => _PartnerAgendaState();
}

class _PartnerAgendaState extends ConsumerState<PartnerAgenda> {
  final ScrollController _scroll = ScrollController();
  late DateTime _focus;
  late DateTime _miniMonth;
  _AgendaView? _view;
  var _miniOpen = false;
  var _menuOpen = false;
  var _hourHeight = 56.0;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(widget.snapshot.now);
    _focus = today;
    _miniMonth = DateTime(today.year, today.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealNow());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  _AgendaView _resolved(bool wide) {
    return _view ?? (wide ? _AgendaView.week : _AgendaView.day);
  }

  void _selectView(_AgendaView view) {
    setState(() {
      _view = view;
      _menuOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealNow());
  }

  void _revealNow() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final now = widget.snapshot.now;
    final hour = now.hour + now.minute / 60;
    final target = (hour - agendaGridStartHour - 0.75) * _hourHeight;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(target.clamp(0.0, max));
  }

  void _shift(int direction) {
    final view = _resolved(isScapeDesktop(context));
    final next = switch (view) {
      _AgendaView.day => _focus.add(Duration(days: direction)),
      _AgendaView.threeDays => _focus.add(Duration(days: 3 * direction)),
      _AgendaView.week => _focus.add(Duration(days: 7 * direction)),
      _AgendaView.month => _addMonths(_focus, direction),
    };
    setState(() {
      _focus = _dateOnly(next);
      _miniMonth = DateTime(_focus.year, _focus.month);
    });
  }

  void _goToday() {
    final today = _dateOnly(widget.snapshot.now);
    setState(() {
      _focus = today;
      _miniMonth = DateTime(today.year, today.month);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealNow());
  }

  void _focusDay(DateTime day, {bool asDay = false}) {
    setState(() {
      _focus = _dateOnly(day);
      _miniMonth = DateTime(day.year, day.month);
      if (asDay) {
        _view = _AgendaView.day;
        _menuOpen = false;
      }
    });
    if (asDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    final view = _resolved(wide);
    _hourHeight = wide ? 68 : 56;
    final colors = {
      for (var i = 0; i < widget.snapshot.rooms.length; i++)
        widget.snapshot.rooms[i].id: roomColor(widget.snapshot.rooms[i], i),
    };
    final days = _daysOf(view, _focus);
    return Column(
      children: [
        _AgendaHeader(
          title: _titleFor(view),
          miniOpen: _miniOpen,
          showMenu: !wide,
          showChevrons: wide,
          onMenu: () => setState(() => _menuOpen = !_menuOpen),
          onTitle: () => setState(() => _miniOpen = !_miniOpen),
          onPrevious: () => _shift(-1),
          onNext: () => _shift(1),
          onToday: _goToday,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _miniOpen
              ? _MiniMonth(
                  month: _miniMonth,
                  focus: _focus,
                  today: widget.snapshot.now,
                  marked: _markedDays(widget.snapshot),
                  onPrevious: () => setState(() {
                    _miniMonth = DateTime(_miniMonth.year, _miniMonth.month - 1);
                  }),
                  onNext: () => setState(() {
                    _miniMonth = DateTime(_miniMonth.year, _miniMonth.month + 1);
                  }),
                  onDay: (day) => _focusDay(day),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    SizedBox(
                      width: 232,
                      child: _ViewDrawer(
                        view: view,
                        colors: colors,
                        snapshot: widget.snapshot,
                        onView: _selectView,
                      ),
                    ),
                  Expanded(
                    key: PartnerKeys.agendaCalendar,
                    child: GestureDetector(
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity > 250) {
                          _shift(-1);
                        } else if (velocity < -250) {
                          _shift(1);
                        }
                      },
                      child: view == _AgendaView.month
                          ? _MonthBoard(
                              focus: _focus,
                              snapshot: widget.snapshot,
                              colors: colors,
                              onDay: (day) => _focusDay(day, asDay: true),
                              onOpen: (group) => _showGroup(context, group),
                            )
                          : _TimeGrid(
                              days: days,
                              focus: _focus,
                              snapshot: widget.snapshot,
                              colors: colors,
                              hourHeight: _hourHeight,
                              scroll: _scroll,
                              collapseFree: view == _AgendaView.week,
                              onFocusDay: (day) => _focusDay(day, asDay: true),
                              onOpen: (group) => _showGroup(context, group),
                              onCreate: (roomId, startsAt) => _showAddSession(
                                context,
                                roomId: roomId,
                                startsAt: startsAt,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              if (!wide && _menuOpen) ...[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _menuOpen = false),
                    child: const ColoredBox(color: Color(0x52000000)),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 280,
                  child: _ViewDrawer(
                    view: view,
                    colors: colors,
                    snapshot: widget.snapshot,
                    onView: _selectView,
                  ),
                ),
              ],
              Positioned(
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: FloatingActionButton(
                  key: PartnerKeys.agendaAdd,
                  tooltip: PartnerMessages.addSession,
                  onPressed: () => _showAddSession(context),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _titleFor(_AgendaView view) {
    if (view == _AgendaView.week) {
      final start = _monday(_focus);
      final end = start.add(const Duration(days: 6));
      if (start.month != end.month) {
        final from = _cap(DateFormat('MMM', 'pt_BR').format(start));
        final to = _cap(DateFormat('MMM', 'pt_BR').format(end));
        return '$from – $to';
      }
    }
    if (view == _AgendaView.month) {
      return _cap(DateFormat('MMMM', 'pt_BR').format(_focus));
    }
    return _cap(DateFormat('MMMM', 'pt_BR').format(_focus));
  }

  Future<void> _showGroup(BuildContext context, Group group) {
    return showPartnerGroupSheet(
      context,
      snapshot: widget.snapshot,
      group: group,
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
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.title,
    required this.miniOpen,
    required this.showMenu,
    required this.showChevrons,
    required this.onMenu,
    required this.onTitle,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String title;
  final bool miniOpen;
  final bool showMenu;
  final bool showChevrons;
  final VoidCallback onMenu;
  final VoidCallback onTitle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            if (showMenu)
              IconButton(
                key: PartnerKeys.agendaViews,
                tooltip: PartnerMessages.agendaViews,
                onPressed: onMenu,
                icon: const Icon(Icons.menu),
              ),
            if (showChevrons)
              IconButton(
                tooltip: 'Anterior',
                visualDensity: VisualDensity.compact,
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
            InkWell(
              key: PartnerKeys.agendaMonthToggle,
              borderRadius: BorderRadius.circular(8),
              onTap: onTitle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AnimatedRotation(
                      turns: miniOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.arrow_drop_down),
                    ),
                  ],
                ),
              ),
            ),
            if (showChevrons)
              IconButton(
                tooltip: 'Próximo',
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            const Spacer(),
            TextButton(
              key: PartnerKeys.agendaToday,
              onPressed: onToday,
              child: const Text(PartnerMessages.today),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.month,
    required this.focus,
    required this.today,
    required this.marked,
    required this.onPrevious,
    required this.onNext,
    required this.onDay,
  });

  final DateTime month;
  final DateTime focus;
  final DateTime today;
  final Set<DateTime> marked;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month);
    final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final title = _cap(DateFormat("MMMM 'de' y", 'pt_BR').format(month));
    return Material(
      key: PartnerKeys.agendaMiniCalendar,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Mês anterior',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo mês',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final letter in _weekdayLetters)
                  Expanded(
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (var week = 0; week < 6; week++)
              Row(
                children: [
                  for (var day = 0; day < 7; day++)
                    Expanded(
                      child: _MiniDay(
                        day: start.add(Duration(days: week * 7 + day)),
                        month: month,
                        focus: focus,
                        today: today,
                        marked: marked,
                        onDay: onDay,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.day,
    required this.month,
    required this.focus,
    required this.today,
    required this.marked,
    required this.onDay,
  });

  final DateTime day;
  final DateTime month;
  final DateTime focus;
  final DateTime today;
  final Set<DateTime> marked;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = day.month == month.month && day.year == month.year;
    final isToday = _sameDay(day, today);
    final isFocus = _sameDay(day, focus);
    final has = marked.contains(_dateOnly(day));
    final numberColor = !inMonth
        ? scheme.outline
        : isToday
        ? scheme.onPrimary
        : scheme.onSurface;
    return InkWell(
      key: PartnerKeys.agendaMiniDay(day.year, day.month, day.day),
      onTap: () => onDay(day),
      child: SizedBox(
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday
                    ? scheme.primary
                    : isFocus
                    ? scheme.primaryContainer
                    : null,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: numberColor,
                ),
              ),
            ),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: has ? scheme.primary : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewDrawer extends StatelessWidget {
  const _ViewDrawer({
    required this.view,
    required this.colors,
    required this.snapshot,
    required this.onView,
  });

  final _AgendaView view;
  final Map<String, Color> colors;
  final PartnerSnapshot snapshot;
  final ValueChanged<_AgendaView> onView;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: scheme.outlineVariant)),
        ),
        child: ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                PartnerMessages.agendaViews,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final item in _AgendaView.values)
              _ViewTile(
                view: item,
                selected: item == view,
                onTap: () => onView(item),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                PartnerMessages.calendarRooms,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final room in snapshot.rooms)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[room.id],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
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

class _ViewTile extends StatelessWidget {
  const _ViewTile({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final _AgendaView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, key) = switch (view) {
      _AgendaView.day => (
        Icons.view_day_outlined,
        PartnerMessages.viewDay,
        PartnerKeys.agendaViewDay,
      ),
      _AgendaView.threeDays => (
        Icons.view_column_outlined,
        PartnerMessages.viewThreeDays,
        PartnerKeys.agendaViewThree,
      ),
      _AgendaView.week => (
        Icons.calendar_view_week_outlined,
        PartnerMessages.viewWeek,
        PartnerKeys.agendaViewWeek,
      ),
      _AgendaView.month => (
        Icons.calendar_view_month_outlined,
        PartnerMessages.viewMonth,
        PartnerKeys.agendaViewMonth,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.days,
    required this.focus,
    required this.snapshot,
    required this.colors,
    required this.hourHeight,
    required this.scroll,
    required this.collapseFree,
    required this.onFocusDay,
    required this.onOpen,
    required this.onCreate,
  });

  final List<DateTime> days;
  final DateTime focus;
  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final double hourHeight;
  final ScrollController scroll;
  final bool collapseFree;
  final ValueChanged<DateTime> onFocusDay;
  final ValueChanged<Group> onOpen;
  final void Function(String? roomId, DateTime startsAt) onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hours = agendaGridEndHour - agendaGridStartHour;
    final height = hours * hourHeight + 88;
    final showNow = days.any((day) => _sameDay(day, snapshot.now));
    final nowTop = _topFor(snapshot.now, hourHeight);
    return Column(
      children: [
        ColoredBox(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Row(
              children: [
                const SizedBox(width: _gutterWidth),
                for (final day in days)
                  Expanded(
                    child: _DateHeading(
                      day: day,
                      today: snapshot.now,
                      focus: focus,
                      solo: days.length == 1,
                      onTap: () => onFocusDay(day),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            child: SizedBox(
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HourGutter(hourHeight: hourHeight),
                      for (final day in days)
                        Expanded(
                          child: _DayColumn(
                            day: day,
                            today: snapshot.now,
                            events: _eventsFor(
                              snapshot,
                              colors,
                              day,
                              collapseFree: collapseFree,
                            ),
                            hourHeight: hourHeight,
                            onOpen: onOpen,
                            onCreate: onCreate,
                          ),
                        ),
                    ],
                  ),
                  if (showNow && nowTop >= 0)
                    Positioned(
                      top: nowTop - 5,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            const SizedBox(
                              width: _gutterWidth - 6,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _nowColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(width: 10, height: 10),
                                ),
                              ),
                            ),
                            const Expanded(
                              child: ColoredBox(
                                color: _nowColor,
                                child: SizedBox(height: 2),
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
      ],
    );
  }
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({
    required this.day,
    required this.today,
    required this.focus,
    required this.solo,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final DateTime focus;
  final bool solo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = _sameDay(day, today);
    final isFocus = _sameDay(day, focus);
    final label = solo
        ? _cap(DateFormat('EEEE', 'pt_BR').format(day))
        : _weekdayLetters[day.weekday - DateTime.monday];
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: solo ? 13 : 12,
              fontWeight: FontWeight.w700,
              color: isToday ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? scheme.primary : null,
              shape: BoxShape.circle,
              border: !isToday && isFocus
                  ? Border.all(color: scheme.primary, width: 2)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isToday ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.hourHeight});

  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return SizedBox(
      width: _gutterWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var hour = agendaGridStartHour; hour < agendaGridEndHour; hour++)
            Positioned(
              top: (hour - agendaGridStartHour) * hourHeight - 7,
              right: 8,
              child: Text(_hm(hour, 0), style: style),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.today,
    required this.events,
    required this.hourHeight,
    required this.onOpen,
    required this.onCreate,
  });

  final DateTime day;
  final DateTime today;
  final List<_CalEvent> events;
  final double hourHeight;
  final ValueChanged<Group> onOpen;
  final void Function(String? roomId, DateTime startsAt) onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = _sameDay(day, today);
    final placed = _place(events);
    final hours = agendaGridEndHour - agendaGridStartHour;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            onCreate(null, _snapHour(day, details.localPosition.dy, hourHeight));
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isToday ? scheme.primary.withValues(alpha: 0.04) : null,
              border: Border(left: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Stack(
              children: [
                for (var hour = 0; hour < hours; hour++) ...[
                  Positioned(
                    top: hour * hourHeight,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: scheme.outlineVariant),
                  ),
                  Positioned(
                    top: hour * hourHeight + hourHeight / 2,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ],
                for (final item in placed)
                  Positioned(
                    top: _topFor(item.event.startsAt, hourHeight),
                    height: _blockHeight(item.event, hourHeight),
                    left: item.column * (constraints.maxWidth / item.columns) + 1,
                    width: (constraints.maxWidth / item.columns) - 2,
                    child: _EventBlock(
                      event: item.event,
                      onOpen: onOpen,
                      onCreate: onCreate,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({
    required this.event,
    required this.onOpen,
    required this.onCreate,
  });

  final _CalEvent event;
  final ValueChanged<Group> onOpen;
  final void Function(String? roomId, DateTime startsAt) onCreate;

  @override
  Widget build(BuildContext context) {
    final group = event.group;
    final booked = group != null;
    final cancelled = group?.isCancelled ?? false;
    final background = booked
        ? event.color.withValues(alpha: cancelled ? 0.45 : 1)
        : event.color.withValues(alpha: 0.18);
    final foreground = booked ? onRoomColor(event.color) : event.color;
    final time = _hm(event.startsAt.hour, event.startsAt.minute);
    final detail = group == null
        ? PartnerMessages.free
        : '${group.filledSpots}/${group.totalSpots}';
    return Material(
      key: PartnerKeys.agendaBlock(event.id),
      color: background,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (group != null) {
            onOpen(group);
            return;
          }
          onCreate(event.room?.id, event.startsAt);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: booked ? Colors.transparent : event.color.withValues(alpha: 0.85),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${event.title}\n$time · $detail',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                  decorationColor: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthBoard extends StatelessWidget {
  const _MonthBoard({
    required this.focus,
    required this.snapshot,
    required this.colors,
    required this.onDay,
    required this.onOpen,
  });

  final DateTime focus;
  final PartnerSnapshot snapshot;
  final Map<String, Color> colors;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<Group> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = isScapeDesktop(context);
    final first = DateTime(focus.year, focus.month);
    final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
    final cellHeight = wide ? 112.0 : 86.0;
    return ListView(
      key: PartnerKeys.agendaMonthGrid,
      primary: false,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
      children: [
        Row(
          children: [
            for (final letter in _weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          SizedBox(
            height: cellHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: _MonthCell(
                      day: start.add(Duration(days: week * 7 + index)),
                      focus: focus,
                      today: snapshot.now,
                      events: _eventsFor(
                        snapshot,
                        colors,
                        start.add(Duration(days: week * 7 + index)),
                        collapseFree: true,
                      ),
                      maxChips: wide ? 3 : 2,
                      onDay: onDay,
                      onOpen: onOpen,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.focus,
    required this.today,
    required this.events,
    required this.maxChips,
    required this.onDay,
    required this.onOpen,
  });

  final DateTime day;
  final DateTime focus;
  final DateTime today;
  final List<_CalEvent> events;
  final int maxChips;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<Group> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = day.month == focus.month;
    final isToday = _sameDay(day, today);
    final shown = events.take(maxChips).toList();
    final extra = events.length - shown.length;
    return InkWell(
      onTap: () => onDay(day),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: ClipRect(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isToday ? scheme.primary : null,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: !inMonth
                          ? scheme.outline
                          : isToday
                          ? scheme.onPrimary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
              for (final event in shown)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _MonthChip(event: event, onOpen: onOpen),
                ),
              if (extra > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2),
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.event, required this.onOpen});

  final _CalEvent event;
  final ValueChanged<Group> onOpen;

  @override
  Widget build(BuildContext context) {
    final group = event.group;
    final foreground = group == null ? event.color : onRoomColor(event.color);
    final background = group == null
        ? event.color.withValues(alpha: 0.16)
        : event.color.withValues(alpha: group.isCancelled ? 0.45 : 1);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: group == null ? null : () => onOpen(group),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
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
              const Text(PartnerMessages.nobodyYet)
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
                  final error = await ref
                      .read(partnerRepositoryProvider)
                      .cancelSession(
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
      title: Text(
        '${person.displayName} · ${GroupMessages.paymentStatus(person.payment)}',
      ),
      subtitle: marked
          ? Text(
              PartnerMessages.absenceLine(
                snapshot.absenceCount(playerId),
                snapshot.standingOf(playerId),
              ),
            )
          : null,
      trailing: !marked && canMark
          ? TextButton(
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
  const _AddSessionSheet({required this.snapshot, this.roomId, this.startsAt});

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
    _roomId = widget.roomId ?? (rooms.isEmpty ? '' : rooms.first.id);
    final start = widget.startsAt ?? _nextOpening(widget.snapshot.now);
    _day = _dateOnly(start);
    _hour = _housePair(start);
    EscapeRoom? room;
    for (final item in rooms) {
      if (item.id == _roomId) {
        room = item;
        break;
      }
    }
    room ??= rooms.isEmpty ? null : rooms.first;
    if (room != null) {
      _roomId = room.id;
    }
    _price = TextEditingController(text: reaisField(room?.priceCents ?? 10900));
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
    if (widget.snapshot.rooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Crie uma sala antes de abrir um horário.'),
      );
    }
    final days = [
      for (var i = 0; i < 14; i++)
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
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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

class _CalEvent {
  const _CalEvent({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.color,
    required this.title,
    this.room,
    this.group,
  });

  final String id;
  final EscapeRoom? room;
  final DateTime startsAt;
  final DateTime endsAt;
  final Color color;
  final String title;
  final Group? group;
}

class _Placed {
  const _Placed(this.event, this.column, this.columns);

  final _CalEvent event;
  final int column;
  final int columns;
}

List<_CalEvent> _eventsFor(
  PartnerSnapshot snapshot,
  Map<String, Color> colors,
  DateTime day, {
  required bool collapseFree,
}) {
  final events = <_CalEvent>[];
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
    events.add(
      _CalEvent(
        id: group.id,
        room: room,
        startsAt: group.startsAt,
        endsAt: group.endsAt,
        color: colors[room.id] ?? const Color(0xFF0F4C4A),
        title: room.name,
        group: group,
      ),
    );
  }
  for (final room in snapshot.rooms) {
    for (final slot in snapshot.slotsByRoom[room.id] ?? const []) {
      if (!_sameDay(slot.startsAt, day) || !slot.startsAt.isAfter(snapshot.now)) {
        continue;
      }
      if (!_houseHour(slot.startsAt)) {
        continue;
      }
      final key = '${room.id}|${slot.startsAt.toIso8601String()}';
      if (taken.contains(key)) {
        continue;
      }
      events.add(
        _CalEvent(
          id: slot.id,
          room: room,
          startsAt: slot.startsAt,
          endsAt: slot.startsAt.add(Duration(minutes: room.durationMinutes)),
          color: colors[room.id] ?? const Color(0xFF0F4C4A),
          title: room.name,
        ),
      );
    }
  }
  events.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (!collapseFree) {
    return events;
  }
  return _collapseFree(events);
}

List<_CalEvent> _collapseFree(List<_CalEvent> events) {
  final booked = [for (final event in events) if (event.group != null) event];
  final free = [for (final event in events) if (event.group == null) event];
  final byStart = <int, List<_CalEvent>>{};
  for (final event in free) {
    final key = event.startsAt.hour * 60 + event.startsAt.minute;
    byStart.putIfAbsent(key, () => []).add(event);
  }
  final collapsed = <_CalEvent>[...booked];
  for (final bucket in byStart.values) {
    if (bucket.length <= 2) {
      collapsed.addAll(bucket);
    }
  }
  collapsed.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return collapsed;
}

List<_Placed> _place(List<_CalEvent> events) {
  if (events.isEmpty) {
    return const [];
  }
  final sorted = [...events]..sort((a, b) {
    final byStart = a.startsAt.compareTo(b.startsAt);
    if (byStart != 0) {
      return byStart;
    }
    return b.endsAt.compareTo(a.endsAt);
  });
  final clusters = <List<_CalEvent>>[];
  var cluster = <_CalEvent>[sorted.first];
  var clusterEnd = sorted.first.endsAt;
  for (final event in sorted.skip(1)) {
    if (event.startsAt.isBefore(clusterEnd)) {
      cluster.add(event);
      if (event.endsAt.isAfter(clusterEnd)) {
        clusterEnd = event.endsAt;
      }
    } else {
      clusters.add(cluster);
      cluster = [event];
      clusterEnd = event.endsAt;
    }
  }
  clusters.add(cluster);
  final placed = <_Placed>[];
  for (final group in clusters) {
    final columnEnds = <DateTime>[];
    final columns = <int>[];
    for (final event in group) {
      var column = 0;
      while (column < columnEnds.length &&
          columnEnds[column].isAfter(event.startsAt)) {
        column += 1;
      }
      if (column == columnEnds.length) {
        columnEnds.add(event.endsAt);
      } else {
        columnEnds[column] = event.endsAt;
      }
      columns.add(column);
    }
    for (var i = 0; i < group.length; i++) {
      placed.add(_Placed(group[i], columns[i], columnEnds.length));
    }
  }
  return placed;
}

Set<DateTime> _markedDays(PartnerSnapshot snapshot) {
  return {
    for (final group in snapshot.groups) _dateOnly(group.startsAt),
  };
}

List<DateTime> _daysOf(_AgendaView view, DateTime focus) {
  return switch (view) {
    _AgendaView.day => [focus],
    _AgendaView.threeDays => [
      for (var i = 0; i < 3; i++) focus.add(Duration(days: i)),
    ],
    _AgendaView.week => [
      for (var i = 0; i < 7; i++) _monday(focus).add(Duration(days: i)),
    ],
    _AgendaView.month => const [],
  };
}

EscapeRoom? _room(PartnerSnapshot snapshot, String id) {
  for (final room in snapshot.rooms) {
    if (room.id == id) {
      return room;
    }
  }
  return null;
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

double _topFor(DateTime time, double hourHeight) {
  final minutes = (time.hour - agendaGridStartHour) * 60 + time.minute;
  if (minutes < 0) {
    return 0;
  }
  return minutes / 60 * hourHeight;
}

double _blockHeight(_CalEvent event, double hourHeight) {
  final minutes = event.endsAt.difference(event.startsAt).inMinutes;
  final raw = minutes <= 0 ? hourHeight / 2 : minutes / 60 * hourHeight;
  if (raw < 28) {
    return 28;
  }
  return raw;
}

DateTime _snapHour(DateTime day, double dy, double hourHeight) {
  final minutes = (dy / hourHeight * 60).round();
  final clock = DateTime(day.year, day.month, day.day, agendaGridStartHour).add(
    Duration(minutes: minutes),
  );
  var best = agendaHours.first;
  var bestDelta = 1 << 30;
  for (final hour in agendaHours) {
    final candidate = DateTime(day.year, day.month, day.day, hour.$1, hour.$2);
    final delta = candidate.difference(clock).inMinutes.abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = hour;
    }
  }
  return DateTime(day.year, day.month, day.day, best.$1, best.$2);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _monday(DateTime day) {
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

DateTime _addMonths(DateTime day, int months) {
  final target = DateTime(day.year, day.month + months);
  final last = DateTime(target.year, target.month + 1, 0).day;
  final date = day.day > last ? last : day.day;
  return DateTime(target.year, target.month, date);
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _houseHour(DateTime time) {
  for (final hour in agendaHours) {
    if (time.hour == hour.$1 && time.minute == hour.$2) {
      return true;
    }
  }
  return false;
}

(int, int) _housePair(DateTime time) {
  for (final hour in agendaHours) {
    if (time.hour == hour.$1 && time.minute == hour.$2) {
      return hour;
    }
  }
  final fromGrid = ((time.hour - agendaGridStartHour) * 60 + time.minute)
      .toDouble();
  final snapped = _snapHour(time, fromGrid, 60);
  return (snapped.hour, snapped.minute);
}

String _hm(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

String _cap(String raw) {
  if (raw.isEmpty) {
    return raw;
  }
  return raw[0].toUpperCase() + raw.substring(1);
}

String _dayHeading(DateTime day) {
  final raw = DateFormat('EEE d', 'pt_BR').format(day);
  return _cap(raw);
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
