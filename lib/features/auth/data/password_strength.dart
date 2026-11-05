import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Frase da regra local: 8 caracteres, com letra e número.
const passwordRuleMessage =
    'A senha precisa de pelo menos 8 caracteres, com letras e números.';

/// Frase quando a senha aparece na lista do Have I Been Pwned.
const leakedPasswordMessage =
    'Essa senha apareceu em vazamentos. Escolha outra.';

/// Nulo quando a senha cumpre o mínimo. Não consulta a rede.
String? passwordRuleError(String password) {
  final longEnough = password.length >= 8;
  final hasLetter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').hasMatch(password);
  final hasDigit = RegExp(r'\d').hasMatch(password);
  if (longEnough && hasLetter && hasDigit) return null;
  return passwordRuleMessage;
}

/// Recusa senha fraca ou vazada. Se a API falhar, devolve nulo.
///
/// O SHA-1 fica neste aparelho. A rede só recebe os 5 primeiros
/// caracteres do hash, no esquema k-anonymity do Pwned Passwords.
/// `Add-Padding: true` completa a resposta com linhas de contagem zero;
/// só contagem maior que zero recusa a senha.
Future<String?> rejectPassword(
  String password, {
  http.Client? httpClient,
}) async {
  final rule = passwordRuleError(password);
  if (rule != null) return rule;

  final digest = sha1.convert(utf8.encode(password)).toString().toUpperCase();
  final prefix = digest.substring(0, 5);
  final suffix = digest.substring(5);
  final client = httpClient ?? http.Client();
  try {
    final response = await client
        .get(
          Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
          headers: const {'Add-Padding': 'true'},
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    if (_suffixWasLeaked(response.body, suffix)) return leakedPasswordMessage;
    return null;
  } on Object {
    return null;
  } finally {
    if (httpClient == null) client.close();
  }
}

bool _suffixWasLeaked(String body, String suffix) {
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final split = line.split(':');
    if (split.length < 2) continue;
    if (split[0].toUpperCase() != suffix) continue;
    final count = int.tryParse(split[1]) ?? 0;
    if (count > 0) return true;
  }
  return false;
}
