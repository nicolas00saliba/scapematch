import 'dart:convert';

import 'package:dominio/dominio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Última regra lida neste aparelho.
///
/// Sem chave, o app usa o padrão do código. Com a chave, a tela abre
/// no último valor mesmo sem rede.
class RewardRulesStore {
  RewardRulesStore({PublicRewardRules? current})
    : current = current ?? PublicRewardRules.fallback;

  static const storageKey = 'reward_rules_public';

  PublicRewardRules current;
  var hasCache = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    current = PublicRewardRules.fromJson(Map<String, dynamic>.from(decoded));
    hasCache = true;
  }

  Future<void> save(PublicRewardRules rules) async {
    current = rules;
    hasCache = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(rules.toJson()));
  }
}
