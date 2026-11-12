import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/ranking/data/room_time_gateway.dart';
import 'package:scapematch/providers/repositories.dart';

/// Top 10 da sala. Some quando a flag está desligada.
class RoomTimeSlot extends ConsumerWidget {
  const RoomTimeSlot({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.maybeWhen(
      data: (on) {
        if (!on || !scapeUsesLiveBackend) return const SizedBox.shrink();
        return _RoomTimeLive(roomId: roomId);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RoomTimeLive extends ConsumerStatefulWidget {
  const _RoomTimeLive({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_RoomTimeLive> createState() => _RoomTimeLiveState();
}

class _RoomTimeLiveState extends ConsumerState<_RoomTimeLive> {
  late Future<List<RoomTimeLine>> _lines;

  @override
  void initState() {
    super.initState();
    _lines = ref.read(roomTimeGatewayProvider).ranking(widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomTimeLine>>(
      future: _lines,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text('Não foi possível carregar o ranking desta sala.'),
          );
        }
        final lines = snapshot.data ?? const <RoomTimeLine>[];
        if (lines.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: RoomTimeBoard(lines: lines),
        );
      },
    );
  }
}

/// Tempos da própria conta, no perfil.
class MyRoomTimesSlot extends ConsumerWidget {
  const MyRoomTimesSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.maybeWhen(
      data: (on) {
        if (!on || !scapeUsesLiveBackend) return const SizedBox.shrink();
        return const _MyRoomTimesLive();
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _MyRoomTimesLive extends ConsumerStatefulWidget {
  const _MyRoomTimesLive();

  @override
  ConsumerState<_MyRoomTimesLive> createState() => _MyRoomTimesLiveState();
}

class _MyRoomTimesLiveState extends ConsumerState<_MyRoomTimesLive> {
  late Future<List<RoomTimeLine>> _lines;

  @override
  void initState() {
    super.initState();
    _lines = ref.read(roomTimeGatewayProvider).mine();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomTimeLine>>(
      future: _lines,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError || (snapshot.data ?? const []).isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: MyRoomTimesView(lines: snapshot.data!),
        );
      },
    );
  }
}

/// O jogador escolhe se o primeiro nome entra no ranking público.
class RoomTimeVisibilitySlot extends ConsumerWidget {
  const RoomTimeVisibilitySlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.maybeWhen(
      data: (on) {
        if (!on || !scapeUsesLiveBackend) return const SizedBox.shrink();
        return const _RoomTimeVisibilityLive();
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RoomTimeVisibilityLive extends ConsumerStatefulWidget {
  const _RoomTimeVisibilityLive();

  @override
  ConsumerState<_RoomTimeVisibilityLive> createState() =>
      _RoomTimeVisibilityLiveState();
}

class _RoomTimeVisibilityLiveState extends ConsumerState<_RoomTimeVisibilityLive> {
  bool? _appears;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final appears = await ref.read(roomTimeGatewayProvider).appearsInRanking();
      if (!mounted) return;
      setState(() => _appears = appears);
    } on Object {
      if (!mounted) return;
      setState(() => _appears = true);
    }
  }

  Future<void> _set(bool appears) async {
    final previous = _appears;
    setState(() {
      _appears = appears;
      _error = null;
    });
    try {
      await ref.read(roomTimeGatewayProvider).setAppearsInRanking(appears);
    } on RoomTimeRejected catch (error) {
      if (!mounted) return;
      setState(() {
        _appears = previous;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appears = _appears;
    if (appears == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: LinearProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: RoomTimeVisibilityCard(
        appears: appears,
        error: _error,
        onChanged: _set,
      ),
    );
  }
}

class RoomTimeVisibilityCard extends StatelessWidget {
  const RoomTimeVisibilityCard({
    super.key,
    required this.appears,
    required this.onChanged,
    this.error,
  });

  final bool appears;
  final ValueChanged<bool> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('room-time-visibility'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Aparecer no ranking público'),
          subtitle: const Text(
            'O padrão é aparecer. Se desligar, seu primeiro nome sai do ranking. O tempo do grupo continua.',
          ),
          value: appears,
          onChanged: onChanged,
        ),
        if (error != null)
          Text(error!, key: const Key('room-time-visibility-error')),
      ],
    );
  }
}

/// Nome do grupo, escolhido por quem está na sessão.
class TeamNameSlot extends ConsumerWidget {
  const TeamNameSlot({super.key, required this.groupId, required this.canEdit});

  final String groupId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(roomTimeRankingEnabledProvider);
    return enabled.maybeWhen(
      data: (on) {
        if (!on || !canEdit || !scapeUsesLiveBackend) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TeamNameEditor(groupId: groupId),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class TeamNameEditor extends ConsumerStatefulWidget {
  const TeamNameEditor({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<TeamNameEditor> createState() => _TeamNameEditorState();
}

class _TeamNameEditorState extends ConsumerState<TeamNameEditor> {
  final _name = TextEditingController();
  var _ready = false;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final name = await ref.read(roomTimeGatewayProvider).teamName(widget.groupId);
      if (!mounted) return;
      _name.text = name == roomTimeDefaultGroup ? '' : name;
      setState(() => _ready = true);
    } on Object {
      if (!mounted) return;
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = roomTimeNameError(_name.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(roomTimeGatewayProvider).setTeamName(
        widget.groupId,
        _name.text,
      );
      if (!mounted) return;
      setState(() => _busy = false);
    } on RoomTimeRejected catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('team-name-field'),
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome do grupo no ranking',
            hintText: 'Se ficar vazio, entra como Grupo',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, key: const Key('team-name-error')),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('team-name-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Salvar nome'),
          ),
        ),
      ],
    );
  }
}

class RoomTimeBoard extends StatelessWidget {
  const RoomTimeBoard({super.key, required this.lines});

  final List<RoomTimeLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('room-time-board'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ranking da sala',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Menor tempo entre quem escapou.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          const Text('Ainda não há grupos que escaparam nesta sala.')
        else
          for (final line in lines) RoomTimeRow(line: line),
      ],
    );
  }
}

class MyRoomTimesView extends StatelessWidget {
  const MyRoomTimesView({super.key, required this.lines});

  final List<RoomTimeLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('my-room-times'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Seus tempos',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'O que a casa lançou nas salas que você jogou.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          const Text('Você ainda não tem tempos lançados.')
        else
          for (final line in lines)
            RoomTimeRow(
              line: line,
              title: line.roomName ?? line.groupName,
              subtitleExtra: line.escaped ? null : 'Não escapou',
            ),
      ],
    );
  }
}

class RoomTimeRow extends StatelessWidget {
  const RoomTimeRow({
    super.key,
    required this.line,
    this.title,
    this.subtitleExtra,
  });

  final RoomTimeLine line;
  final String? title;
  final String? subtitleExtra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final medal = line.medal;
    final place = line.place;
    return Padding(
      key: Key('room-time-row-${line.entryId ?? line.place ?? line.groupName}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaceMark(place: place, medal: medal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? line.groupName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (title != null)
                      Text(
                        line.groupName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      line.clockLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      [
                        ?subtitleExtra,
                        if (line.membersLine.isNotEmpty) line.membersLine,
                        formatRoomDate(line.playedOn),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceMark extends StatelessWidget {
  const _PlaceMark({required this.place, required this.medal});

  final int? place;
  final RoomTimeMedal? medal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (medal) {
      RoomTimeMedal.gold => const Color(0xFFB8860B),
      RoomTimeMedal.silver => const Color(0xFF8E99A4),
      RoomTimeMedal.bronze => const Color(0xFF8C5A3C),
      null => scheme.surfaceContainerHighest,
    };
    final label = place == null ? '—' : roomTimePlaceLabel(place!);
    return Tooltip(
      message: medal == null ? 'Posição' : medalLabel(medal!),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: color,
        foregroundColor: medal == null ? scheme.onSurface : Colors.white,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
