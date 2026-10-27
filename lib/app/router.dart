import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/app_shell.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/features/groups/presentation/my_groups_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/news/presentation/news_detail_screen.dart';

/// Rotas do app.
///
/// A barra tem dois ramos: `/` (Home, à esquerda) e `/groups/mine`
/// (Meus grupos, à direita). O app abre na Home. Criar grupo, o detalhe do
/// grupo e o detalhe da notícia abrem por cima da barra. `new` continua
/// antes de `:groupId` para a palavra não virar um id. `/groups` sem sufixo
/// volta para a Home, que agora é a busca.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      if (state.uri.path == '/groups') {
        return '/';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/groups/mine',
                name: 'my-groups',
                builder: (context, state) => const MyGroupsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/groups/new',
        name: 'create-group',
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/groups/:groupId',
        name: 'group-detail',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return GroupDetailScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: '/news/:newsId',
        name: 'news-detail',
        builder: (context, state) {
          final newsId = state.pathParameters['newsId']!;
          return NewsDetailScreen(newsId: newsId);
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
