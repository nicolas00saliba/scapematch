import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  testWidgets('conciliação mostra a divergência do último run', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MemoryAdminApi()
      ..divergenceFixture = DivergenceBoard(
        startedAt: DateTime.utc(2026, 11, 13, 11, 30),
        paymentCount: 2,
        transferCount: 1,
        divergenceCount: 1,
        truncated: false,
        rows: [
          DivergenceRow(
            kind: 'charge_status',
            providerRef: 'pay_conciliacao',
            localId: 'local-1',
            expected: 'paid',
            actual: 'pending',
            when: DateTime.utc(2026, 11, 13, 11, 30),
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
    await tester.tap(find.text('Conciliação'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('admin-conciliacao')), findsOneWidget);
    expect(find.text('Status da cobrança diferente'), findsOneWidget);
    expect(find.textContaining('pay_conciliacao'), findsOneWidget);
    expect(find.textContaining('paid → pending'), findsOneWidget);
    expect(find.textContaining('2 cobranças'), findsOneWidget);
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
