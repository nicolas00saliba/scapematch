import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('o admin aprova a reivindicação pendente', (tester) async {
    final api = MemoryAdminApi();
    await _pump(tester, api);
    expect(find.text('Ninja Escape'), findsOneWidget);
    expect(find.text('Ninja Escape Room'), findsOneWidget);
    expect(find.byKey(const Key('admin-reivindicacoes')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('admin-aprovar-claim-claim-ninja')),
    );
    await tester.tap(find.byKey(const Key('admin-aprovar-claim-claim-ninja')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.claims, isEmpty);
    expect(find.text('Ninja Escape Room'), findsNothing);
    expect(find.text('Ninja Escape'), findsOneWidget);
  });

  testWidgets('o admin recusa a reivindicação pendente', (tester) async {
    final api = MemoryAdminApi();
    await _pump(tester, api);
    await tester.ensureVisible(
      find.byKey(const Key('admin-recusar-claim-claim-ninja')),
    );
    await tester.tap(find.byKey(const Key('admin-recusar-claim-claim-ninja')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.claims, isEmpty);
    expect(
      api.audits.any(
        (row) => row.action == 'review_venue_claim' && row.after == 'rejected',
      ),
      isTrue,
    );
  });

  testWidgets('gravar contato oficial exige e-mail ou telefone', (
    tester,
  ) async {
    final api = MemoryAdminApi();
    await _pump(tester, api);
    await tester.tap(find.text('Ninja Escape'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.ensureVisible(find.byKey(const Key('admin-gravar-contato')));
    await tester.tap(find.byKey(const Key('admin-gravar-contato')));
    await tester.pump();
    expect(find.text('Informe o e-mail ou o telefone oficial.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('admin-contato-email')),
      'oficial@ninja.example',
    );
    await tester.tap(find.byKey(const Key('admin-gravar-contato')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Contato oficial gravado.'), findsOneWidget);
    expect(
      api.audits.any((row) => row.action == 'set_venue_contacts'),
      isTrue,
    );
  });
}

Future<void> _pump(WidgetTester tester, AdminApi api) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        adminApiProvider.overrideWithValue(api),
        adminSessionProvider.overrideWith(_ReadySession.new),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _ReadySession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(
      phase: AdminPhase.ready,
      name: 'Nícolas',
      email: 'admin@scapematch.exemplo',
    );
  }
}
