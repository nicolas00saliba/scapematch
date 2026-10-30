import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/account/presentation/account_destination.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Aba Conta. O desenho é do ScapeMatch: cartões claros, verde e cobre.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    if (session == null) {
      return const _SignedOutAccount();
    }
    final name = session.displayName;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Conta'),
        actions: [
          IconButton(
            key: AppKeys.accountSettings,
            tooltip: 'Configurações',
            onPressed: () => context.push('/account/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            'Olá, $name',
            key: AppKeys.accountGreeting,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sua conta de exemplo nesta versão.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const _WalletCard(),
          const SizedBox(height: 16),
          for (final item in _items) ...[
            _AccountTile(item: item),
            const SizedBox(height: 10),
          ],
          const _ReplayIntroButton(),
          const SizedBox(height: 10),
          OutlinedButton(
            key: AppKeys.accountSignOut,
            onPressed: () => _signOut(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text(AccountMessages.signOut),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(AccountMessages.signOutTitle),
          content: const Text(AccountMessages.signOutBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(AccountMessages.signOutStay),
            ),
            FilledButton(
              key: AppKeys.dialogConfirm,
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AccountMessages.signOutConfirm),
            ),
          ],
        );
      },
    );
    if (leave != true || !context.mounted) {
      return;
    }
    await ref.read(authSessionProvider.notifier).signOut();
  }
}

class _SignedOutAccount extends StatelessWidget {
  const _SignedOutAccount();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppScaffold(
      appBar: AppBar(title: const Text('Conta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            AccountMessages.signedOutTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AccountMessages.signedOutBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: AppKeys.accountSignIn,
            onPressed: () => context.push(loginLocation('/account')),
            child: const Text(AccountMessages.signInAgain),
          ),
          const SizedBox(height: 10),
          const _ReplayIntroButton(),
        ],
      ),
    );
  }
}

class _ReplayIntroButton extends StatelessWidget {
  const _ReplayIntroButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: AppKeys.accountIntro,
      onPressed: () => context.go('/introducao'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: const Icon(Icons.slideshow_outlined),
      label: const Text(OnboardingMessages.replay),
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final balance = ref.watch(walletBalanceProvider);
    final amount = balance.maybeWhen(
      data: (money) => formatPrice(money.cents),
      orElse: () => '—',
    );
    return Material(
      key: AppKeys.accountWallet,
      color: scheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Carteira ScapeMatch',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Créditos fictícios. Reembolsos simulados apareceriam aqui. Nada é cobrado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: AppKeys.accountAddBalance,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.surface,
                foregroundColor: scheme.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => context.push('/account/wallet/top-up'),
              child: const Text('Adicionar saldo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountItem {
  const _AccountItem({
    required this.destination,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final AccountDestination destination;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _items = <_AccountItem>[
  _AccountItem(
    destination: AccountDestination.profile,
    title: 'Perfil',
    subtitle: 'Nome e o que esta versão sabe de você',
    icon: Icons.badge_outlined,
  ),
  _AccountItem(
    destination: AccountDestination.partners,
    title: 'Meus parceiros de jogo',
    subtitle: 'Quem já jogou com você, de exemplo',
    icon: Icons.groups_outlined,
  ),
  _AccountItem(
    destination: AccountDestination.referral,
    title: 'Indique e ganhe',
    subtitle: 'Um código fictício, sem prêmio',
    icon: Icons.card_giftcard_outlined,
  ),
  _AccountItem(
    destination: AccountDestination.cards,
    title: 'Cartões cadastrados',
    subtitle: 'Formas de pagamento da sua conta',
    icon: Icons.credit_card_outlined,
  ),
  _AccountItem(
    destination: AccountDestination.help,
    title: 'Ajuda',
    subtitle: 'Respostas curtas desta versão',
    icon: Icons.help_outline,
  ),
];

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.item});

  final _AccountItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        key: AppKeys.accountDestination(item.destination.name),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/account/${item.destination.name}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(item.icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      item.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
