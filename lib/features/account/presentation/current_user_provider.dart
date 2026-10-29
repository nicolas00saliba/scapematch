import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/account/domain/current_user.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';

/// Who is using the app in this session.
///
/// Segue a sessão. Sem sessão, ainda devolve o usuário de exemplo para
/// telas que exigem um dono. Meus grupos, Criar grupo e o convite não usam
/// esse fallback: eles leem [authSessionProvider] e pedem login.
final currentUserProvider = Provider<CurrentUser>((ref) {
  return ref.watch(authSessionProvider) ?? sampleCurrentUser;
});
