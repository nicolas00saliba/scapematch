class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    required this.isCreator,
    required this.isLocalUser,
  });

  final String id;
  final String displayName;
  final bool isCreator;

  /// True for the person using this phone. There is no account yet,
  /// so the app marks that person locally as "Você".
  final bool isLocalUser;
}
