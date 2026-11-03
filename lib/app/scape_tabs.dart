import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Abas do jogador, na mesma ordem da barra do celular e do menu do site.
class ScapeTab {
  const ScapeTab({
    required this.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Key key;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const scapeTabs = <ScapeTab>[
  ScapeTab(
    key: AppKeys.homeTab,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  ScapeTab(
    key: AppKeys.nearTab,
    icon: Icons.radar_outlined,
    selectedIcon: Icons.radar,
    label: 'Perto de você',
  ),
  ScapeTab(
    key: AppKeys.myGroups,
    icon: Icons.event_available_outlined,
    selectedIcon: Icons.event_available,
    label: 'Meus grupos',
  ),
  ScapeTab(
    key: AppKeys.accountTab,
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Conta',
  ),
];
