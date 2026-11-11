import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fator TOTP unverified é removido antes de cadastrar de novo', () async {
    final gate = _Gate();
    gate.factors = _factors(
      all: [
        _totp('factor-stale', FactorStatus.unverified),
        _phone('factor-sms'),
      ],
    );

    final session = await gate.run();

    expect(gate.calls, ['list', 'unenroll:factor-stale', 'enroll']);
    expect(session.phase, AdminPhase.enroll);
    expect(session.factorId, 'factor-new');
    expect(session.secret, 'NEWSECRET234567');
    expect(session.qrCode, contains('<svg'));
    expect(session.error, isNull);
  });

  test('vários TOTP unverified saem antes do enroll', () async {
    final gate = _Gate();
    gate.factors = _factors(
      all: [
        _totp('factor-a', FactorStatus.unverified),
        _totp('factor-b', FactorStatus.unverified),
      ],
    );

    final session = await gate.run();

    expect(gate.calls, [
      'list',
      'unenroll:factor-a',
      'unenroll:factor-b',
      'enroll',
    ]);
    expect(session.phase, AdminPhase.enroll);
  });

  test('não cadastra de novo se o unenroll do unverified falha', () async {
    final gate = _Gate();
    gate.factors = _factors(
      all: [_totp('factor-stale', FactorStatus.unverified)],
    );
    gate.onUnenroll = (_) async {
      throw const AuthException(
        'otpauth://totp/EscapeMatch?secret=JBSWY3DPEHPK3PXP',
        statusCode: '500',
        code: 'unexpected_failure',
      );
    };

    await expectLater(gate.run(), throwsA(isA<AuthException>()));
    expect(gate.calls, ['list', 'unenroll:factor-stale']);
  });

  test('fator verified vai para o verify e não é removido', () async {
    final gate = _Gate();
    gate.factors = _factors(
      all: [
        _totp('factor-ok', FactorStatus.verified),
        _totp('factor-stale', FactorStatus.unverified),
      ],
      totp: [_totp('factor-ok', FactorStatus.verified)],
    );

    final session = await gate.run();

    expect(gate.calls, ['list', 'challenge:factor-ok']);
    expect(session.phase, AdminPhase.verify);
    expect(session.factorId, 'factor-ok');
    expect(session.challengeId, 'challenge-1');
    expect(session.secret, isNull);
  });

  test('fator verified só em factors.all também abre o verify', () async {
    final gate = _Gate();
    gate.factors = _factors(all: [_totp('factor-ok', FactorStatus.verified)]);

    final session = await gate.run();

    expect(gate.calls, ['list', 'challenge:factor-ok']);
    expect(session.phase, AdminPhase.verify);
    expect(session.factorId, 'factor-ok');
  });

  test('código inválido mantém a tela e troca o desafio', () {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    const secret = 'JBSWY3DPEHPK3PXP';
    final next = sessionAfterFailedMfaCode(
      current: const AdminSession(
        phase: AdminPhase.verify,
        email: 'admin@escapematch.com.br',
        factorId: 'factor-ok',
        challengeId: 'challenge-1',
      ),
      error: AuthException(
        'otpauth://totp/EscapeMatch?secret=$secret',
        statusCode: '403',
        code: 'mfa_verification_failed',
      ),
      replacementChallengeId: 'challenge-2',
    );

    expect(next.phase, AdminPhase.verify);
    expect(next.factorId, 'factor-ok');
    expect(next.challengeId, 'challenge-2');
    expect(next.busy, isFalse);
    expect(
      next.error,
      'Código inválido. Confira se o relógio do celular está em hora automática e use o código da conta EscapeMatch Admin.',
    );
    expect(logs, ['admin mfa: mfa_verification_failed']);
    expect(logs.single.contains(secret), isFalse);
  });

  test('código inválido no cadastro conserva o QR e o segredo', () {
    final next = sessionAfterFailedMfaCode(
      current: const AdminSession(
        phase: AdminPhase.enroll,
        email: 'admin@escapematch.com.br',
        factorId: 'factor-new',
        qrCode: '<svg></svg>',
        secret: 'NEWSECRET234567',
      ),
      error: const AuthException('invalid', code: 'mfa_verification_failed'),
    );

    expect(next.phase, AdminPhase.enroll);
    expect(next.qrCode, '<svg></svg>');
    expect(next.secret, 'NEWSECRET234567');
    expect(next.challengeId, isNull);
    expect(next.error, adminMfaVerificationFailed);
  });

  test(
    'mfa_factor_name_conflict explica o nome repetido sem vazar segredo',
    () {
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previous);

      const secret = 'NEWSECRET234567';
      final session = sessionAfterFailedMfaGate(
        email: 'admin@escapematch.com.br',
        error: AuthException(
          'friendly name already exists secret=$secret',
          statusCode: '422',
          code: 'mfa_factor_name_conflict',
        ),
      );

      expect(session.phase, AdminPhase.signedOut);
      expect(session.email, 'admin@escapematch.com.br');
      expect(
        session.error,
        'Já existe um autenticador com o nome EscapeMatch Admin. Saia e entre de novo; se a conta já estiver no app, use o código dela.',
      );
      expect(logs, ['admin mfa: mfa_factor_name_conflict']);
      expect(logs.single.contains(secret), isFalse);
    },
  );

  test('erro sem código cai na mensagem genérica e não loga o texto', () {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);

    final message = messageForAdminMfa(
      Exception('secret=JBSWY3DPEHPK3PXP'),
      verifyingCode: false,
    );

    expect(message, 'Não foi possível confirmar o autenticador.');
    expect(logs, isEmpty);
  });

  testWidgets(
    'código recusado no verify permite outra tentativa na mesma tela',
    (tester) async {
      final session = _RetrySession();
      await tester.pumpWidget(
        ProviderScope(
          retry: noAutomaticRetry,
          overrides: [
            adminApiProvider.overrideWithValue(MemoryAdminApi()),
            adminSessionProvider.overrideWith(() => session),
          ],
          child: const AdminApp(),
        ),
      );
      await tester.pump();

      expect(find.text('Código do autenticador'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('admin-mfa-code')), '111111');
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('admin-login')), findsNothing);
      expect(find.byKey(const Key('admin-mfa')), findsOneWidget);
      expect(
        find.text(
          'Código inválido. Confira se o relógio do celular está em hora automática e use o código da conta EscapeMatch Admin.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-mfa-confirm')), findsOneWidget);
      expect(session.challengeId, 'challenge-2');

      await tester.enterText(find.byKey(const Key('admin-mfa-code')), '222222');
      await tester.pump();

      expect(session.calls, 2);
      expect(session.lastCode, '222222');
      expect(session.challengeId, 'challenge-3');
      expect(find.byKey(const Key('admin-mfa')), findsOneWidget);
      expect(find.byKey(const Key('admin-login')), findsNothing);
    },
  );
}

class _RetrySession extends AdminSessionController {
  var calls = 0;
  String? lastCode;
  String? challengeId = 'challenge-1';

  @override
  AdminSession build() {
    return AdminSession(
      phase: AdminPhase.verify,
      email: 'admin@scapematch.exemplo',
      factorId: 'factor-ok',
      challengeId: challengeId,
    );
  }

  @override
  Future<void> confirmCode(String raw) async {
    calls += 1;
    lastCode = raw.trim();
    if (lastCode!.length != 6) return;
    final replacement = 'challenge-${calls + 1}';
    challengeId = replacement;
    state = sessionAfterFailedMfaCode(
      current: state,
      error: const AuthException(
        'otpauth://totp/EscapeMatch?secret=JBSWY3DPEHPK3PXP',
        code: 'mfa_verification_failed',
      ),
      replacementChallengeId: replacement,
    );
  }
}

class _Gate {
  final calls = <String>[];
  late AuthMFAListFactorsResponse factors;
  Future<void> Function(String id)? onUnenroll;

  Future<AdminSession> run({String? email = 'admin@escapematch.com.br'}) {
    return resolveAdminMfaGate(
      email: email,
      listFactors: () async {
        calls.add('list');
        return factors;
      },
      unenroll: (id) async {
        calls.add('unenroll:$id');
        await onUnenroll?.call(id);
      },
      enroll: () async {
        calls.add('enroll');
        return const AuthMFAEnrollResponse(
          id: 'factor-new',
          type: FactorType.totp,
          totp: TOTPEnrollment(
            qrCode: 'data:image/svg+xml;utf-8,<svg></svg>',
            secret: 'NEWSECRET234567',
            uri: 'otpauth://totp/EscapeMatch%20Admin?secret=NEWSECRET234567',
          ),
        );
      },
      challenge: (id) async {
        calls.add('challenge:$id');
        return AuthMFAChallengeResponse(
          id: 'challenge-1',
          expiresAt: DateTime.utc(2026, 1, 1),
        );
      },
    );
  }
}

final _stamp = DateTime.utc(2026, 1, 1);

Factor _totp(String id, FactorStatus status) {
  return Factor(
    id: id,
    friendlyName: adminTotpLabel,
    factorType: FactorType.totp,
    status: status,
    createdAt: _stamp,
    updatedAt: _stamp,
  );
}

Factor _phone(String id) {
  return Factor(
    id: id,
    friendlyName: 'sms',
    factorType: FactorType.phone,
    status: FactorStatus.unverified,
    createdAt: _stamp,
    updatedAt: _stamp,
  );
}

AuthMFAListFactorsResponse _factors({
  required List<Factor> all,
  List<Factor> totp = const [],
  List<Factor> phone = const [],
}) {
  return AuthMFAListFactorsResponse(all: all, totp: totp, phone: phone);
}
