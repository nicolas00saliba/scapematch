import 'package:dominio/dominio.dart';
import 'package:scapematch/features/ranking/data/room_time_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomTimeMemberDraft {
  const RoomTimeMemberDraft({required this.userId, required this.label});

  final String userId;
  final String label;
}

class RoomTimeDraft {
  const RoomTimeDraft({
    required this.groupName,
    required this.elapsedSeconds,
    required this.escaped,
    required this.members,
  });

  final String groupName;
  final int elapsedSeconds;
  final bool escaped;
  final List<RoomTimeMemberDraft> members;
}

class VenueTimePrefs {
  const VenueTimePrefs({
    required this.showPublic,
    required this.showMembers,
  });

  final bool showPublic;
  final bool showMembers;
}

abstract class PartnerRoomTimeGateway {
  Future<VenueTimePrefs> prefs(String venueId);
  Future<VenueTimePrefs> savePrefs(String venueId, VenueTimePrefs prefs);
  Future<List<RoomTimeLine>> times(String roomId);
  Future<void> record(String groupId, RoomTimeDraft draft);
  Future<void> edit(String entryId, RoomTimeDraft draft);
  Future<void> remove(String entryId);
}

class MemoryPartnerRoomTimeGateway implements PartnerRoomTimeGateway {
  MemoryPartnerRoomTimeGateway({
    VenueTimePrefs? prefs,
    List<RoomTimeLine>? times,
  }) : prefsState = prefs ??
           const VenueTimePrefs(showPublic: true, showMembers: false),
       lines = [...?times];

  VenueTimePrefs prefsState;
  final List<RoomTimeLine> lines;

  @override
  Future<VenueTimePrefs> prefs(String venueId) async => prefsState;

  @override
  Future<VenueTimePrefs> savePrefs(String venueId, VenueTimePrefs prefs) async {
    prefsState = prefs;
    return prefsState;
  }

  @override
  Future<List<RoomTimeLine>> times(String roomId) async => List.of(lines);

  @override
  Future<void> record(String groupId, RoomTimeDraft draft) async {
    _reject(draft);
  }

  @override
  Future<void> edit(String entryId, RoomTimeDraft draft) async {
    _reject(draft);
    final index = lines.indexWhere((line) => line.entryId == entryId);
    if (index < 0) throw RoomTimeRejected('tempo não encontrado');
    final current = lines[index];
    lines[index] = RoomTimeLine(
      entryId: current.entryId,
      groupId: current.groupId,
      place: current.place,
      groupName: roomTimeNameOrDefault(draft.groupName),
      elapsedSeconds: draft.elapsedSeconds,
      remainingSeconds: (current.elapsedSeconds + current.remainingSeconds -
              draft.elapsedSeconds)
          .clamp(0, 1 << 30),
      playedOn: current.playedOn,
      members: [for (final member in draft.members) firstLabel(member.label)],
      memberIds: [for (final member in draft.members) member.userId],
      escaped: draft.escaped,
      roomName: current.roomName,
      venueName: current.venueName,
    );
  }

  @override
  Future<void> remove(String entryId) async {
    lines.removeWhere((line) => line.entryId == entryId);
  }

  void _reject(RoomTimeDraft draft) {
    final error = roomTimeNameError(draft.groupName);
    if (error != null) throw RoomTimeRejected(error);
    if (draft.elapsedSeconds < 1) {
      throw RoomTimeRejected('O tempo fica entre 1 segundo e a duração da sala.');
    }
  }
}

class SupabasePartnerRoomTimeGateway implements PartnerRoomTimeGateway {
  SupabasePartnerRoomTimeGateway(this.client);

  final SupabaseClient client;

  @override
  Future<VenueTimePrefs> prefs(String venueId) async {
    final raw = await _rpc('venue_time_ranking', {'p_venue_id': venueId});
    return _prefs(raw);
  }

  @override
  Future<VenueTimePrefs> savePrefs(String venueId, VenueTimePrefs prefs) async {
    final raw = await _rpc('set_venue_time_ranking', {
      'p_venue_id': venueId,
      'p_show_public': prefs.showPublic,
      'p_show_members': prefs.showMembers,
    });
    return _prefs(raw);
  }

  @override
  Future<List<RoomTimeLine>> times(String roomId) async {
    final raw = await _rpc('partner_room_times', {'p_room_id': roomId});
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map)
          RoomTimeLine(
            entryId: row['entry_id']?.toString(),
            groupId: row['group_id']?.toString(),
            place: row['rank_place'] == null ? null : _intOf(row['rank_place']),
            groupName: '${row['group_name']}',
            elapsedSeconds: _intOf(row['elapsed_seconds']),
            remainingSeconds: _intOf(row['remaining_seconds']),
            playedOn: DateTime.tryParse('${row['played_on']}') ?? DateTime(1970),
            members: _memberLabels(row['members']),
            memberIds: _memberIds(row['members']),
            escaped: row['escaped'] == true,
          ),
    ];
  }

  @override
  Future<void> record(String groupId, RoomTimeDraft draft) async {
    _check(draft);
    await _rpc('record_room_time', {
      'p_group_id': groupId,
      'p_elapsed_seconds': draft.elapsedSeconds,
      'p_escaped': draft.escaped,
      'p_group_name': draft.groupName.trim(),
      'p_members': _members(draft),
    });
  }

  @override
  Future<void> edit(String entryId, RoomTimeDraft draft) async {
    _check(draft);
    await _rpc('edit_room_time', {
      'p_entry_id': entryId,
      'p_elapsed_seconds': draft.elapsedSeconds,
      'p_escaped': draft.escaped,
      'p_group_name': draft.groupName.trim(),
      'p_members': _members(draft),
    });
  }

  @override
  Future<void> remove(String entryId) async {
    await _rpc('remove_room_time', {'p_entry_id': entryId});
  }

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await client.rpc(name, params: params);
    } on PostgrestException catch (error) {
      throw RoomTimeRejected(error.message);
    }
  }

  void _check(RoomTimeDraft draft) {
    final error = roomTimeNameError(draft.groupName);
    if (error != null) throw RoomTimeRejected(error);
  }
}

VenueTimePrefs _prefs(Object? raw) {
  final map = raw is Map ? raw : const {};
  return VenueTimePrefs(
    showPublic: map['show_public'] != false,
    showMembers: map['show_members'] == true,
  );
}

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse('$value');
}

List<String> _memberLabels(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map && item['published'] == true) '${item['label']}',
  ];
}

List<String> _memberIds(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map && item['published'] == true) '${item['user_id']}',
  ];
}

List<Map<String, String>>? _members(RoomTimeDraft draft) {
  if (draft.members.isEmpty) return null;
  return [
    for (final member in draft.members)
      {'user_id': member.userId, 'label': member.label},
  ];
}
