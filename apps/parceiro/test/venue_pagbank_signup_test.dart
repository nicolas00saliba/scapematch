import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/pagbank_signup_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/pagbank_signup.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_pagbank_signup_card.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('modo A não envia o CPF e abre a página oficial', (tester) async {
    final repo = MemoryPagbankSignupRepository();
    final opened = <Uri>[];
    await _pump(tester, repo, opened);
    await _fill(tester, cnpj: false);
    await tester.tap(find.byKey(PartnerKeys.pagbankSignupSubmit));
    await tester.pumpAndSettle();

    expect(find.byKey(PartnerKeys.pagbankSignupManual), findsOneWidget);
    expect(find.text(PartnerMessages.pagbankSignupStays), findsOneWidget);
    expect(repo.guides, ['casa:cpf:ENTERTAINMENT']);
    expect(repo.created, isEmpty);
    expect(find.text('52998224725'), findsNothing);

    await tester.tap(find.byKey(PartnerKeys.pagbankSignupOfficial));
    await tester.pump();
    expect(opened.single, Uri.parse(pagbankOfficialSignupUrl));
  });

  testWidgets('modo B mostra a ativação e manda o CNPJ só no create', (
    tester,
  ) async {
    final repo = MemoryPagbankSignupRepository(apiEnabled: true);
    await _pump(tester, repo, []);
    expect(find.text(PartnerMessages.pagbankSignupSubmitApi), findsOneWidget);
    await _fill(tester, cnpj: true);
    await tester.tap(find.byKey(PartnerKeys.pagbankSignupSubmit));
    await tester.pumpAndSettle();

    expect(find.byKey(PartnerKeys.pagbankSignupActivation), findsOneWidget);
    expect(find.text(PartnerMessages.pagbankSignupActivationDocs), findsOneWidget);
    expect(repo.guides, isEmpty);
    expect(repo.created, hasLength(1));
    expect(repo.created.single.documentNumber, '11222333000181');
    expect(repo.created.single.responsibleCpf, '52998224725');
    expect(find.text('11222333000181'), findsNothing);
  });

  testWidgets('conta já existente abre o Connect sem novo cadastro', (
    tester,
  ) async {
    final repo = MemoryPagbankSignupRepository(
      apiEnabled: true,
      signup: const PagbankSignupRow(
        mode: 'api',
        documentKind: 'cnpj',
        businessCategory: 'ENTERTAINMENT',
        accountStatus: 'exists',
      ),
    );
    final opened = <Uri>[];
    await _pump(tester, repo, opened);
    expect(find.text(PartnerMessages.pagbankSignupExists), findsOneWidget);
    expect(find.byKey(PartnerKeys.pagbankSignupSubmit), findsNothing);
    expect(repo.created, isEmpty);
    await tester.tap(find.byKey(PartnerKeys.pagbankSignupConnect));
    await tester.pump();
    expect(opened.single, repo.connectUri);
    expect(repo.created, isEmpty);
  });
}

Future<void> _pump(
  WidgetTester tester,
  MemoryPagbankSignupRepository repo,
  List<Uri> opened,
) async {
  tester.view.physicalSize = const Size(500, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pagbankSignupRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [
              VenuePagbankSignupCard(
                venueId: 'casa',
                onOpen: opened.add,
                today: () => DateTime.utc(2026, 11, 24),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {required bool cnpj}) async {
  if (cnpj) {
    await tester.tap(find.byKey(PartnerKeys.pagbankSignupCnpj));
    await tester.pumpAndSettle();
    await _type(tester, PartnerKeys.pagbankSignupDocument, '11222333000181');
    await _type(tester, PartnerKeys.pagbankSignupCompany, 'Casa Escape Ltda');
    await _type(
      tester,
      PartnerKeys.pagbankSignupResponsibleCpf,
      '52998224725',
    );
  } else {
    await _type(tester, PartnerKeys.pagbankSignupDocument, '52998224725');
    await _type(tester, PartnerKeys.pagbankSignupCompany, 'Casa Escape');
  }
  await _type(tester, PartnerKeys.pagbankSignupStreet, 'Rua das Salas');
  await _type(tester, PartnerKeys.pagbankSignupNumber, '10');
  await _type(tester, PartnerKeys.pagbankSignupLocality, 'Centro');
  await _type(tester, PartnerKeys.pagbankSignupCity, 'Curitiba');
  await _type(tester, PartnerKeys.pagbankSignupPostal, '80010010');
  await _type(tester, PartnerKeys.pagbankSignupRegion, 'PR');
  await _type(tester, PartnerKeys.pagbankSignupName, 'Ana Souza');
  await _type(tester, PartnerKeys.pagbankSignupBirth, '1991-10-10');
  await _type(tester, PartnerKeys.pagbankSignupPhone, '11987654321');
  await _type(tester, PartnerKeys.pagbankSignupEmail, 'ana@casa.example');
  final category = find.byKey(PartnerKeys.pagbankSignupCategory);
  await tester.ensureVisible(category);
  await tester.tap(category);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Serviços de recreação e lazer').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(PartnerKeys.pagbankSignupTerms));
  await tester.tap(find.byKey(PartnerKeys.pagbankSignupTerms));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(PartnerKeys.pagbankSignupSubmit));
}

Future<void> _type(WidgetTester tester, Key key, String value) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.enterText(find.byKey(key), value);
}
