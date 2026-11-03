import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/scape_tabs.dart';
import 'package:scapematch/core/ui/scape_logo.dart';

const scapeTabPaths = ['/', '/perto', '/groups/mine', '/account'];

void goScapeTab(BuildContext context, int index) {
  context.go(scapeTabPaths[index]);
}

/// Menu do site. Nas abas, [selectedIndex] marca a atual. Numa tela
/// empilhada, passe -1 para nenhuma ficar marcada.
class ScapeDesktopBar extends StatelessWidget {
  const ScapeDesktopBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

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
