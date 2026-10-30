import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/features/account/presentation/account_destination.dart';
import 'package:scapematch/features/account/presentation/current_user_provider.dart';
import 'package:scapematch/features/wallet/presentation/payment_methods_body.dart';

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
      AccountDestination.settings => 'Configurações',
      null => 'Conta',
    };

    return AppScaffold(
      appBar: AppBar(title: Text(title)),
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
      AccountDestination.partners => [
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
      ],
      AccountDestination.referral => [
        const _InfoCard(
          title: 'SCAPE-NICOLAS',
          subtitle:
              'Código fictício. Indique e ganhe não paga nada nesta versão.',
        ),
      ],
      AccountDestination.cards => [const PaymentMethodsBody()],
      AccountDestination.help => [
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
      AccountDestination.settings => [
        const _InfoCard(
          title: 'Notificações',
          subtitle: 'Desligadas. Este interruptor ainda não existe.',
        ),
        const SizedBox(height: 8),
        const _InfoCard(
          title: 'Cidade',
          subtitle: 'A escolha fica salva neste aparelho. Sem escolha, a Home abre em Curitiba.',
        ),
        const SizedBox(height: 8),
        Text(
          'Nada nesta tela altera o app de verdade.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    };
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
