import 'package:flutter/material.dart';

import '../../../../test/support/folga_golden.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/retry.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_app.dart';
import 'package:scapematch_admin/admin_session.dart';

void main() {
  setUp(() {
    goldenFileComparator = FolgaGolden(
      Uri.parse('test/quality/telas_golden_test.dart'),
    );
  });

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    final nome = size.width.round().toString();

    testWidgets('login do admin em $nome', (tester) async {
      await _pump(tester, size);
      await expectLater(
        find.byKey(const Key('admin-login')),
        matchesGoldenFile('goldens/admin_login_$nome.png'),
      );
    });
  }

  testWidgets('botão Entrar do admin', (tester) async {
    await _pump(tester, const Size(390, 844));
    await expectLater(
      find.byKey(const Key('admin-enter')),
      matchesGoldenFile('goldens/admin_entrar.png'),
    );
  });

  testWidgets('login do admin segue contraste e toque', (tester) async {
    await _pump(tester, const Size(390, 844));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        adminApiProvider.overrideWithValue(MemoryAdminApi()),
        adminSessionProvider.overrideWith(SignedOutAdminSession.new),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

class SignedOutAdminSession extends AdminSessionController {
  @override
  AdminSession build() {
    return const AdminSession(phase: AdminPhase.signedOut);
  }
}
