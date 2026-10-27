/// The person using the app right now.
///
/// There is no login yet. [sampleCurrentUser] is a stand-in so screens and
/// repositories stop hardcoding the name "Você". When accounts exist, the
/// provider that returns this object should read the signed-in user and
/// keep the same fields.
class CurrentUser {
  const CurrentUser({required this.id, required this.displayName});

  /// Stable id for this person. Today it is local. Tomorrow it is the
  /// account id from the auth provider.
  final String id;

  /// Name other people see on the group. The sample user is "Você".
  final String displayName;
}

/// Fictional signed-in user used until login replaces the provider.
const sampleCurrentUser = CurrentUser(id: 'user-local', displayName: 'Você');
