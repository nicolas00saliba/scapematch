import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch_admin/admin_ranking.dart';
import 'package:scapematch_admin/admin_theme.dart';

void main() {
  testWidgets('a flag nasce desligada e o admin remove uma linha', (
    tester,
  ) async {
    final api = MemoryRankingAdminApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rankingAdminProvider.overrideWithValue(api)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: adminTheme(),
          home: const Scaffold(body: RankingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final flag = tester.widget<Switch>(find.byType(Switch));
    expect(flag.value, isFalse);
    expect(find.textContaining('Desligada'), findsOneWidget);
    expect(find.text('Os Ninjas · Ninja Escape · O Cofre'), findsOneWidget);
    expect(find.textContaining('38:12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-ranking-flag')));
    await tester.tap(find.byKey(const Key('admin-ranking-salvar')));
    await tester.pumpAndSettle();
    expect((await api.settings()).enabled, isTrue);
    expect(find.textContaining('Ligada'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-ranking-remover-tempo-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('removido'), findsOneWidget);
    expect(find.byKey(const Key('admin-ranking-remover-tempo-1')), findsNothing);
  });
}
