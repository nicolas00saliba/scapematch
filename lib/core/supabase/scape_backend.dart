import 'package:scapematch/core/mode/app_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// URL e chave publicável do projeto EscapeMatch.
///
/// A chave publicável vai no app. A chave secreta e a service role não.
const scapeSupabaseUrl = 'https://eujlhicairvksvmssruz.supabase.co';
const scapeSupabasePublishableKey =
    'sb_publishable_V9VlCtbVt8ogFGZkhcYGOg_GMAnG3Ie';

/// Fica falso nos testes, que continuam no banco em memória.
/// O `main` de cada app liga isto depois de inicializar o cliente.
bool scapeUsesLiveBackend = false;

SupabaseClient get scapeSupabase => Supabase.instance.client;

Future<void> startScapeSupabase() async {
  await Supabase.initialize(
    url: scapeSupabaseUrl,
    publishableKey: scapeSupabasePublishableKey,
  );
  scapeUsesLiveBackend = true;
}

/// Liga o backend deste binário. O release de demonstração não chega
/// no [startScapeSupabase]: o `if` é constante e o compilador corta a chamada.
Future<void> bootScapeBackend() async {
  if (kAppMode == AppMode.demo) {
    scapeUsesLiveBackend = false;
    return;
  }
  await startScapeSupabase();
}

/// Mesma escolha, com o modo e o arranque injetados. Os testes usam isto
/// para provar que a demonstração não chama o Supabase.
Future<void> applyBackendPlan(
  AppMode mode, {
  Future<void> Function()? startSupabase,
}) async {
  if (mode == AppMode.demo) {
    scapeUsesLiveBackend = false;
    return;
  }
  await (startSupabase ?? startScapeSupabase)();
}
