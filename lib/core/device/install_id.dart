import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Identificador da instalação. Não é anúncio, telefone nem conta.
class InstallId {
  static const storageKey = 'scape_install_id';

  static final _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isValid(String value) => _pattern.hasMatch(value);

  static String create(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<String?> readOrCreate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(storageKey);
      if (current != null && isValid(current)) return current;
      final created = create(Random.secure());
      await prefs.setString(storageKey, created);
      return created;
    } on Object {
      return null;
    }
  }
}
