import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/scape_tabs.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
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
                  _DesktopNav(
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
    );
  }
}

class _DesktopNav extends StatelessWidget {
  const _DesktopNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  ScapeLogo(
                    height: 36,
                    onTap: () => onSelected(0),
                  ),
                  const SizedBox(width: 28),
                  for (var index = 0; index < scapeTabs.length; index++) ...[
                    if (index > 0) const SizedBox(width: 4),
                    _DesktopTab(
                      tab: scapeTabs[index],
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTab extends StatelessWidget {
  const _DesktopTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final ScapeTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      key: tab.key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? tab.selectedIcon : tab.icon,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              tab.label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
