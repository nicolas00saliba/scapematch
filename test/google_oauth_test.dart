import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:scapematch/features/auth/presentation/google_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('erros do Google ficam em português', () {
    expect(
      googleAuthErrorMessage(const AuthException('access_denied')),
      googleCancelledMessage,
    );
    expect(
      googleAuthErrorMessage(Exception('popup_blocked_by_browser')),
      googlePopupBlockedMessage,
    );
    expect(
      googleAuthErrorMessage(
        const AuthException('Unsupported provider: provider is not enabled'),
      ),
      googleProviderOffMessage,
    );
    expect(
      googleAuthErrorMessage(const AuthException('User already registered')),
      googleAlreadyRegisteredMessage,
    );
    expect(
      googleAuthErrorMessage(Exception('socket')),
      'Sem conexão. Tente de novo.',
    );
  });

  test('não abrir a janela explica o bloqueio ou o cancelamento', () {
    expect(
      googleLaunchFailure(launched: false, web: true),
      googlePopupBlockedMessage,
    );
    expect(
      googleLaunchFailure(launched: false, web: false),
      googleCancelledMessage,
    );
    expect(googleLaunchFailure(launched: true, web: true), isNull);
  });

  test('a volta do provedor lê o erro da query e do fragmento', () {
    expect(
      googleAuthNoticeFromUri(
        Uri.parse('https://app.escapematch.com.br/#error=access_denied'),
      ),
      googleCancelledMessage,
    );
    expect(
      googleAuthNoticeFromUri(
        Uri.parse(
          'https://parceiro.escapematch.com.br/?error=server_error&error_description=provider%20is%20not%20enabled',
        ),
      ),
      googleProviderOffMessage,
    );
    expect(
      googleAuthNoticeFromUri(
        Uri.parse('https://app.escapematch.com.br/?code=pkce'),
      ),
      isNull,
    );
  });

  test('o redirect da web fica na raiz e leva o next interno', () {
    expect(
      googleWebRedirect(
        Uri.parse('https://app.escapematch.com.br/login?next=%2Fgroups%2Fnew'),
        '/',
      ),
      'https://app.escapematch.com.br/?next=%2Fgroups%2Fnew',
    );
    expect(
      googleWebRedirect(
        Uri.parse('https://parceiro.escapematch.com.br/login'),
        '/',
      ),
      'https://parceiro.escapematch.com.br/',
    );
    expect(
      googleWebRedirect(
        Uri.parse('https://app.escapematch.com.br/login?next=https://evil.test'),
        '/',
      ),
      'https://app.escapematch.com.br/',
    );
    expect(googleNativeRedirect, 'dev.scapematch.scapematch://login-callback');
  });

  test('conta só do Google pede cadastro; e-mail vinculado não', () {
    expect(googleOnlyProviders(const ['google']), isTrue);
    expect(googleOnlyProviders(const ['email', 'google']), isFalse);
    expect(googleOnlyProviders(const []), isFalse);
    expect(
      suggestedOAuthName(
        const {'full_name': 'Ana Silva'},
        'ana@gmail.com',
      ),
      'Ana Silva',
    );
    expect(suggestedOAuthName(const {}, 'ana.silva@gmail.com'), 'ana.silva');
  });

  test('código de indicação repetido não trava o cadastro', () {
    expect(referralClaimMessage('ok'), isNull);
    expect(referralClaimMessage('exists'), isNull);
    expect(referralClaimMessage('invalid'), contains('inválido'));
    expect(referralClaimMessage('self'), contains('próprio'));
  });

  test('o G do Google cabe no quadrado de 48', () {
    const data =
        'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z';
    final bounds = pathFromSvg(data).getBounds();
    expect(bounds.width, greaterThan(10));
    expect(bounds.left, greaterThanOrEqualTo(-1));
    expect(bounds.right, lessThan(49));
    expect(bounds.bottom, lessThan(49));
  });
}
