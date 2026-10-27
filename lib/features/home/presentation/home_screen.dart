import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'ScapeMatch',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monte um grupo para jogar escape room na sua cidade.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          const CitySelector(),
          const SizedBox(height: 20),
          _EntryCard(
            buttonKey: AppKeys.findGroup,
            icon: Icons.search,
            title: 'Encontrar grupo',
            subtitle: 'Veja quem já está montando uma sessão.',
            onTap: () => context.push('/groups'),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            buttonKey: AppKeys.createGroup,
            icon: Icons.add,
            title: 'Criar grupo',
            subtitle: 'Escolha a sala, o horário e quantas vagas faltam.',
            onTap: () => context.push('/groups/new'),
          ),
          const SizedBox(height: 12),
          _EntryCard(
            buttonKey: AppKeys.myGroups,
            icon: Icons.event_available_outlined,
            title: 'Meus grupos',
            subtitle: 'Próximos, passados, cancelados e o reembolso simulado.',
            onTap: () => context.push('/groups/mine'),
          ),
          const SizedBox(height: 20),
          const ExampleDataBanner(),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.buttonKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      identifier: buttonKey == AppKeys.findGroup
          ? 'find-group'
          : buttonKey == AppKeys.myGroups
          ? 'my-groups'
          : 'create-group',
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
