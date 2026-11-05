import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_signup_gateway.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_signup_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

void main() {
  testWidgets('partner signup shows the same success screen', (tester) async {
    final gateway = _Gateway();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutomaticRetry,
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PartnerSignupScreen(
                          gateway: gateway,
                          resendCooldown: const Duration(seconds: 30),
                        ),
                      ),
                    );
                  },
                  child: const Text('abrir cadastro'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir cadastro'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(PartnerKeys.partnerEmail), 'Casa Lume');
    await tester.enterText(find.byType(TextField).at(1), 'casa@exemplo.com');
    await tester.enterText(
      find.byKey(PartnerKeys.partnerSignupPassword),
      'Casa1234',
    );
    await tester.ensureVisible(find.byKey(PartnerKeys.partnerSignupTerms));
    await tester.tap(find.byKey(PartnerKeys.partnerSignupTerms));
    await tester.pump();
    await tester.tap(find.byKey(PartnerKeys.partnerSubmit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(gateway.created, 1);
    expect(find.byKey(AppKeys.signupSuccess), findsOneWidget);
    expect(
      find.textContaining(
        'Confirme o e-mail que enviamos para casa@exemplo.com e depois entre.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(AppKeys.signupResendEmail))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(AppKeys.signupGoToLogin));
    await tester.pumpAndSettle();
    expect(find.text('abrir cadastro'), findsOneWidget);
    expect(find.byType(PartnerSignupScreen), findsNothing);
  });
}

class _Gateway extends PartnerSignupGateway {
  var created = 0;

  @override
  Future<({PartnerSignupStatus? status, String? error})> create({
    required String name,
    required String email,
    required String password,
  }) async {
    created += 1;
    expect(name, 'Casa Lume');
    expect(email, 'casa@exemplo.com');
    return (status: PartnerSignupStatus.confirmEmail, error: null);
  }

  @override
  Future<String?> resend(String email) async => null;
}
