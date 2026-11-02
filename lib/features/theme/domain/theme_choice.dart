import 'package:flutter/material.dart';

/// Aparência escolhida na Conta. Automático segue o aparelho.
///
/// Sem chave salva, o padrão é Claro. Um valor desconhecido continua
/// Automático, para não apagar uma escolha que o app ainda não conhece.
enum ThemeChoice {
  light,
  dark,
  system;

  ThemeMode get mode {
    return switch (this) {
      ThemeChoice.light => ThemeMode.light,
      ThemeChoice.dark => ThemeMode.dark,
      ThemeChoice.system => ThemeMode.system,
    };
  }

  String get labelPt {
    return switch (this) {
      ThemeChoice.light => 'Claro',
      ThemeChoice.dark => 'Escuro',
      ThemeChoice.system => 'Automático',
    };
  }

  IconData get icon {
    return switch (this) {
      ThemeChoice.light => Icons.light_mode,
      ThemeChoice.dark => Icons.dark_mode,
      ThemeChoice.system => Icons.brightness_auto,
    };
  }

  static ThemeChoice parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return ThemeChoice.light;
    }
    for (final choice in ThemeChoice.values) {
      if (choice.name == raw) {
        return choice;
      }
    }
    return ThemeChoice.system;
  }
}
