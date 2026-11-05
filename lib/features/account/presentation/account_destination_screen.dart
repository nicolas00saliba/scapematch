import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/account/presentation/account_destination.dart';
import 'package:scapematch/features/account/presentation/account_list_tile.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';
import 'package:scapematch/features/theme/presentation/theme_choice_control.dart';
import 'package:scapematch/features/wallet/presentation/payment_methods_body.dart';
import 'package:scapematch/providers/repositories.dart';

/// Tela curta de um item da Conta. Tudo aqui é placeholder fictício.
class AccountDestinationScreen extends ConsumerWidget {
  const AccountDestinationScreen({super.key, required this.destinationName});

  final String destinationName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = accountDestinationByName(destinationName);
    final title = switch (destination) {
      AccountDestination.profile => 'Perfil',
      AccountDestination.partners => 'Meus parceiros de jogo',
      AccountDestination.referral => 'Indique e ganhe',
      AccountDestination.cards => 'Cartões cadastrados',
      AccountDestination.help => 'Ajuda',
      AccountDestination.policies => 'Termos e políticas',
      AccountDestination.dataPrivacy => 'Meus dados e privacidade',
      AccountDestination.settings => 'Configurações',
      null => 'Conta',
    };

    return AppScaffold(
      desktopMaxWidth: AppScaffold.readingMax,
      appBar: AppBar(leading: const ScapeBackButton(), title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          if (destination == null)
            const Text('Essa página não existe.')
          else
            ..._body(context, ref, destination),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    WidgetRef ref,
    AccountDestination destination,
  ) {
    final name = ref.watch(currentUserProvider).displayName;
    final theme = Theme.of(context);
    final sample = ref.watch(backendPlanProvider).loadsSampleDatabase;
    return switch (destination) {
      AccountDestination.profile => [
        Text(
          name,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sem login nesta versão. Este perfil é fictício e não sai deste aparelho.',
        ),
      ],
      AccountDestination.partners =>
        sample
            ? [
                const Text(
                  'Ainda não há uma lista real de parceiros. Os nomes abaixo são de exemplo, das salas fictícias.',
                ),
                const SizedBox(height: 12),
                for (final person in const ['Marina', 'Caio', 'Helena'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _InfoCard(
                      title: person,
                      subtitle: 'Jogou com você numa sala de exemplo.',
                    ),
                  ),
              ]
            : [const Text('Ainda não há parceiros de jogo nesta conta.')],
      AccountDestination.referral => [
        _InfoCard(
          title: sample ? 'SCAPE-NICOLAS' : 'Em breve',
          subtitle: sample
              ? 'Código fictício. Indique e ganhe não paga nada nesta versão.'
              : 'Indique e ganhe ainda não está disponível.',
        ),
      ],
      AccountDestination.cards => [const PaymentMethodsBody()],
      AccountDestination.help => [
        if (showsIntroReplay(ref.watch(onboardingModeProvider))) ...[
          _AccountLink(
            tileKey: AppKeys.accountIntro,
            icon: Icons.slideshow_outlined,
            title: OnboardingMessages.replay,
            subtitle: 'As quatro telas da primeira abertura.',
            onTap: () => context.go('/introducao'),
          ),
          const SizedBox(height: 10),
        ],
        const _InfoCard(
          title: 'Como achar um grupo?',
          subtitle: 'Escolha a cidade, abra uma sala e toque em Achar grupo, ou use a busca da Home.',
        ),
        const SizedBox(height: 8),
        const _InfoCard(
          title: 'Os dados são de exemplo',
          subtitle: 'Casas, salas, notícias e a carteira foram inventados. Nada é cobrado.',
        ),
      ],
      AccountDestination.policies => [
        _AccountLink(
          tileKey: AppKeys.accountLegal,
          icon: Icons.description_outlined,
          title: 'Termos de uso',
          subtitle: 'O combinado desta versão de exemplo.',
          onTap: () => context.push('/legal/termos'),
        ),
        const SizedBox(height: 10),
        _AccountLink(
          tileKey: AppKeys.accountPrivacy,
          icon: Icons.policy_outlined,
          title: 'Privacidade',
          subtitle: 'O que o app guarda e o que não guarda.',
          onTap: () => context.push('/legal/privacidade'),
        ),
        const SizedBox(height: 10),
        _AccountLink(
          tileKey: AppKeys.accountRefund,
          icon: Icons.currency_exchange,
          title: 'Cancelamento e reembolso',
          subtitle: 'Grupo que não fecha, janela da casa e arrependimento.',
          onTap: () => context.push('/legal/reembolso'),
        ),
      ],
      AccountDestination.dataPrivacy => [
        _AccountLink(
          tileKey: AppKeys.accountData,
          icon: Icons.folder_shared_outlined,
          title: 'Meus dados',
          subtitle: 'O que esta versão sabe de você.',
          onTap: () => context.push('/account/data'),
        ),
        const SizedBox(height: 10),
        _AccountLink(
          tileKey: AppKeys.accountDelete,
          icon: Icons.delete_outline,
          title: 'Pedir exclusão da conta',
          subtitle: 'O pedido fica registrado neste exemplo.',
          onTap: () => context.push('/account/delete'),
        ),
      ],
      AccountDestination.settings => [
        const ThemeChoiceControl(),
        const SizedBox(height: 16),
        const _InfoCard(
          title: 'Notificações',
          subtitle: 'Os lembretes ficam em Avisos, aqui embaixo. O push do celular espera a conta de verdade.',
        ),
        const SizedBox(height: 10),
        _AccountLink(
          tileKey: AppKeys.accountNotices,
          icon: Icons.notifications_outlined,
          title: 'Avisos',
          subtitle: 'Lembretes desta conta de exemplo.',
          onTap: () => context.push('/account/notices'),
        ),
        const SizedBox(height: 10),
        const _InfoCard(
          title: 'Cidade',
          subtitle: 'A escolha fica salva neste aparelho. Sem escolha, a Home abre em Curitiba.',
        ),
      ],
    };
  }
}

class _AccountLink extends StatelessWidget {
  const _AccountLink({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: tileKey,
      child: AccountListTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
