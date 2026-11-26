import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_signup_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_pagbank_signup_card.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const _account = 'ACCO_F74B8490-77C0-4F9C-88EA-E98735B413CA';
const _other = 'ACCO_11111111-2222-3333-4444-555555559999';

void main() {
  test('o servidor da casa recusa uma segunda conta e aceita a mesma', () {
    final server = MemoryPagbankServer()..link(accountId: _account);
    expect(
      () => server.link(accountId: _other),
      throwsA(
        isA<PagbankSignupException>().having(
          (e) => e.code,
          'code',
          'pagbank_account_exists',
        ),
      ),
    );
    expect(server.account.accountLast4, '13CA');
    server.link(accountId: _account);
    expect(server.account.accountLast4, '13CA');
  });

  test('o JSON do servidor vira conta mascarada e sem conta vira nenhuma', () {
    final view = PagbankAccountView.fromJson({
      'connected': true,
      'house_name': 'Ninja Escape Room',
      'bank': 'PagBank',
      'account_last4': '13CA',
      'document_kind': 'cnpj',
      'document_masked': '**.***.***/****-95',
      'can_disconnect': false,
    });
    expect(view.connected, isTrue);
    expect(view.documentLabel, 'CNPJ da casa');
    expect(view.houseName, 'Ninja Escape Room');
    expect(view.documentMasked, '**.***.***/****-95');
    expect(view.canDisconnect, isFalse);
    expect(PagbankAccountView.fromJson({'connected': false}).connected, isFalse);
    expect(PagbankAccountView.fromJson(null).connected, isFalse);
  });

  testWidgets(
    'dois logins da mesma casa veem a mesma conta e nenhum conecta outra',
    (tester) async {
      // Um servidor, dois aparelhos: cada um com o seu repositório e sem
      // nenhum estado local compartilhado entre eles.
      final server = MemoryPagbankServer()..link(accountId: _account);
      final phone = MemoryPagbankSignupRepository(server: server);
      final laptop = MemoryPagbankSignupRepository(server: server);

      await _pump(tester, phone);
      expect(find.byKey(PartnerKeys.pagbankAccountCard), findsOneWidget);
      expect(find.text('Casa de Teste'), findsOneWidget);
      expect(find.text('PagBank'), findsOneWidget);
      expect(find.text('13CA'), findsOneWidget);
      expect(find.text('**.***.***/****-81'), findsOneWidget);
      expect(find.byKey(PartnerKeys.pagbankHaveAccount), findsNothing);
      expect(find.byKey(PartnerKeys.pagbankSignupConnect), findsNothing);

      // O segundo login abre sem o aparelho saber de nada: mesma conta.
      // O pai ainda diz que a casa não recebe (estado velho): o servidor vale.
      await _pump(tester, laptop, receivesPayments: false);
      expect(find.byKey(PartnerKeys.pagbankAccountCard), findsOneWidget);
      expect(find.text('13CA'), findsOneWidget);
      expect(find.byKey(PartnerKeys.pagbankHaveAccount), findsNothing);
      expect(find.byKey(PartnerKeys.pagbankNoAccount), findsNothing);
      expect(find.byKey(PartnerKeys.pagbankSignupConnect), findsNothing);

      // Mesmo pela API, o servidor recusa conectar outra conta.
      await expectLater(
        laptop.connect('casa'),
        throwsA(isA<PagbankSignupException>()),
      );
      expect(() => server.link(accountId: _other), throwsA(anything));
      expect((await phone.account('casa')).accountLast4, '13CA');
      expect((await laptop.account('casa')).accountLast4, '13CA');
    },
  );

  testWidgets('trocar de conta pede confirmação e só depois desconecta', (
    tester,
  ) async {
    final server = MemoryPagbankServer()..link(accountId: _account);
    final repo = MemoryPagbankSignupRepository(server: server);
    await _pump(tester, repo);

    await tester.tap(find.byKey(PartnerKeys.pagbankAccountSwap));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.pagbankSwapTitle), findsOneWidget);
    expect(
      find.textContaining('conta final 13CA'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(PartnerKeys.pagbankAccountSwapCancel));
    await tester.pumpAndSettle();
    expect(server.account.connected, isTrue);
    expect(find.byKey(PartnerKeys.pagbankAccountCard), findsOneWidget);

    await tester.tap(find.byKey(PartnerKeys.pagbankAccountSwap));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.pagbankAccountSwapConfirm));
    await tester.pumpAndSettle();
    expect(server.account.connected, isFalse);
    expect(find.byKey(PartnerKeys.pagbankAccountCard), findsNothing);
    expect(find.byKey(PartnerKeys.pagbankHaveAccount), findsOneWidget);

    // Desconectada, conecta outra. Um segundo login já vê só a nova.
    server.link(accountId: _other);
    final second = MemoryPagbankSignupRepository(server: server);
    expect((await second.account('casa')).accountLast4, '9999');
  });

  testWidgets('dinheiro a caminho trava a troca e explica', (tester) async {
    final server = MemoryPagbankServer()
      ..moneyInFlight = true
      ..link(accountId: _account);
    final repo = MemoryPagbankSignupRepository(server: server);
    await _pump(tester, repo);

    final swap = tester.widget<OutlinedButton>(
      find.byKey(PartnerKeys.pagbankAccountSwap),
    );
    expect(swap.onPressed, isNull);
    expect(find.text(PartnerMessages.pagbankSwapBusy), findsOneWidget);
    await expectLater(
      repo.disconnect('casa'),
      throwsA(
        isA<PagbankSignupException>().having(
          (e) => e.code,
          'code',
          'pagbank_in_flight',
        ),
      ),
    );
    expect(server.account.connected, isTrue);
  });

  testWidgets('renovar a autorização não abre caminho para outra conta', (
    tester,
  ) async {
    final server = MemoryPagbankServer()..link(accountId: _account);
    final repo = MemoryPagbankSignupRepository(server: server);
    final opened = <Uri>[];
    await _pump(tester, repo, opened: opened);

    await tester.tap(find.byKey(PartnerKeys.pagbankAccountRenew));
    await tester.pump();
    expect(opened.single, repo.connectUri);
    expect(
      () => server.link(accountId: _other),
      throwsA(isA<PagbankSignupException>()),
    );
  });

  test('os códigos de conflito viram mensagem clara', () {
    expect(
      pagbankSignupMessage('pagbank_account_exists'),
      PartnerMessages.pagbankAccountExists,
    );
    expect(
      pagbankSignupMessage(
        signupErrorCode('{error: pagbank_account_exists, message: Esta casa}'),
      ),
      PartnerMessages.pagbankAccountExists,
    );
    expect(
      pagbankSignupMessage(signupErrorCode('pagbank_in_flight')),
      PartnerMessages.pagbankSwapBusy,
    );
  });

  test('não há rótulo de titular: o PagBank só devolve o id da conta', () {
    expect(PartnerMessages.pagbankAccountHouse, 'Casa');
    final old = PagbankAccountView.fromJson({
      'connected': true,
      'holder': 'Nome Qualquer',
      'account_last4': '13CA',
    });
    expect(old.houseName, '');
    expect(
      PagbankAccountView.fromJson({
        'connected': true,
        'document_kind': 'cpf',
      }).documentLabel,
      'CPF da casa',
    );
  });

  test('conta de outra casa e conta que mudou têm mensagem própria', () {
    expect(
      signupErrorCode('pagbank_account_in_use'),
      'pagbank_account_in_use',
    );
    expect(
      signupErrorCode('pagbank_account_changed'),
      'pagbank_account_changed',
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  MemoryPagbankSignupRepository repo, {
  bool receivesPayments = true,
  List<Uri>? opened,
}) async {
  tester.view.physicalSize = const Size(500, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [pagbankSignupRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [
              VenuePagbankSignupCard(
                venueId: 'casa',
                onOpen: opened?.add,
                receivesPayments: receivesPayments,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
