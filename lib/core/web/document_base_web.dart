import 'package:web/web.dart';

/// O `<base href>` que o `flutter build --base-href` gravou.
String? documentBaseHref() {
  final href = document.querySelector('base')?.getAttribute('href');
  if (href == null || href.trim().isEmpty) return null;
  return href;
}
