import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/app_shell.dart';
import 'package:scapematch/features/account/presentation/account_destination_screen.dart';
import 'package:scapematch/features/account/presentation/account_screen.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/groups/presentation/invite_screen.dart';
import 'package:scapematch/features/catalog/presentation/popular_rooms_screen.dart';
import 'package:scapematch/features/catalog/presentation/room_category_screen.dart';
import 'package:scapematch/features/catalog/presentation/room_groups_screen.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/features/groups/presentation/my_groups_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';
import 'package:scapematch/features/news/presentation/news_browse_screen.dart';
import 'package:scapematch/features/news/presentation/news_detail_screen.dart';
import 'package:scapematch/features/wallet/presentation/add_balance_screen.dart';

/// Rotas do app.
///
/// A barra tem três ramos: `/` (Home), `/groups/mine` (Meus grupos) e
/// `/account` (Conta). O app abre na Home. Criar grupo, o detalhe do grupo,
/// o detalhe da notícia, a lista de uma sala e as páginas da Conta abrem
/// por cima da barra. `new` continua antes de `:groupId` para a palavra não
/// virar um id. `/groups` sem sufixo volta para a Home.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/groups') {
        return '/';
      }
      // Detalhe interno sem sessão vira o convite público.
      final detail = RegExp(r'^/groups/([^/]+)$').firstMatch(path);
      final id = detail?.group(1);
      if (id != null && id != 'mine' && id != 'new') {
        if (ref.read(authSessionProvider) == null) {
          return '/convite/$id';
        }
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                name: 'account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/convite/:groupId',
        name: 'invite',
        builder: (context, state) {
          return InviteScreen(groupId: state.pathParameters['groupId']!);
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/cadastro',
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/groups/new',
        name: 'create-group',
        builder: (context, state) => CreateGroupScreen(
          prefilledRoomId: state.uri.queryParameters['roomId'],
        ),
      ),
      GoRoute(
        path: '/rooms/popular',
        name: 'popular-rooms',
        builder: (context, state) => const PopularRoomsScreen(),
      ),
      GoRoute(
        path: '/rooms/category/:category',
        name: 'room-category',
        builder: (context, state) {
          return RoomCategoryScreen(
            categoryName: state.pathParameters['category']!,
          );
        },
      ),
      GoRoute(
        path: '/rooms/:roomId/groups',
        name: 'room-groups',
        builder: (context, state) {
          return RoomGroupsScreen(roomId: state.pathParameters['roomId']!);
        },
      ),
      GoRoute(
        path: '/account/wallet/top-up',
        name: 'add-balance',
        builder: (context, state) => const AddBalanceScreen(),
      ),
      GoRoute(
        path: '/account/:destination',
        name: 'account-destination',
        builder: (context, state) {
          return AccountDestinationScreen(
            destinationName: state.pathParameters['destination']!,
          );
        },
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
        path: '/news',
        name: 'news',
        builder: (context, state) => const NewsBrowseScreen(),
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
