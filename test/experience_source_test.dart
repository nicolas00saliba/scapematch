import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/catalog/data/asset_experience_source.dart';
import 'package:scapematch/features/catalog/data/json_experience_source.dart';
import 'package:scapematch/features/catalog/domain/schedule_availability.dart';

void main() {
  test('example JSON exposes every availability kind', () async {
    final json = File('assets/experience/example_house.json')
        .readAsStringSync();
    final source = JsonExperienceSource.fromJsonString(
      houseId: AssetExperienceSource.exampleHouseId,
      json: json,
    );

    final offering = await source.fetchOffering();

    expect(offering.houseName, 'Casa Exemplo');
    expect(offering.origin, 'local-json');
    expect(offering.rooms, hasLength(1));
    expect(offering.rooms.single.capacity, 6);
    expect(
      offering.sessions.map((session) => session.availability).toSet(),
      ScheduleAvailability.values.toSet(),
    );

    final arranged = offering.sessions.singleWhere(
      (session) => session.availability == ScheduleAvailability.toBeArranged,
    );
    expect(arranged.startsAt, isNull);
    expect(arranged.availability.labelPt, 'A combinar');

    final integrated = offering.sessions.singleWhere(
      (session) => session.availability == ScheduleAvailability.integrated,
    );
    expect(integrated.startsAt, DateTime(2026, 11, 14, 19));
    expect(integrated.availability.labelPt, 'Horário integrado');
  });

  test('the bundled asset is the example the adapter reads', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final offering = await AssetExperienceSource.example().fetchOffering();

    expect(offering.houseId, AssetExperienceSource.exampleHouseId);
    expect(offering.sessions, hasLength(ScheduleAvailability.values.length));
  });

  test('a session for an unknown room is rejected', () async {
    const json = '''
      {
        "houseId": "example-house",
        "houseName": "Casa Exemplo",
        "cityId": "sao-paulo",
        "neighborhood": "Centro",
        "origin": "local-json",
        "rooms": [
          {
            "id": "room-a",
            "name": "Sala",
            "theme": "Tema",
            "capacity": 4,
            "durationMinutes": 60,
            "difficulty": "easy"
          }
        ],
        "sessions": [
          {
            "id": "session-a",
            "roomId": "missing-room",
            "startsAt": "2026-11-14T19:00:00",
            "availability": "integrated"
          }
        ]
      }
    ''';

    final source = JsonExperienceSource.fromJsonString(
      houseId: 'example-house',
      json: json,
    );

    expect(source.fetchOffering(), throwsFormatException);
  });

  test('toBeArranged cannot carry a clock time', () async {
    const json = '''
      {
        "houseId": "example-house",
        "houseName": "Casa Exemplo",
        "cityId": "sao-paulo",
        "neighborhood": "Centro",
        "origin": "local-json",
        "rooms": [
          {
            "id": "room-a",
            "name": "Sala",
            "theme": "Tema",
            "capacity": 4,
            "durationMinutes": 60,
            "difficulty": "easy"
          }
        ],
        "sessions": [
          {
            "id": "session-a",
            "roomId": "room-a",
            "startsAt": "2026-11-14T19:00:00",
            "availability": "toBeArranged"
          }
        ]
      }
    ''';

    expect(
      JsonExperienceSource.fromJsonString(
        houseId: 'example-house',
        json: json,
      ).fetchOffering(),
      throwsFormatException,
    );
  });
}
