import 'package:shared_preferences/shared_preferences.dart';

/// Grupo que a pessoa quis entrar antes de ter conta.
///
/// A chave fica no aparelho. Um valor vazio é o mesmo que não ter intenção.
class PendingInviteStore {
  PendingInviteStore({String? groupId}) : _groupId = _blankToNull(groupId);

  static const storageKey = 'pending_group_id';

  String? _groupId;

  String? get groupId => _groupId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _groupId = _blankToNull(prefs.getString(storageKey));
  }

  Future<void> save(String groupId) async {
    _groupId = _blankToNull(groupId);
    final prefs = await SharedPreferences.getInstance();
    if (_groupId == null) {
      await prefs.remove(storageKey);
      return;
    }
    await prefs.setString(storageKey, _groupId!);
  }

  Future<void> clear() async {
    _groupId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }

  static String? _blankToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
