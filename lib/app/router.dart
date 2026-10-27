import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/features/groups/presentation/create_group_screen.dart';
import 'package:scapematch/features/groups/presentation/find_groups_screen.dart';
import 'package:scapematch/features/groups/presentation/group_detail_screen.dart';
import 'package:scapematch/features/groups/presentation/my_groups_screen.dart';
import 'package:scapematch/features/home/presentation/home_screen.dart';

/// App routes. `new` and `mine` are registered before `:groupId` so those
/// words are not treated as a group id.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/groups',
        name: 'groups',
        builder: (context, state) => const FindGroupsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            name: 'create-group',
            builder: (context, state) => const CreateGroupScreen(),
          ),
          GoRoute(
            path: 'mine',
            name: 'my-groups',
            builder: (context, state) => const MyGroupsScreen(),
          ),
          GoRoute(
            path: ':groupId',
            name: 'group-detail',
            builder: (context, state) {
              final groupId = state.pathParameters['groupId']!;
              return GroupDetailScreen(groupId: groupId);
            },
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
