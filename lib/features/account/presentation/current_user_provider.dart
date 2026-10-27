import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/domain/current_user.dart';

/// Who is using the app in this session.
///
/// Override this in tests, and replace the body with a real session when
/// login arrives. Callers should read [CurrentUser] from here instead of
/// writing the name "Você" into a repository call.
final currentUserProvider = Provider<CurrentUser>((ref) {
  return sampleCurrentUser;
});
