import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/features/auth/data/google_oauth.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_google_account.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_legal.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

import 'support/pump_parceiro.dart';

void main() {
  testWidgets('login da casa mostra Continuar com Google', (tester) async {
    await pumpParceiro(tester, size: const Size(390, 1400));
    final button = find.byKey(PartnerKeys.googleSignIn);
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(googleExampleMessage), findsOneWidget);
  });

  testWidgets('casa do Google não segue sem o aceite', (tester) async {
    var submitted = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          home: PartnerGoogleFinishScreen(
            initialName: 'Casa Ninja',
            onSubmit: ({required name, required acceptedTerms}) async {
              submitted += 1;
              if (!acceptedTerms) return PartnerLegal.termsRequired;
              if (name.trim().length < 2) return 'Informe o nome.';
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Casa Ninja'), findsOneWidget);
    await tester.tap(find.byKey(PartnerKeys.partnerGoogleSubmit));
    await tester.pumpAndSettle();
    expect(find.text(PartnerLegal.termsRequired), findsOneWidget);
    expect(submitted, 1);

    await tester.tap(find.byKey(PartnerKeys.partnerGoogleTerms));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartnerKeys.partnerGoogleSubmit));
    await tester.pumpAndSettle();
    expect(find.text(PartnerLegal.termsRequired), findsNothing);
    expect(submitted, 2);
    expect(find.textContaining(legalDocumentVersion), findsOneWidget);
  });
}
