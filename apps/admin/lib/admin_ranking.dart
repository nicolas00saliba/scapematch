import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RankingSettings {
  const RankingSettings({required this.enabled});

  final bool enabled;

  static const off = RankingSettings(enabled: false);
}

class RankingRow {
  const RankingRow({
    required this.id,
    required this.venueName,
    required this.roomName,
    required this.groupName,
    required this.elapsedSeconds,
    required this.escaped,
    required this.removed,
    required this.playedOn,
  });

  final String id;
  final String venueName;
  final String roomName;
  final String groupName;
  final int elapsedSeconds;
  final bool escaped;
  final bool removed;
  final String playedOn;

  RankingRow copyWith({bool? removed}) {
    return RankingRow(
      id: id,
      venueName: venueName,
      roomName: roomName,
      groupName: groupName,
      elapsedSeconds: elapsedSeconds,
      escaped: escaped,
      removed: removed ?? this.removed,
      playedOn: playedOn,
    );
  }
}

abstract class RankingAdminApi {
  Future<RankingSettings> settings();
  Future<RankingSettings> save(bool enabled);
  Future<List<RankingRow>> recent();
  Future<void> remove(String id);
}

class MemoryRankingAdminApi implements RankingAdminApi {
  MemoryRankingAdminApi({RankingSettings? settings})
    : _settings = settings ?? RankingSettings.off;

  RankingSettings _settings;
  final List<RankingRow> _rows = [
    const RankingRow(
      id: 'tempo-1',
      venueName: 'Ninja Escape',
      roomName: 'O Cofre',
      groupName: 'Os Ninjas',
      elapsedSeconds: 38 * 60 + 12,
      escaped: true,
      removed: false,
      playedOn: '2026-11-02',
    ),
  ];

  @override
  Future<RankingSettings> settings() async => _settings;

  @override
  Future<RankingSettings> save(bool enabled) async {
    _settings = RankingSettings(enabled: enabled);
    return _settings;
  }

  @override
  Future<List<RankingRow>> recent() async => List.of(_rows);

  @override
  Future<void> remove(String id) async {
    final index = _rows.indexWhere((row) => row.id == id);
    if (index < 0) throw AdminRejected('tempo não encontrado');
    _rows[index] = _rows[index].copyWith(removed: true);
  }
}

class SupabaseRankingAdminApi implements RankingAdminApi {
  SupabaseRankingAdminApi(this.client);

  final SupabaseClient client;

  @override
  Future<RankingSettings> settings() async {
    final raw = await _rpc('admin_room_time_settings');
    return RankingSettings(enabled: raw is Map && raw['enabled'] == true);
  }

  @override
  Future<RankingSettings> save(bool enabled) async {
    final raw = await _rpc('admin_save_room_time_settings', {
      'p_enabled': enabled,
    });
    return RankingSettings(enabled: raw is Map && raw['enabled'] == true);
  }

  @override
  Future<List<RankingRow>> recent() async {
    final raw = await _rpc('admin_room_time_recent');
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map)
          RankingRow(
            id: '${row['entry_id']}',
            venueName: '${row['venue_name']}',
            roomName: '${row['room_name']}',
            groupName: '${row['group_name']}',
            elapsedSeconds: row['elapsed_seconds'] is num
                ? (row['elapsed_seconds'] as num).round()
                : 0,
            escaped: row['escaped'] == true,
            removed: row['removed'] == true,
            playedOn: '${row['played_on']}',
          ),
    ];
  }

  @override
  Future<void> remove(String id) async {
    await _rpc('remove_room_time', {'p_entry_id': id});
  }

  Future<Object?> _rpc(String name, [Map<String, Object?>? params]) async {
    try {
      return await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      throw AdminRejected(error.message);
    }
  }
}

final rankingAdminProvider = Provider<RankingAdminApi>((ref) {
  if (!scapeUsesLiveBackend) {
    throw StateError('O Admin real ainda não ligou o Supabase.');
  }
  return SupabaseRankingAdminApi(scapeSupabase);
});

class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key});

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
  RankingSettings? _settings;
  List<RankingRow> _rows = const [];
  var _enabled = false;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(rankingAdminProvider);
      final settings = await api.settings();
      final rows = await api.recent();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _enabled = settings.enabled;
        _rows = rows;
        _error = null;
      });
    } on AdminRejected catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(rankingAdminProvider).save(_enabled);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _enabled = saved.enabled;
        _busy = false;
        _error = null;
      });
    } on AdminRejected catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _remove(RankingRow row) async {
    try {
      await ref.read(rankingAdminProvider).remove(row.id);
      await _load();
    } on AdminRejected catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _settings?.enabled ?? false;
    return AdminFrame(
      title: 'Ranking de tempo',
      child: Column(
        key: const Key('admin-ranking'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const Key('admin-ranking-flag'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ranking de tempo por sala'),
            subtitle: Text(on ? 'Ligada' : 'Desligada'),
            value: _enabled,
            onChanged: _settings == null
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const Text(
            'Nasce desligada. A casa lança o tempo do cronômetro. O público vê o top 10, sem e-mail e sem nome completo.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('admin-ranking-salvar'),
              onPressed: _busy || _settings == null ? null : _save,
              child: const Text('Salvar'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('admin-ranking-erro')),
          ],
          const SizedBox(height: 24),
          Text(
            'Moderação',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final row in _rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${row.groupName} · ${row.venueName} · ${row.roomName}'),
              subtitle: Text(
                '${_clock(row.elapsedSeconds)} · ${row.escaped ? 'escapou' : 'não escapou'} · ${row.playedOn}${row.removed ? ' · removido' : ''}',
              ),
              trailing: row.removed
                  ? null
                  : TextButton(
                      key: Key('admin-ranking-remover-${row.id}'),
                      onPressed: () => _remove(row),
                      child: const Text('Remover'),
                    ),
            ),
        ],
      ),
    );
  }
}

String _clock(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
