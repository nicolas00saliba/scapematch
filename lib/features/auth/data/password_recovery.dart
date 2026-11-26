import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fica verdadeiro quando o link de nova senha abre o app.
///
/// O Auth emite [AuthChangeEvent.passwordRecovery] durante o
/// `Supabase.initialize`, antes do primeiro frame. O stream reapresenta
/// o último evento, então o ouvinte entra logo depois do boot.
final passwordRecoverySignal = PasswordRecoverySignal();

class PasswordRecoverySignal extends ChangeNotifier {
  var pending = false;

  void mark() {
    if (pending) return;
    pending = true;
    notifyListeners();
  }

  void clear() {
    if (!pending) return;
    pending = false;
    notifyListeners();
  }
}

/// O fragmento ou a query do link traz `type=recovery`.
bool passwordRecoveryLink(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  if (uri.fragment.isNotEmpty) {
    params.addAll(Uri.splitQueryString(uri.fragment));
  }
  return params['type'] == 'recovery';
}

void notePasswordRecoveryLink(Uri uri) {
  if (passwordRecoveryLink(uri)) passwordRecoverySignal.mark();
}

void notePasswordRecoveryEvent(AuthChangeEvent event) {
  if (event == AuthChangeEvent.passwordRecovery) {
    passwordRecoverySignal.mark();
  }
}

/// Ouve o Auth. O `onError` é obrigatório: sem ele, uma falha de rede
/// no refresh vira exceção solta.
void watchPasswordRecovery(GoTrueClient auth) {
  auth.onAuthStateChange.listen(
    (data) => notePasswordRecoveryEvent(data.event),
    onError: (Object _, StackTrace _) {},
  );
}
