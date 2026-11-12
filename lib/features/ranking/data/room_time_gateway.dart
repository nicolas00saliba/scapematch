import 'package:dominio/dominio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class RoomTimeGateway {
  Future<List<RoomTimeLine>> ranking(String roomId);
  Future<List<RoomTimeLine>> mine();
  Future<String> teamName(String groupId);
  Future<void> setTeamName(String groupId, String name);
  Future<bool> appearsInRanking();
  Future<void> setAppearsInRanking(bool appears);
}

class MemoryRoomTimeGateway implements RoomTimeGateway {
  MemoryRoomTimeGateway({
    this.rankingLines = const [],
    this.mineLines = const [],
    this.storedName = roomTimeDefaultGroup,
  });

  final List<RoomTimeLine> rankingLines;
  final List<RoomTimeLine> mineLines;
  String storedName;

  @override
  Future<List<RoomTimeLine>> ranking(String roomId) async => rankingLines;

  @override
  Future<List<RoomTimeLine>> mine() async => mineLines;

  @override
  Future<String> teamName(String groupId) async => storedName;

  @override
  Future<void> setTeamName(String groupId, String name) async {
    final error = roomTimeNameError(name);
    if (error != null) throw RoomTimeRejected(error);
    storedName = roomTimeNameOrDefault(name);
  }

  bool appears = true;

  @override
  Future<bool> appearsInRanking() async => appears;

  @override
  Future<void> setAppearsInRanking(bool appears) async {
    this.appears = appears;
  }
}

class RoomTimeRejected implements Exception {
  RoomTimeRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabaseRoomTimeGateway implements RoomTimeGateway {
  SupabaseRoomTimeGateway(this.client);

  final SupabaseClient client;

  @override
  Future<List<RoomTimeLine>> ranking(String roomId) async {
    final raw = await client.rpc('room_time_ranking', params: {
      'p_room_id': roomId,
      'p_limit': 10,
    });
    return [
      for (final row in _rows(raw))
        RoomTimeLine(
          place: _intOf(row['rank_place']),
          groupName: '${row['group_name']}',
          elapsedSeconds: _intOf(row['elapsed_seconds']),
          remainingSeconds: _intOf(row['remaining_seconds']),
          playedOn: _dateOf(row['played_on']),
          members: _labels(row['members']),
          escaped: true,
        ),
    ];
  }

  @override
  Future<List<RoomTimeLine>> mine() async {
    final raw = await client.rpc('my_room_times');
    return [
      for (final row in _rows(raw))
        RoomTimeLine(
          entryId: row['entry_id']?.toString(),
          place: row['rank_place'] == null ? null : _intOf(row['rank_place']),
          roomName: '${row['room_name']}',
          venueName: '${row['venue_name']}',
          groupName: '${row['group_name']}',
          elapsedSeconds: _intOf(row['elapsed_seconds']),
          remainingSeconds: _intOf(row['remaining_seconds']),
          playedOn: _dateOf(row['played_on']),
          members: _labels(row['members']),
          escaped: row['escaped'] == true,
        ),
    ];
  }

  @override
  Future<String> teamName(String groupId) async {
    final raw = await client.rpc('group_team_name', params: {
      'p_group_id': groupId,
    });
    final name = raw?.toString().trim() ?? '';
    if (name.isEmpty) return roomTimeDefaultGroup;
    return name;
  }

  @override
  Future<void> setTeamName(String groupId, String name) async {
    final error = roomTimeNameError(name);
    if (error != null) throw RoomTimeRejected(error);
    try {
      await client.rpc('set_group_team_name', params: {
        'p_group_id': groupId,
        'p_name': name.trim(),
      });
    } on PostgrestException catch (error) {
      throw RoomTimeRejected(error.message);
    }
  }

  @override
  Future<bool> appearsInRanking() async {
    final raw = await client.rpc('my_room_time_visibility');
    return raw == true;
  }

  @override
  Future<void> setAppearsInRanking(bool appears) async {
    try {
      await client.rpc('set_my_room_time_visibility', params: {
        'p_show': appears,
      });
    } on PostgrestException catch (error) {
      throw RoomTimeRejected(error.message);
    }
  }
}

List<Map<String, dynamic>> _rows(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final row in raw)
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse('$value');
}

DateTime _dateOf(Object? value) {
  final text = '$value';
  final parsed = DateTime.tryParse(text);
  return parsed ?? DateTime(1970);
}

List<String> _labels(Object? value) {
  if (value is! List) return const [];
  return [for (final item in value) '$item'];
}
