/// A bookable start time for one room. Dates here are sample data.
class TimeSlot {
  const TimeSlot({
    required this.id,
    required this.roomId,
    required this.startsAt,
    this.active = true,
  });

  final String id;
  final String roomId;
  final DateTime startsAt;

  /// Falso depois que a casa tira o horário da grade. A linha fica, para
  /// o grupo, o fomento e os pontos continuarem apontando para ela.
  final bool active;
}
