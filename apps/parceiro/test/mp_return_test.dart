import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_parceiro/features/partner/data/mp_oauth_return.dart';
import 'package:scapematch_parceiro/features/partner/data/provider_payments.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/mp_return_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const _venue = '11111111-1111-4111-8111-111111111111';
const _state = 'v1.$_venue.1800000000000.nonce.assinatura';

void main() {
  test('a rota do build real é /mp-retorno no domínio do Parceiro', () {
    final uri = Uri.parse(mpOauthRedirectUri);
    expect(uri.toString(), 'https://parceiro.escapematch.com.br/mp-retorno');
    expect(isMpOauthReturnPath(uri), isTrue);
    expect(mpReturnHomePath(uri), '/');
    final doc = File(
      '../../docs/pagamentos-woovi-mercadopago.md',
    ).readAsStringSync();
    expect(doc, contains(mpOauthRedirectUri));
  });

  test('sem state no formato v1 a sessão informa a casa', () {
    final request = readMpOauthReturn(
      Uri.parse('https://parceiro.escapematch.com.br/mp-retorno?code=abc&state=legado'),
      sessionHouseId: _venue,
    );
    expect(request.outcome, MpOauthReturnOutcome.connect);
    expect(request.venueId, _venue);
  });

  testWidgets('code e state chamam o callback e mostram sucesso', (tester) async {
    final repo = _FakePayments();
    var left = false;
    await tester.pumpWidget(_app(
      repo: repo,
      uri: Uri.parse(
        'https://parceiro.escapematch.com.br/mp-retorno?code=codigo&state=$_state',
      ),
      onFinished: () => left = true,
    ));
    await tester.pumpAndSettle();

    expect(repo.calls, [
      {'venueId': _venue, 'code': 'codigo', 'state': _state},
    ]);
    expect(find.text(PartnerMessages.mpReturnSuccess), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.mpReturnBack));
    expect(left, isTrue);
  });

  testWidgets('state ausente não grava o token', (tester) async {
    final repo = _FakePayments();
    await tester.pumpWidget(_app(
      repo: repo,
      uri: Uri.parse(
        'https://parceiro.escapematch.com.br/mp-retorno?code=codigo',
      ),
    ));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.text(PartnerMessages.mpReturnMissing), findsOneWidget);
    expect(find.text(PartnerMessages.mpReturnSuccess), findsNothing);
  });

  testWidgets('access_denied não grava o token', (tester) async {
    final repo = _FakePayments();
    await tester.pumpWidget(_app(
      repo: repo,
      uri: Uri.parse(
        'https://parceiro.escapematch.com.br/mp-retorno?error=access_denied&state=$_state',
      ),
    ));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.text(PartnerMessages.mpReturnDenied), findsOneWidget);
  });

  testWidgets('a sessão logada não substitui a casa do state', (tester) async {
    final repo = _FakePayments();
    await tester.pumpWidget(_app(
      repo: repo,
      sessionHouseId: '22222222-2222-4222-8222-222222222222',
      uri: Uri.parse(
        'https://parceiro.escapematch.com.br/mp-retorno?code=codigo&state=$_state',
      ),
    ));
    await tester.pumpAndSettle();
    expect(repo.calls.single['venueId'], _venue);
  });
}

Widget _app({
  required _FakePayments repo,
  required Uri uri,
  String? sessionHouseId,
  VoidCallback? onFinished,
}) {
  return ProviderScope(
    overrides: [
      providerPaymentsRepositoryProvider.overrideWithValue(repo),
      if (sessionHouseId != null)
        partnerSessionProvider.overrideWith(
          () => _FixedSession(sessionHouseId),
        ),
    ],
    child: MaterialApp(
      home: MpReturnScreen(uri: uri, onFinished: onFinished),
    ),
  );
}

class _FixedSession extends PartnerSessionController {
  _FixedSession(this.houseId);

  final String houseId;

  @override
  PartnerAccount? build() {
    return PartnerAccount(
      email: 'casa@exemplo.com',
      houseId: houseId,
      houseName: 'Casa',
    );
  }
}

class _FakePayments implements ProviderPaymentsRepository {
  final calls = <Map<String, String>>[];

  @override
  Future<WooviHouseBalance> balance(String venueId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> completeMpOauth({
    required String venueId,
    required String code,
    required String state,
  }) async {
    calls.add({'venueId': venueId, 'code': code, 'state': state});
  }

  @override
  Future<Uri> mpConnectUrl(String venueId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> withdraw({
    required String venueId,
    required int amountCents,
  }) async {}
}
