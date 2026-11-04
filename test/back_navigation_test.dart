import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/catalog/presentation/room_detail_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/news/data/sample_news.dart';

import 'support/pump_app.dart';

void main() {
  testWidgets('a pushed room pops back to the same Home', (tester) async {
    await pumpScapeMatch(tester);
    await tester.enterText(find.byKey(AppKeys.groupSearch), 'Cofre');
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .push('/sala/${SampleIds.roomCwbCofre}');
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsOneWidget);
    expect(find.byKey(AppKeys.scapeBack), findsOneWidget);
    expect(find.text('O Cofre do Café'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.scapeBack));
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(AppKeys.scapeBack), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(AppKeys.groupSearch))
          .controller
          ?.text,
      'Cofre',
    );
  });

  testWidgets('a direct link on every stacked screen goes back home', (
    tester,
  ) async {
    await pumpScapeMatch(tester);

    const chave = 'room-curitiba-near-1';
    final routes = <(String, String)>[
      ('/salas/$chave', 'A Chave'),
      ('/sala/${SampleIds.roomCwbCofre}', 'O Cofre do Café'),
      ('/groups/${SampleIds.groupCwbCofreAlmost}', 'Grupo'),
      ('/groups/new', 'Criar grupo'),
      ('/rooms/${SampleIds.roomCwbCofre}/groups', 'O Cofre do Café'),
      ('/rooms/popular', 'Salas mais procuradas'),
      ('/rooms/category/mystery', 'Mistério'),
      ('/account/settings', 'Configurações'),
      ('/account/profile', 'Perfil'),
      ('/account/cards', 'Cartões cadastrados'),
      ('/account/wallet/top-up', 'Adicionar saldo'),
      ('/account/notices', 'Avisos'),
      ('/account/data', 'Meus dados'),
      ('/account/delete', 'Excluir conta'),
      ('/legal/termos', 'Termos de uso'),
      ('/legal/privacidade', 'Política de privacidade'),
      ('/legal/reembolso', 'Política de cancelamento e reembolso'),
      ('/news', 'Novidades'),
      ('/news/${SampleNewsIds.cwbBiblioteca}', 'Novidade'),
      ('/convite/${SampleIds.groupCwbCofreAlmost}', 'Convite'),
      ('/login', 'Entrar'),
      ('/cadastro', 'Cadastro'),
    ];

    for (final (path, marker) in routes) {
      GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
      await tester.pumpAndSettle();

      expect(find.text(marker), findsWidgets, reason: path);
      expect(find.byKey(AppKeys.scapeBack), findsOneWidget, reason: path);

      await tester.tap(find.byKey(AppKeys.scapeBack));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget, reason: path);
      expect(find.byKey(AppKeys.scapeBack), findsNothing, reason: path);
      expect(
        GoRouterState.of(tester.element(find.byType(HomeScreen))).uri.path,
        '/',
        reason: path,
      );
    }
  });

  testWidgets('the room cover keeps the back button over the photo', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .go('/salas/room-curitiba-near-1');
    await tester.pumpAndSettle();

    expect(find.text('A Chave'), findsOneWidget);
    expect(find.text('Sala: mín. 3 · máx. 8'), findsOneWidget);
    final back = find.byKey(AppKeys.scapeBack);
    expect(back, findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    final button = tester.getRect(back);
    final photo = tester.getRect(find.byType(RoomDetailScreen));
    expect(button.left, lessThan(80));
    expect(button.top, lessThan(photo.top + 80));
    expect(button.width, greaterThanOrEqualTo(44));
    expect(button.height, greaterThanOrEqualTo(44));
  });
}
