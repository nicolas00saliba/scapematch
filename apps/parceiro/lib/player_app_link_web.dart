import 'package:scapematch_parceiro/player_app_url.dart';
import 'package:web/web.dart' as web;

void openPlayerApp() {
  web.window.location.href = playerAppUrl(web.window.location.href);
}
