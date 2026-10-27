/// How a start time is known for one room.
///
/// These are the ways a future house feed can describe a session.
/// The sample app's groups still use fixed fictional slots. An
/// ExperienceSource returns this model so a partner feed, a file, or a
/// later integration can say how sure the time is.
enum ScheduleAvailability {
  /// The house published this start time on its own schedule.
  /// Product name: horário integrado.
  integrated,

  /// A partner sent a grid of openings.
  /// Product name: grade do parceiro.
  partnerGrid,

  /// Somebody suggested a time. The house has not confirmed it.
  /// Product name: horário proposto.
  proposed,

  /// The session has no fixed clock time yet.
  /// Product name: a combinar. [startsAt] on the session stays null.
  toBeArranged,
}

extension ScheduleAvailabilityText on ScheduleAvailability {
  String get labelPt {
    return switch (this) {
      ScheduleAvailability.integrated => 'Horário integrado',
      ScheduleAvailability.partnerGrid => 'Grade do parceiro',
      ScheduleAvailability.proposed => 'Horário proposto',
      ScheduleAvailability.toBeArranged => 'A combinar',
    };
  }

  static ScheduleAvailability parse(String raw) {
    for (final value in ScheduleAvailability.values) {
      if (value.name == raw) {
        return value;
      }
    }
    throw FormatException('Unknown schedule availability: $raw');
  }
}
