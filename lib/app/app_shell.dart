import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/desktop_nav.dart';
import 'package:scapematch/app/scape_tabs.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/window_class.dart';

/// Navegação do jogador.
///
/// No celular, a barra fica embaixo: Home, Perto de você, Meus grupos, Conta.
/// No site, o mesmo menu fica no topo, ao lado da marca, e o conteúdo usa
/// a largura da janela. O índice segue os ramos do [StatefulShellRoute].
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isScapeDesktop(context);
    return RepaintBoundary(
      key: AppKeys.appFrame,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: desktop
            ? Column(
                children: [
                  ScapeDesktopBar(
                    selectedIndex: navigationShell.currentIndex,
                    onSelected: _go,
                  ),
                  Expanded(child: navigationShell),
                ],
              )
            : navigationShell,
        bottomNavigationBar: desktop ? null : _phoneBar(context),
      ),
    );
  }

  Widget _phoneBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppScaffold.maxWidth),
            child: NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              destinations: [
                for (final tab in scapeTabs)
                  NavigationDestination(
                    key: tab.key,
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: tab.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
