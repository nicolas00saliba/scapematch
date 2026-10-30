import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';

/// Barra inferior. A ordem é Home, Meus grupos, Conta.
///
/// O índice segue os ramos do [StatefulShellRoute]: 0 é a Home, 1 é Meus
/// grupos, 2 é a Conta. O app abre na Home porque a rota inicial é `/`.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: navigationShell,
      bottomNavigationBar: ColoredBox(
        color: scheme.surface,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppScaffold.maxWidth),
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
              destinations: const [
                NavigationDestination(
                  key: AppKeys.homeTab,
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  key: AppKeys.myGroups,
                  icon: Icon(Icons.event_available_outlined),
                  selectedIcon: Icon(Icons.event_available),
                  label: 'Meus grupos',
                ),
                NavigationDestination(
                  key: AppKeys.accountTab,
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Conta',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
