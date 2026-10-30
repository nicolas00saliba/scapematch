import 'package:shared_preferences/shared_preferences.dart';

/// A introdução já foi vista neste aparelho.
///
/// Na web, [SharedPreferences] usa o localStorage. Sem a chave, a pessoa
/// ainda não passou pela introdução.
class OnboardingStore {
  OnboardingStore({this._seen = false});

  static const storageKey = 'onboarding_seen';

  bool _seen;

  bool get seen => _seen;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _seen = prefs.getBool(storageKey) ?? false;
  }

  Future<void> markSeen() async {
    _seen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey, true);
  }
}
