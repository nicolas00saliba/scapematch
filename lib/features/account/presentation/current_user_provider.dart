import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';

/// Who is using the app in this session.
///
/// Segue a sessão. Sem sessão, continua o usuário de exemplo, para as
/// telas que já existem não quebrarem. O convite olha [authSessionProvider]
/// para saber se a pessoa está logada de verdade.
final currentUserProvider = Provider<CurrentUser>((ref) {
  return ref.watch(authSessionProvider) ?? sampleCurrentUser;
});
