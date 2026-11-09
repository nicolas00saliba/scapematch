import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/scape_grid.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/account/presentation/account_destination.dart';
import 'package:scapematch/features/account/presentation/account_list_tile.dart';
import 'package:scapematch/features/account/presentation/account_messages.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/wallet/presentation/real_account_wallet.dart';
import 'package:scapematch/features/wallet/presentation/wallet_providers.dart';

/// Aba Conta. O desenho é do EscapeMatch: cartões claros, verde e cobre.
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
            ref.watch(backendPlanProvider).loadsSampleDatabase
                ? 'Sua conta de exemplo nesta versão.'
                : 'Sua conta no EscapeMatch.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (isScapeDesktop(context))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: ref.watch(backendPlanProvider).connectsSupabase
                      ? const RealAccountWallet()
                      : const _WalletCard(),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 7,
                  child: ScapeWrapGrid(
                    maxColumns: 2,
                    gap: 10,
                    children: [
                      for (final item in _signedInItems)
                        _AccountTile(item: item),
                      const _FriendsTile(),
                      _SignOutTile(onPressed: () => _signOut(context, ref)),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            ref.watch(backendPlanProvider).connectsSupabase
                ? const RealAccountWallet()
                : const _WalletCard(),
            const SizedBox(height: 16),
            for (final item in _signedInItems) ...[
              _AccountTile(item: item),
              const SizedBox(height: 10),
            ],
            const _FriendsTile(),
            const SizedBox(height: 10),
            _SignOutTile(onPressed: () => _signOut(context, ref)),
          ],
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
          content: Text(
            scapeUsesLiveBackend
                ? 'A sessão termina neste aparelho. Dá para entrar de novo com o mesmo e-mail.'
                : AccountMessages.signOutBody,
          ),
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
            AccountMessages.signedOutTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            scapeUsesLiveBackend
                ? 'Entre de novo para ver a conta.'
                : AccountMessages.signedOutBody,
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
          const SizedBox(height: 16),
          for (final item in _signedOutItems) ...[
            _AccountTile(item: item),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _FriendsTile extends StatelessWidget {
  const _FriendsTile();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: AppKeys.accountFriends,
      child: AccountListTile(
        icon: Icons.diversity_3_outlined,
        title: 'Amigos e turmas',
        subtitle: 'Peça amizade, monte a turma e entre junto',
        onTap: () => context.push('/account/friends'),
      ),
    );
  }
}

class _SignOutTile extends StatelessWidget {
  const _SignOutTile({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return KeyedSubtree(
      key: AppKeys.accountSignOut,
      child: AccountListTile(
        icon: Icons.logout,
        title: AccountMessages.signOut,
        subtitle: 'Encerra a sessão de exemplo neste aparelho.',
        foreground: error,
        onTap: onPressed,
      ),
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
              'Carteira EscapeMatch',
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

const _signedInItems = <_AccountItem>[
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
    subtitle: 'Introdução e respostas curtas desta versão',
    icon: Icons.help_outline,
  ),
  _AccountItem(
    destination: AccountDestination.policies,
    title: 'Termos e políticas',
    subtitle: 'Uso, privacidade e reembolso',
    icon: Icons.gavel_outlined,
  ),
  _AccountItem(
    destination: AccountDestination.dataPrivacy,
    title: 'Meus dados e privacidade',
    subtitle: 'O que esta versão guarda e como pedir exclusão',
    icon: Icons.privacy_tip_outlined,
  ),
];

const _signedOutItems = <_AccountItem>[
  _AccountItem(
    destination: AccountDestination.help,
    title: 'Ajuda',
    subtitle: 'Introdução e respostas curtas desta versão',
    icon: Icons.help_outline,
  ),
  _AccountItem(
    destination: AccountDestination.policies,
    title: 'Termos e políticas',
    subtitle: 'Uso, privacidade e reembolso',
    icon: Icons.gavel_outlined,
  ),
];

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.item});

  final _AccountItem item;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: AppKeys.accountDestination(item.destination.name),
      child: AccountListTile(
        icon: item.icon,
        title: item.title,
        subtitle: item.subtitle,
        onTap: () => context.push('/account/${item.destination.name}'),
      ),
    );
  }
}
