import 'package:scapematch/core/data/sample_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cidade escolhida, gravada no aparelho.
///
/// Na web, [SharedPreferences] usa o localStorage do navegador. A ausência
/// da chave não é preenchida sozinha: quem lê trata isso como Curitiba.
class SelectedCityStore {
  SelectedCityStore({String? savedCityId})
    : _cityId = _blankToNull(savedCityId);

  static const storageKey = 'selected_city_id';

  String? _cityId;

  /// Cidade salva, ou Curitiba quando não há escolha.
  String resolve() => _cityId ?? SampleIds.curitiba;

  void remember(String cityId) {
    _cityId = cityId;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cityId = _blankToNull(prefs.getString(storageKey));
  }

  Future<void> persist(String cityId) async {
    _cityId = cityId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, cityId);
  }

  static String? _blankToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
