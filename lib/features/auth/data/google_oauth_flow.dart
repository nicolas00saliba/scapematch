import 'package:flutter/foundation.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/web/document_base.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Abre o Google. Na web a página sai e volta na raiz do app. No celular
/// o retorno é [googleNativeRedirect].
Future<String?> startGoogleOAuth(GoTrueClient auth) async {
  if (!scapeUsesLiveBackend) return googleExampleMessage;
  final redirectTo = kIsWeb
      ? googleWebRedirect(Uri.base, documentBaseHref())
      : googleNativeRedirect;
  try {
    final launched = await auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      queryParams: const {'prompt': 'select_account'},
    );
    return googleLaunchFailure(launched: launched, web: kIsWeb);
  } on Object catch (error) {
    return googleAuthErrorMessage(error);
  }
}
