import 'package:supabase_flutter/supabase_flutter.dart';

/// URL e chave publicável do projeto ScapeMatch.
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
