import 'package:scapematch/core/web/document_base.dart';
import 'package:scapematch/features/auth/data/auth_return_url.dart';

/// Raiz que o e-mail do Auth abre. É o `start_url` do ícone, dentro do PWA.
String? webAuthRedirect([Uri? page, String? baseHref]) {
  final href = baseHref ?? documentBaseHref();
  if (href == null) return null;
  return authReturnUrl(page ?? Uri.base, href);
}
