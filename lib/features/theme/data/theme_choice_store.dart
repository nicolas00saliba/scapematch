import 'package:scapematch/features/theme/domain/theme_choice.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema gravado no aparelho.
///
/// Na web, [SharedPreferences] usa o localStorage. Sem chave, ou com um
/// valor desconhecido, a leitura vira Automático.
class ThemeChoiceStore {
  ThemeChoiceStore({String? saved}) : _choice = ThemeChoice.parse(saved);

  static const storageKey = 'theme_choice';

  ThemeChoice _choice;

  ThemeChoice get choice => _choice;

  void remember(ThemeChoice choice) {
    _choice = choice;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _choice = ThemeChoice.parse(prefs.getString(storageKey));
  }

  Future<void> persist(ThemeChoice choice) async {
    _choice = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, choice.name);
  }
}
