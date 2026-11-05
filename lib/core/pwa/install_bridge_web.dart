import 'dart:js_interop';

import 'package:scapematch/core/pwa/install_offer.dart';
import 'package:web/web.dart';

@JS('scapeInstallPrompt')
external JSAny? get _scapeInstallPrompt;

@JS('scapeLaunchInstall')
external JSPromise<JSString> _scapeLaunchInstall();

@JS('navigator.standalone')
external JSBoolean? get _navigatorStandalone;

void listenForInstallPrompt(void Function() onChange) {
  window.addEventListener('scape-install-prompt', ((Event _) => onChange()).toJS);
  for (final query in const [
    '(display-mode: standalone)',
    '(display-mode: fullscreen)',
    '(display-mode: minimal-ui)',
  ]) {
    window.matchMedia(query).addEventListener('change', ((Event _) => onChange()).toJS);
  }
}

InstallSignals readInstallSignals() {
  try {
    final standalone =
        _display('standalone') ||
        _display('fullscreen') ||
        _display('minimal-ui') ||
        _navigatorStandalone?.toDart == true;
    return InstallSignals(
      standalone: standalone,
      ios: _looksLikeIos(),
      promptReady: _scapeInstallPrompt != null,
      dismissed: window.localStorage.getItem(_dismissKey()) == '1',
    );
  } on Object {
    return const InstallSignals(
      standalone: false,
      ios: false,
      promptReady: false,
      dismissed: false,
    );
  }
}

Future<String> launchBrowserInstall() async {
  try {
    final outcome = await _scapeLaunchInstall().toDart;
    return outcome.toDart;
  } on Object {
    return 'missing';
  }
}

void rememberInstallDismissed() {
  window.localStorage.setItem(_dismissKey(), '1');
}

bool _display(String mode) {
  return window.matchMedia('(display-mode: $mode)').matches;
}

bool _looksLikeIos() {
  final ua = window.navigator.userAgent;
  if (RegExp('iPad|iPhone|iPod').hasMatch(ua)) return true;
  // iPadOS 13+ se apresenta como Macintosh, mas o toque continua.
  return ua.contains('Macintosh') && window.navigator.maxTouchPoints > 1;
}

String _dismissKey() {
  final href = document.querySelector('base')?.getAttribute('href') ?? '/';
  return 'scapematch-install-dismissed:$href';
}
