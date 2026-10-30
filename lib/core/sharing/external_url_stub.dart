import 'package:scapematch/core/sharing/external_url_launch.dart';

/// Abre o link fora da tela atual. A implementação é a mesma da web.
Future<bool> openExternalUrl(Uri uri) => launchExternalUrl(uri);

/// Folha de compartilhar do sistema. No teste não existe.
Future<bool> sharePlainText(String text) async => false;
