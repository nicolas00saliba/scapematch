import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/schedule_availability.dart';

/// Rooms and sessions published for a single escape house.
///
/// One implementation per house. A partner API, a file the house sends,
/// or a future allowed integration all look like this to the app. The
/// screens keep talking to CatalogRepository; a repository can fill
/// itself from these sources later. Nothing here fetches a website.
abstract class ExperienceSource {
  /// Id of the house this source speaks for.
  String get houseId;

  Future<ExperienceOffering> fetchOffering();
}

/// What one house source returned: its rooms and its sessions.
class ExperienceOffering {
  const ExperienceOffering({
    required this.houseId,
    required this.houseName,
    required this.cityId,
    required this.neighborhood,
    required this.origin,
    required this.rooms,
    required this.sessions,
  });

  final String houseId;
  final String houseName;
  final String cityId;
  final String neighborhood;

  /// Short name of where this offering came from, such as `local-json`.
  /// A real feed would put the partner or file name here, not a scraped URL
  /// hidden from the rest of the app.
  final String origin;

  final List<SourcedRoom> rooms;
  final List<SourcedSession> sessions;
}

class SourcedRoom {
  const SourcedRoom({
    required this.id,
    required this.name,
    required this.theme,
    required this.capacity,
    required this.durationMinutes,
    required this.difficulty,
  });

  final String id;
  final String name;
  final String theme;
  final int capacity;
  final int durationMinutes;
  final Difficulty difficulty;
}

class SourcedSession {
  const SourcedSession({
    required this.id,
    required this.roomId,
    required this.startsAt,
    required this.availability,
  });

  final String id;
  final String roomId;

  /// Null only when [availability] is [ScheduleAvailability.toBeArranged].
  final DateTime? startsAt;
  final ScheduleAvailability availability;
}
