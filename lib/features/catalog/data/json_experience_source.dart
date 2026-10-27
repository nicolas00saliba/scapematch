import 'dart:convert';

import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/experience_source.dart';
import 'package:scapematch/features/catalog/domain/schedule_availability.dart';

/// Reads one house from a JSON object already in memory.
///
/// This class does not open files, assets, or the network. Callers pass
/// the text. [AssetExperienceSource] is the example that loads a bundled file.
class JsonExperienceSource implements ExperienceSource {
  JsonExperienceSource({
    required this.houseId,
    required Future<String> Function() readJson,
  }) : _readJson = readJson;

  JsonExperienceSource.fromJsonString({
    required this.houseId,
    required String json,
  }) : _readJson = (() async => json);

  @override
  final String houseId;

  final Future<String> Function() _readJson;

  @override
  Future<ExperienceOffering> fetchOffering() async {
    final raw = jsonDecode(await _readJson());
    final offering = parseExperienceOffering(raw);
    if (offering.houseId != houseId) {
      throw FormatException(
        'JSON houseId "${offering.houseId}" does not match $houseId',
      );
    }
    return offering;
  }
}

/// Parses the example house document. Throws [FormatException] when a
/// required field is missing or a session points at an unknown room.
ExperienceOffering parseExperienceOffering(Object? raw) {
  final json = _asMap(raw, 'offering');
  final houseId = _string(json, 'houseId');
  final rooms = _asList(json['rooms'], 'rooms').map(_parseRoom).toList();
  final roomIds = rooms.map((room) => room.id).toSet();
  if (roomIds.length != rooms.length) {
    throw const FormatException('Room ids must be unique inside one house');
  }
  final sessions = _asList(
    json['sessions'],
    'sessions',
  ).map((item) => _parseSession(item, roomIds)).toList();

  return ExperienceOffering(
    houseId: houseId,
    houseName: _string(json, 'houseName'),
    cityId: _string(json, 'cityId'),
    neighborhood: _string(json, 'neighborhood'),
    origin: _string(json, 'origin'),
    rooms: List.unmodifiable(rooms),
    sessions: List.unmodifiable(sessions),
  );
}

SourcedRoom _parseRoom(Object? raw) {
  final json = _asMap(raw, 'room');
  final capacity = _positiveInt(json, 'capacity');
  final duration = _positiveInt(json, 'durationMinutes');
  return SourcedRoom(
    id: _string(json, 'id'),
    name: _string(json, 'name'),
    theme: _string(json, 'theme'),
    capacity: capacity,
    durationMinutes: duration,
    difficulty: _difficulty(_string(json, 'difficulty')),
  );
}

SourcedSession _parseSession(Object? raw, Set<String> roomIds) {
  final json = _asMap(raw, 'session');
  final roomId = _string(json, 'roomId');
  if (!roomIds.contains(roomId)) {
    throw FormatException('Session refers to unknown room $roomId');
  }
  final availability = ScheduleAvailabilityText.parse(
    _string(json, 'availability'),
  );
  final startsAt = _optionalDate(json['startsAt'], 'startsAt');
  if (availability == ScheduleAvailability.toBeArranged) {
    if (startsAt != null) {
      throw const FormatException(
        'A session marked toBeArranged cannot have startsAt',
      );
    }
  } else if (startsAt == null) {
    throw FormatException(
      'Session ${_string(json, 'id')} needs startsAt '
      'because it is ${availability.name}',
    );
  }
  return SourcedSession(
    id: _string(json, 'id'),
    roomId: roomId,
    startsAt: startsAt,
    availability: availability,
  );
}

Difficulty _difficulty(String raw) {
  for (final value in Difficulty.values) {
    if (value.name == raw) {
      return value;
    }
  }
  throw FormatException('Unknown difficulty: $raw');
}

Map<String, dynamic> _asMap(Object? raw, String label) {
  if (raw is! Map) {
    throw FormatException('$label must be an object');
  }
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

List<Object?> _asList(Object? raw, String label) {
  if (raw is! List) {
    throw FormatException('$label must be a list');
  }
  return raw;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

int _positiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('$key must be a positive integer');
  }
  return value;
}

DateTime? _optionalDate(Object? raw, String label) {
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw FormatException('$label must be an ISO-8601 string or null');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('$label is not a date: $raw');
  }
  return parsed;
}
