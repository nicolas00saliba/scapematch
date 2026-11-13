import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_documents_repository.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_withdrawal_repository.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/venue_withdrawals_panel.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  test('status aprovado libera e pendente bloqueia o saque', () {
    final pending = VenueDocumentsView.fromJson({
      'known': true,
      'approved': false,
      'documentation': 'PENDING',
      'general': 'PENDING',
      'onboarding_url': 'https://cadastro.io/casa',
      'documents': [
        {
          'id': 'doc_sem_link_1',
          'status': 'NOT_SENT',
          'type': 'IDENTIFICATION',
          'title': 'RG',
          'hosted': true,
          'upload': false,
          'onboarding_url': 'https://cadastro.io/casa',
        },
      ],
    });
    expect(pending.blocksWithdraw, isTrue);
    expect(pending.onboardingUrl, 'https://cadastro.io/casa');
    expect(
      VenueDocumentsView.fromJson({
        'known': true,
        'approved': true,
        'documentation': 'APPROVED',
        'general': 'APPROVED',
        'documents': [],
      }).blocksWithdraw,
      isFalse,
    );
    expect(
      venueDocumentFailureMessage('onboarding'),
      contains('site do Asaas'),
    );
  });

  testWidgets('link do Asaas aparece e o saque fica desligado', (tester) async {
    final docs = MemoryVenueDocumentsRepository(
      VenueDocumentsView.fromJson({
        'known': true,
        'approved': false,
        'documentation': 'PENDING',
        'general': 'PENDING',
        'onboarding_url': 'https://cadastro.io/casa',
        'documents': [
          {
            'id': 'doc_sem_link_1',
            'status': 'NOT_SENT',
            'type': 'IDENTIFICATION',
            'title': 'RG',
            'description': 'Envie pelo link',
            'hosted': true,
            'upload': false,
            'onboarding_url': 'https://cadastro.io/casa',
          },
        ],
      }),
    );
    await _pump(tester, docs, const _EmptyPicker());

    expect(find.text(PartnerMessages.documentsTitle), findsOneWidget);
    expect(find.text(PartnerMessages.documentsHosted), findsOneWidget);
    expect(find.text(PartnerMessages.documentsBlockWithdraw), findsOneWidget);
    expect(find.textContaining('RG · Não enviado'), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueDocumentOnboarding), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueDocumentUpload), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(PartnerKeys.withdrawalSubmit))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(PartnerKeys.venueDocumentOnboarding));
    await tester.pumpAndSettle();
    expect(find.text(PartnerMessages.documentsOpen), findsOneWidget);
  });

  testWidgets('sem link o arquivo segue depois da confirmação', (tester) async {
    final docs = MemoryVenueDocumentsRepository(
      VenueDocumentsView.fromJson({
        'known': true,
        'approved': false,
        'documentation': 'PENDING',
        'general': 'PENDING',
        'documents': [
          {
            'id': 'doc_sem_link_1',
            'status': 'NOT_SENT',
            'type': 'IDENTIFICATION',
            'title': 'RG',
            'hosted': false,
            'upload': true,
          },
        ],
      }),
    );
    await _pump(
      tester,
      docs,
      _FixedPicker(VenueDocumentFile(bytes: Uint8List.fromList(_png))),
    );

    expect(find.text(PartnerMessages.documentsUpload), findsOneWidget);
    expect(find.byKey(PartnerKeys.venueDocumentOnboarding), findsNothing);
    await tester.tap(find.byKey(PartnerKeys.venueDocumentUpload));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PartnerKeys.withdrawalPassword), 'senha');
    await tester.tap(find.byKey(PartnerKeys.withdrawalConfirm));
    await tester.pumpAndSettle();

    expect(docs.uploads, ['doc_sem_link_1']);
    expect(find.textContaining('RG · Em análise'), findsNothing);
    expect(find.textContaining('RG · Pendente'), findsOneWidget);
  });

  testWidgets('conta aprovada deixa o saque ligado', (tester) async {
    final docs = MemoryVenueDocumentsRepository(
      VenueDocumentsView.fromJson({
        'known': true,
        'approved': true,
        'documentation': 'APPROVED',
        'general': 'APPROVED',
        'documents': [
          {
            'id': 'doc_sem_link_1',
            'status': 'APPROVED',
            'type': 'IDENTIFICATION',
            'title': 'RG',
            'hosted': false,
            'upload': false,
          },
        ],
      }),
    );
    await _pump(tester, docs, const _EmptyPicker());

    expect(find.text(PartnerMessages.documentsApproved), findsOneWidget);
    expect(find.text(PartnerMessages.documentsBlockWithdraw), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(PartnerKeys.withdrawalSubmit))
          .onPressed,
      isNotNull,
    );
  });
}

const _png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

class _EmptyPicker implements VenueDocumentPicker {
  const _EmptyPicker();

  @override
  Future<VenueDocumentFile?> pick() async => null;
}

class _FixedPicker implements VenueDocumentPicker {
  _FixedPicker(this.file);

  final VenueDocumentFile file;

  @override
  Future<VenueDocumentFile?> pick() async => file;
}

Future<void> _pump(
  WidgetTester tester,
  VenueDocumentsRepository docs,
  VenueDocumentPicker picker,
) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        venueWithdrawalRepositoryProvider.overrideWithValue(
          MemoryVenueWithdrawalRepository(VenuePayoutSnapshot.sample()),
        ),
        venueDocumentsRepositoryProvider.overrideWithValue(docs),
        venueDocumentPickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        theme: buildAppTheme(Brightness.light),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ListView(
            children: const [
              VenueWithdrawalsPanel(venueId: 'casa', email: 'casa@example.com'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
