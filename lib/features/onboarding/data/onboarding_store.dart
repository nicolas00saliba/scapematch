import 'package:shared_preferences/shared_preferences.dart';

/// A introdução do app real já foi vista neste aparelho.
///
/// Na web, [SharedPreferences] usa o localStorage do domínio. Real e
/// demonstração saem no mesmo site, em caminhos diferentes, então a
/// demonstração não grava esta chave: “Ver introdução” lá não pode
/// dispensar a primeira abertura do app real. Sem a chave, o app real
/// ainda não passou pela introdução.
class OnboardingStore {
  OnboardingStore({this.persist = true, this._seen = false});

  /// Chave só do app real. A antiga `onboarding_seen` fica de lado: a
  /// demonstração também escrevia nela.
  static const storageKey = 'onboarding_seen_real';

  /// Falso na demonstração. O app real lê e grava [storageKey].
  final bool persist;

  bool _seen;

  bool get seen => _seen;

  Future<void> load() async {
    if (!persist) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _seen = prefs.getBool(storageKey) ?? false;
  }

  Future<void> markSeen() async {
    _seen = true;
    if (!persist) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey, true);
  }
}
