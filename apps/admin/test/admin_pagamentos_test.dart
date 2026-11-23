import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  testWidgets('pagamentos confirma a chave e mostra prontidão e listas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MemoryAdminApi()
      ..payoutsEnabled = false
      ..paymentsFixture = PaymentsBoard(
        asaasApiKey: true,
        asaasBaseUrlProduction: true,
        asaasWebhookToken: false,
        asaasWebhookEmail: null,
        venueWithdrawalsSecret: true,
        vaultUrl: true,
        vaultSecret: false,
        payoutsEnabled: false,
        cronLastFailed: true,
        cronFailureCode: 'config_ausente',
        charges: [
          PaymentLine(
            id: 'cobranca-1',
            title: 'Casa do Painel · PIX',
            detail: 'paid · R\$ 80,00',
            when: DateTime.utc(2026, 11, 12, 18),
          ),
        ],
        refunds: const [],
        withdrawals: [
          PaymentLine(
            id: 'saque-1',
            title: 'Casa do Painel',
            detail: 'done · automatic · R\$ 60,00',
            when: DateTime.utc(2026, 11, 13, 11),
          ),
        ],
        webhookErrors: [
          WebhookErrorLine(
            id: 'erro-1',
            source: 'asaas-webhook',
            code: 'internal_error',
            providerRef: 'pay_painel',
            when: DateTime.utc(2026, 11, 13, 12),
          ),
        ],
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminApiProvider.overrideWithValue(api),
          adminSessionProvider.overrideWith(ReadyAdminSession.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Pagamentos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-pagamentos')), findsOneWidget);
    expect(find.text('Chave da API do Asaas: sim'), findsOneWidget);
    expect(find.text('Token do webhook: não'), findsOneWidget);
    expect(find.text('E-mail do webhook: sem leitura'), findsOneWidget);
    expect(find.text('Vault do segredo de saques: não'), findsOneWidget);
    expect(
      find.text('Última execução do cron: falhou · config_ausente'),
      findsOneWidget,
    );
    expect(find.text('Casa do Painel · PIX'), findsOneWidget);
    expect(find.text('Nenhum estorno recente.'), findsOneWidget);
    expect(find.text('asaas-webhook · internal_error'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-payouts-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Ligar saques automáticos'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.payoutsEnabled, isFalse);
    expect(
      api.audits.where((row) => row.action == 'set_venue_payouts_enabled'),
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('admin-payouts-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('admin-payouts-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.payoutsEnabled, isTrue);
    expect(find.text('Ligados'), findsOneWidget);
    expect(
      api.audits.where((row) => row.action == 'set_venue_payouts_enabled'),
      isNotEmpty,
    );
  });
}

class ReadyAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
}
