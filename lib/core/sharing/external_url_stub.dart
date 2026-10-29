/// Abre uma URL fora do app. No teste e no VM isso não abre nada.
Future<bool> openExternalUrl(Uri uri) async => false;

/// Folha de compartilhar do sistema. No teste não existe.
Future<bool> sharePlainText(String text) async => false;
