class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    required this.isCreator,
    required this.isLocalUser,
    this.userId,
  });

  /// Membership id. Unique inside the database, not the account id.
  final String id;

  /// Account id when this seat belongs to a known user.
  /// Sample players leave this null. The local stand-in user fills it
  /// from the current-user provider so login can match the same field later.
  final String? userId;

  final String displayName;
  final bool isCreator;

  /// True when this seat is the person using this app session.
  /// A shared database should compare [userId] instead of trusting this flag.
  final bool isLocalUser;
}
