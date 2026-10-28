import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipo de jogo escolhido, gravado no aparelho.
///
/// Na web, [SharedPreferences] usa o localStorage. Sem chave, ou com um
/// valor que o app não conhece, a leitura vira “Todos”.
class SelectedGameTypeStore {
  SelectedGameTypeStore({String? savedGameTypeId})
    : _gameTypeId = _knownOrNull(savedGameTypeId);

  static const storageKey = 'selected_game_type';

  String? _gameTypeId;

  /// Escolha salva, ou Todos quando não há uma válida.
  String resolve() => _gameTypeId ?? GameTypes.all;

  void remember(String gameTypeId) {
    _gameTypeId = _knownOrNull(gameTypeId);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _gameTypeId = _knownOrNull(prefs.getString(storageKey));
  }

  Future<void> persist(String gameTypeId) async {
    final known = _knownOrNull(gameTypeId) ?? GameTypes.all;
    _gameTypeId = known;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, known);
  }

  static String? _knownOrNull(String? value) {
    if (value == null || value.isEmpty || !GameTypes.isKnown(value)) {
      return null;
    }
    return value;
  }
}
