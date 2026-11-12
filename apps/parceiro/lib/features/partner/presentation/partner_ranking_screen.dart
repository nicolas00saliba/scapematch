import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/ranking/data/room_time_gateway.dart';
import 'package:scapematch/features/ranking/presentation/room_time_view.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/data/room_time_gateway.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

final partnerRoomTimeGatewayProvider = Provider<PartnerRoomTimeGateway>((ref) {
  if (!scapeUsesLiveBackend) return MemoryPartnerRoomTimeGateway();
  return SupabasePartnerRoomTimeGateway(scapeSupabase);
});

/// Aba da casa. Com a flag desligada, só explica que o Admin ainda não ligou.
class PartnerRankingSection extends ConsumerWidget {
  const PartnerRankingSection({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Center(
        child: Text('Não foi possível carregar o ranking.'),
      ),
      data: (on) {
        if (!on || !scapeUsesLiveBackend) return const PartnerRankingOff();
        return PartnerRankingLive(snapshot: snapshot);
      },
    );
  }
}

class PartnerRankingOff extends StatelessWidget {
  const PartnerRankingOff({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        key: Key('partner-ranking-off'),
        padding: EdgeInsets.all(24),
        child: Text(
          'O ranking de tempo está desligado. Quando o Admin ligar, a casa lança o tempo do cronômetro e vê a lista completa.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PartnerRankingLive extends ConsumerStatefulWidget {
  const PartnerRankingLive({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  ConsumerState<PartnerRankingLive> createState() => _PartnerRankingLiveState();
}

class _PartnerRankingLiveState extends ConsumerState<PartnerRankingLive> {
  String? _roomId;
  VenueTimePrefs _prefs = const VenueTimePrefs(
    showPublic: true,
    showMembers: false,
  );
  List<RoomTimeLine> _lines = const [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rooms = widget.snapshot.rooms;
    _roomId = rooms.isEmpty ? null : rooms.first.id;
    _load();
  }

  Future<void> _load() async {
    final roomId = _roomId;
    if (roomId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gateway = ref.read(partnerRoomTimeGatewayProvider);
      final prefs = await gateway.prefs(widget.snapshot.house.id);
      final lines = await gateway.times(roomId);
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _lines = lines;
        _loading = false;
      });
    } on RoomTimeRejected catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _savePrefs(VenueTimePrefs next) async {
    try {
      final saved = await ref.read(partnerRoomTimeGatewayProvider).savePrefs(
        widget.snapshot.house.id,
        next,
      );
      if (!mounted) return;
      setState(() => _prefs = saved);
    } on RoomTimeRejected catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.snapshot.rooms;
    if (rooms.isEmpty) {
      return const Center(child: Text('Cadastre uma sala para lançar tempos.'));
    }
    final roomId = _roomId ?? rooms.first.id;
    final recorded = {for (final line in _lines) line.groupId};
    final pending = [
      for (final group in widget.snapshot.groups)
        if (group.roomId == roomId &&
            !group.isCancelled &&
            !widget.snapshot.now.isBefore(group.startsAt) &&
            !recorded.contains(group.id))
          group,
    ];
    return ListView(
      key: PartnerKeys.partnerRanking,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        DropdownButtonFormField<String>(
          key: const Key('partner-ranking-room'),
          initialValue: roomId,
          decoration: const InputDecoration(labelText: 'Sala'),
          items: [
            for (final room in rooms)
              DropdownMenuItem(value: room.id, child: Text(room.name)),
          ],
          onChanged: (value) {
            if (value == null || value == _roomId) return;
            setState(() => _roomId = value);
            _load();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!),
        ],
        const SizedBox(height: 12),
        if (_loading)
          const LinearProgressIndicator()
        else ...[
          RoomTimeHousePanel(
            lines: _lines,
            showPublic: _prefs.showPublic,
            showMembers: _prefs.showMembers,
            onShowPublic: (value) => _savePrefs(
              VenueTimePrefs(showPublic: value, showMembers: _prefs.showMembers),
            ),
            onShowMembers: (value) => _savePrefs(
              VenueTimePrefs(showPublic: _prefs.showPublic, showMembers: value),
            ),
            onRemove: (line) async {
              final id = line.entryId;
              if (id == null) return;
              await ref.read(partnerRoomTimeGatewayProvider).remove(id);
              await _load();
            },
            onEdit: (line, draft) async {
              final id = line.entryId;
              if (id == null) return 'Tempo não encontrado.';
              try {
                await ref.read(partnerRoomTimeGatewayProvider).edit(id, draft);
                await _load();
                return null;
              } on RoomTimeRejected catch (error) {
                return error.message;
              }
            },
          ),
          for (final group in pending) ...[
            const SizedBox(height: 12),
            Text(group.roomName, style: Theme.of(context).textTheme.titleSmall),
            RoomTimeLaunchForm(
              durationMinutes: group.durationMinutes,
              initialName: '',
              members: [
                for (final person in group.participants)
                  if (person.occupiesSeat && (person.userId ?? '').isNotEmpty)
                    RoomTimeMemberDraft(
                      userId: person.userId!,
                      label: firstLabel(person.displayName),
                    ),
              ],
              onSubmit: (draft) async {
                try {
                  await ref.read(partnerRoomTimeGatewayProvider).record(
                    group.id,
                    draft,
                  );
                  await _load();
                  return null;
                } on RoomTimeRejected catch (error) {
                  return error.message;
                }
              },
            ),
          ],
        ],
      ],
    );
  }
}

/// Formulário do cronômetro. A casa informa o tempo gasto e se escaparam.
class RoomTimeLaunchForm extends StatefulWidget {
  const RoomTimeLaunchForm({
    super.key,
    required this.durationMinutes,
    required this.initialName,
    required this.members,
    required this.onSubmit,
    this.submitLabel = 'Lançar tempo',
    this.heading = 'Lançar tempo',
    this.initialElapsedSeconds = 0,
    this.initialEscaped = true,
    this.fieldPrefix = 'partner-time',
  });

  final int durationMinutes;
  final String initialName;
  final List<RoomTimeMemberDraft> members;
  final Future<String?> Function(RoomTimeDraft draft) onSubmit;
  final String submitLabel;
  final String heading;
  final int initialElapsedSeconds;
  final bool initialEscaped;
  final String fieldPrefix;

  @override
  State<RoomTimeLaunchForm> createState() => _RoomTimeLaunchFormState();
}

class _RoomTimeLaunchFormState extends State<RoomTimeLaunchForm> {
  late final TextEditingController _name;
  late final TextEditingController _minutes;
  late final TextEditingController _seconds;
  late final List<TextEditingController> _labels;
  late bool _escaped;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final elapsed = widget.initialElapsedSeconds;
    _name = TextEditingController(text: widget.initialName);
    _minutes = TextEditingController(
      text: elapsed == 0 ? '' : '${elapsed ~/ 60}',
    );
    _seconds = TextEditingController(
      text: elapsed == 0 ? '' : '${elapsed % 60}',
    );
    _escaped = widget.initialEscaped;
    _labels = [
      for (final member in widget.members)
        TextEditingController(text: member.label),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _seconds.dispose();
    for (final label in _labels) {
      label.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final nameError = roomTimeNameError(_name.text);
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final seconds = int.tryParse(_seconds.text.trim()) ?? 0;
    final elapsed = minutes * 60 + seconds;
    final limit = widget.durationMinutes * 60;
    String? error = nameError;
    if (seconds < 0 || seconds > 59 || minutes < 0) {
      error = 'Use minutos e segundos do cronômetro.';
    } else if (elapsed < 1 || elapsed > limit) {
      error = 'O tempo fica entre 1 segundo e a duração da sala.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final members = [
      for (var index = 0; index < widget.members.length; index++)
        RoomTimeMemberDraft(
          userId: widget.members[index].userId,
          label: _labels[index].text,
        ),
    ];
    final result = await widget.onSubmit(
      RoomTimeDraft(
        groupName: _name.text,
        elapsedSeconds: elapsed,
        escaped: _escaped,
        members: members,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.partnerTimeLaunch,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.heading,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Use o cronômetro da sala. A duração cadastrada é ${widget.durationMinutes} min. Quem não escapou fica no histórico e fora do ranking.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          key: Key('${widget.fieldPrefix}-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome do grupo',
            hintText: 'Grupo',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: Key('${widget.fieldPrefix}-minutes'),
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Minutos'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: Key('${widget.fieldPrefix}-seconds'),
                controller: _seconds,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Segundos'),
              ),
            ),
          ],
        ),
        SwitchListTile(
          key: Key('${widget.fieldPrefix}-escaped'),
          contentPadding: EdgeInsets.zero,
          title: const Text('O grupo escapou'),
          value: _escaped,
          onChanged: _busy ? null : (value) => setState(() => _escaped = value),
        ),
        if (widget.members.isNotEmpty) ...[
          Text(
            'Integrantes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < widget.members.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: Key('${widget.fieldPrefix}-member-$index'),
                controller: _labels[index],
                decoration: const InputDecoration(
                  labelText: 'Primeiro nome ou apelido',
                ),
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, key: Key('${widget.fieldPrefix}-error')),
        ],
        const SizedBox(height: 8),
        FilledButton(
          key: Key('${widget.fieldPrefix}-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class RoomTimeHousePanel extends StatelessWidget {
  const RoomTimeHousePanel({
    super.key,
    required this.lines,
    required this.showPublic,
    required this.showMembers,
    required this.onShowPublic,
    required this.onShowMembers,
    required this.onRemove,
    this.onEdit,
  });

  final List<RoomTimeLine> lines;
  final bool showPublic;
  final bool showMembers;
  final ValueChanged<bool> onShowPublic;
  final ValueChanged<bool> onShowMembers;
  final Future<void> Function(RoomTimeLine line) onRemove;
  final Future<String?> Function(RoomTimeLine line, RoomTimeDraft draft)? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final escaped = [for (final line in lines) if (line.escaped) line];
    final stayed = [for (final line in lines) if (!line.escaped) line];
    return Column(
      key: PartnerKeys.partnerTimeBoard,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ranking completo',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        SwitchListTile(
          key: const Key('partner-ranking-public'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar o ranking público da sala'),
          value: showPublic,
          onChanged: onShowPublic,
        ),
        SwitchListTile(
          key: const Key('partner-ranking-members'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostrar os integrantes'),
          subtitle: const Text('Só o primeiro nome ou apelido.'),
          value: showMembers,
          onChanged: onShowMembers,
        ),
        if (escaped.isEmpty)
          const Text('Ainda não há grupos que escaparam nesta sala.')
        else
          for (final line in escaped)
            _HouseRow(line: line, onRemove: onRemove, onEdit: onEdit),
        if (stayed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Não escaparam',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in stayed)
            _HouseRow(line: line, onRemove: onRemove, onEdit: onEdit),
        ],
      ],
    );
  }
}

class _HouseRow extends StatefulWidget {
  const _HouseRow({
    required this.line,
    required this.onRemove,
    required this.onEdit,
  });

  final RoomTimeLine line;
  final Future<void> Function(RoomTimeLine line) onRemove;
  final Future<String?> Function(RoomTimeLine line, RoomTimeDraft draft)? onEdit;

  @override
  State<_HouseRow> createState() => _HouseRowState();
}

class _HouseRowState extends State<_HouseRow> {
  var _editing = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    if (_editing && widget.onEdit != null) {
      return RoomTimeLaunchForm(
        durationMinutes: ((line.elapsedSeconds + line.remainingSeconds) / 60)
            .ceil()
            .clamp(15, 480),
        initialName: line.groupName,
        initialElapsedSeconds: line.elapsedSeconds,
        initialEscaped: line.escaped,
        heading: 'Editar tempo',
        fieldPrefix: 'partner-time-edit',
        members: [
          for (var index = 0; index < line.memberIds.length; index++)
            RoomTimeMemberDraft(
              userId: line.memberIds[index],
              label: index < line.members.length ? line.members[index] : '',
            ),
        ],
        submitLabel: 'Salvar',
        onSubmit: (draft) async {
          final error = await widget.onEdit!(line, draft);
          if (error == null && mounted) setState(() => _editing = false);
          return error;
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoomTimeRow(line: line),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: Key('partner-time-edit-${line.entryId ?? line.groupName}'),
                onPressed: widget.onEdit == null
                    ? null
                    : () => setState(() => _editing = true),
                child: const Text('Editar'),
              ),
              TextButton(
                key: Key('partner-time-remove-${line.entryId ?? line.groupName}'),
                onPressed: () => widget.onRemove(line),
                child: const Text('Remover'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Atalho na ficha da sessão. Só aparece com a flag ligada.
class SessionTimeLaunch extends ConsumerWidget {
  const SessionTimeLaunch({super.key, required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.maybeWhen(
      data: (on) {
        if (!on || !scapeUsesLiveBackend) return const SizedBox.shrink();
        return RoomTimeLaunchForm(
          durationMinutes: group.durationMinutes,
          initialName: '',
          members: [
            for (final person in group.participants)
              if (person.occupiesSeat && (person.userId ?? '').isNotEmpty)
                RoomTimeMemberDraft(
                  userId: person.userId!,
                  label: firstLabel(person.displayName),
                ),
          ],
          onSubmit: (draft) async {
            try {
              await ref.read(partnerRoomTimeGatewayProvider).record(
                group.id,
                draft,
              );
              return null;
            } on RoomTimeRejected catch (error) {
              return error.message;
            }
          },
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
