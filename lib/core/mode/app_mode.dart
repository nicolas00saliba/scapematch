import 'package:flutter/foundation.dart';

/// Flavor de um build. O deploy passa `--dart-define=APP_MODE=real` ou `demo`.
enum AppMode { real, demo }

/// Valor cru do `--dart-define`. O padrão é o app real.
const String appModeName = String.fromEnvironment(
  'APP_MODE',
  defaultValue: 'real',
);

AppMode parseAppMode(String raw) {
  switch (raw) {
    case 'real':
      return AppMode.real;
    case 'demo':
      return AppMode.demo;
    default:
      throw FormatException('APP_MODE deve ser real ou demo.');
  }
}

/// Modo deste binário. Sem o define, o release é o app real.
const AppMode kAppMode = appModeName == 'demo' ? AppMode.demo : AppMode.real;

/// Banco de exemplo, logins de casa e o selo. Falso só no release real,
/// para o compilador cortar esse ramo. Os testes continuam na memória.
const bool kAllowSampleData = kAppMode == AppMode.demo || !kReleaseMode;

const bool kAllowSampleLogin = kAllowSampleData;

const bool kShowDemoChrome = kAllowSampleData;

/// O que o processo liga no arranque. As telas não escolhem isso.
class BackendPlan {
  const BackendPlan(this.mode);

  final AppMode mode;

  bool get connectsSupabase => mode == AppMode.real;

  bool get loadsSampleDatabase => mode == AppMode.demo;
}

BackendPlan planFor(AppMode mode) => BackendPlan(mode);
