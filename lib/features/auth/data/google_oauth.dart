import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/auth/data/auth_return_url.dart';

/// Esquema do app nativo. O mesmo valor vai no AndroidManifest e no Info.plist.
const googleNativeRedirect = 'dev.scapematch.scapematch://login-callback';

const googleCancelledMessage = 'Você cancelou a entrada com o Google.';

const googlePopupBlockedMessage =
    'O navegador bloqueou a janela do Google. Permita pop-ups deste site e tente de novo.';

const googleProviderOffMessage =
    'A entrada com Google ainda não está disponível.';

const googleExampleMessage =
    'Neste exemplo a entrada com Google não conecta.';

const googleGenericMessage =
    'Não foi possível entrar com o Google. Tente de novo.';

/// O Supabase vincula o Google a uma conta que já tem o mesmo e-mail
/// confirmado. Não nasce outro `auth.users` e o gatilho `handle_new_user`
/// não insere de novo: o perfil continua o da chave primária `id`.
const googleAlreadyRegisteredMessage =
    'Esse e-mail já tem conta. Entre com a senha.';

/// Redirect do OAuth na web. Cai na raiz do app, dentro do escopo do PWA.
/// O `next` da tela de login volta junto, se for um caminho interno.
String? googleWebRedirect(Uri page, String? baseHref) {
  if (baseHref == null || baseHref.isEmpty) return null;
  final root = authReturnUrl(page, baseHref);
  if (root == null) return null;
  final next = page.queryParameters['next'];
  if (next == null || next.isEmpty) return root;
  if (next.contains('://') || next.startsWith('//') || !next.startsWith('/')) {
    return root;
  }
  return Uri.parse(root).replace(queryParameters: {'next': next}).toString();
}

/// Conta que só tem a identidade Google. E-mail e Google juntos são a
/// mesma pessoa: o cadastro obrigatório já foi feito na conta original.
bool googleOnlyProviders(Iterable<String> providers) {
  final list = providers.where((provider) => provider.isNotEmpty).toList();
  return list.isNotEmpty && list.every((provider) => provider == 'google');
}

/// Frase em pt-BR para o erro do provedor, do popup ou do cancelamento.
String googleAuthErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  if (_cancelled(raw)) return googleCancelledMessage;
  if (_popupBlocked(raw)) return googlePopupBlockedMessage;
  if (_providerOff(raw)) return googleProviderOffMessage;
  if (_alreadyRegistered(raw)) return googleAlreadyRegisteredMessage;
  return authErrorMessage(error, fallback: googleGenericMessage);
}

/// `false` do `signInWithOAuth`: no navegador a janela não abriu; no
/// celular a pessoa fechou o navegador antes de voltar.
String? googleLaunchFailure({required bool launched, required bool web}) {
  if (launched) return null;
  return web ? googlePopupBlockedMessage : googleCancelledMessage;
}

/// Erro que o Supabase devolve na URL de volta (`error` na query ou no fragmento).
String? googleAuthNoticeFromUri(Uri uri) {
  final params = <String, String>{...uri.queryParameters};
  if (uri.fragment.contains('=')) {
    params.addAll(Uri.splitQueryString(uri.fragment));
  }
  final code = params['error'] ?? params['error_code'];
  if (code == null || code.isEmpty) return null;
  final description = params['error_description'] ?? '';
  return googleAuthErrorMessage('$code $description');
}

/// Aviso lido uma vez na tela de login, depois que o navegador volta do Google.
String? pendingGoogleAuthNotice;

String? takeGoogleAuthNotice() {
  final notice = pendingGoogleAuthNotice;
  pendingGoogleAuthNotice = null;
  return notice;
}

/// Nome que o Google manda em `full_name` ou `name`. O gatilho do perfil
/// só lê `display_name`, então a tela de completar cadastro mostra este.
String suggestedOAuthName(Map<String, dynamic>? meta, String? email) {
  for (final key in ['display_name', 'full_name', 'name']) {
    final value = meta?[key];
    if (value is String && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
    }
  }
  final local = (email ?? 'Jogador').split('@').first.trim();
  if (local.isEmpty) return 'Jogador';
  return local.length > 80 ? local.substring(0, 80) : local;
}

/// Resposta de `claim_referral_code`. `exists` é a segunda tentativa.
String? referralClaimMessage(String status) {
  return switch (status) {
    'ok' || 'exists' => null,
    'late' => 'O prazo para usar o código de indicação acabou.',
    'self' => 'Você não pode usar o próprio código.',
    _ => 'Código de indicação inválido. Confira ou deixe em branco.',
  };
}

bool _cancelled(String text) {
  return text.contains('access_denied') ||
      text.contains('user_cancelled') ||
      text.contains('user canceled') ||
      text.contains('user cancelled') ||
      text.contains('canceled') ||
      text.contains('cancelled') ||
      text.contains('popup_closed');
}

bool _popupBlocked(String text) {
  return text.contains('popup') &&
      (text.contains('block') || text.contains('closed') == false);
}

bool _providerOff(String text) {
  return text.contains('provider is not enabled') ||
      text.contains('unsupported provider') ||
      (text.contains('provider') && text.contains('disabled'));
}

bool _alreadyRegistered(String text) {
  return text.contains('already registered') ||
      text.contains('already been registered') ||
      text.contains('identity already') ||
      text.contains('email address is already');
}
