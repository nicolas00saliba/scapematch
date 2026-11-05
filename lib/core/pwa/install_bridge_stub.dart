import 'package:scapematch/core/pwa/install_offer.dart';

/// No VM e nos testes o navegador não oferece instalação.
void listenForInstallPrompt(void Function() onChange) {}

InstallSignals readInstallSignals() {
  return const InstallSignals(
    standalone: false,
    ios: false,
    promptReady: false,
    dismissed: false,
  );
}

Future<String> launchBrowserInstall() async => 'missing';

void rememberInstallDismissed() {}
