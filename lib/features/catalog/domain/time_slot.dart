/// A bookable start time for one room. Dates here are sample data.
class TimeSlot {
  const TimeSlot({
    required this.id,
    required this.roomId,
    required this.startsAt,
  });

  final String id;
  final String roomId;
  final DateTime startsAt;
}
