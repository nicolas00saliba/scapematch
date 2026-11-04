import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/auth/presentation/auth_return.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/features/social/domain/social_rules.dart';
import 'package:scapematch/features/social/presentation/social_providers.dart';
import 'package:scapematch/providers/repositories.dart';

/// Lista de amigos, pedidos, turmas e o convite por link ou QR.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _username = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final view = ref.watch(socialViewProvider);
    return AppScaffold(
      desktopMaxWidth: 840,
      appBar: AppBar(
        leading: const ScapeBackButton(),
        title: const Text('Amigos'),
      ),
      body: session == null
          ? _SignedOut(
              onLogin: () => context.push(loginLocation('/account/friends')),
            )
          : view.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => const Center(
                child: Text('Não foi possível carregar os amigos.'),
              ),
              data: (data) {
                if (data == null) {
                  return const SizedBox.shrink();
                }
                return _Body(
                  view: data,
                  username: _username,
                  sending: _sending,
                  onRequest: _request,
                  onInvite: () => _showInvite(data),
                  onResult: _apply,
                );
              },
            ),
    );
  }

  Future<void> _request() async {
    final session = ref.read(authSessionProvider);
    if (session == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(socialRepositoryProvider)
        .requestByUsername(actorId: session.id, username: _username.text);
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    if (result is SocialOk) {
      _username.clear();
    }
    _finish(result);
  }

  Future<void> _apply(Future<SocialResult> pending) async {
    _finish(await pending);
  }

  Future<void> _finish(SocialResult result) async {
    ref.read(socialTickProvider.notifier).bump();
    ref.read(communityTickProvider.notifier).bump();
    final message = switch (result) {
      SocialOk(:final message) => message ?? 'Pronto.',
      SocialFailure(:final message) => message,
    };
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showInvite(SocialView view) async {
    final link = SocialRules.inviteLink(view.inviteCode);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: AppKeys.friendInviteDialog,
          title: const Text('Convite de amigo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mostre o QR ou envie o link. Quem abrir pede amizade para @${view.me.username}.',
              ),
              const SizedBox(height: 12),
              ColoredBox(
                color: Colors.white,
                child: QrImageView(
                  data: link,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(link, key: AppKeys.friendInviteLink),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Copiar link'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const ExampleDataBanner(),
        const SizedBox(height: 16),
        const Text('Entre na conta para ver amigos e turmas.'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onLogin, child: const Text('Entrar')),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.view,
    required this.username,
    required this.sending,
    required this.onRequest,
    required this.onInvite,
    required this.onResult,
  });

  final SocialView view;
  final TextEditingController username;
  final bool sending;
  final VoidCallback onRequest;
  final VoidCallback onInvite;
  final Future<void> Function(Future<SocialResult> pending) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(authSessionProvider);
    return ListView(
      key: AppKeys.friendList,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const ExampleDataBanner(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '@${view.me.username}',
                key: AppKeys.myUsername,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: AppKeys.friendInvite,
              onPressed: onInvite,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Convite'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Adicione pelo @usuário ou pelo QR. O pedido só vira amizade quando a outra pessoa aceita.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: AppKeys.friendUsername,
                controller: username,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Adicionar por @usuário',
                  hintText: '@marina',
                ),
                onSubmitted: (_) => onRequest(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: AppKeys.friendRequestSubmit,
              style: _inlineButton,
              onPressed: sending ? null : onRequest,
              child: const Text('Pedir'),
            ),
          ],
        ),
        if (view.incoming.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Pedidos', style: theme.textTheme.titleMedium),
          for (final card in view.incoming)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(name: card.displayName, radius: 20),
              title: Text(card.displayName),
              subtitle: Text('@${card.username}'),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    key: AppKeys.declineFriend(card.friendshipId),
                    onPressed: session == null
                        ? null
                        : () => onResult(
                            ref
                                .read(socialRepositoryProvider)
                                .declineFriend(
                                  actorId: session.id,
                                  friendshipId: card.friendshipId,
                                ),
                          ),
                    child: const Text('Recusar'),
                  ),
                  FilledButton(
                    key: AppKeys.acceptFriend(card.friendshipId),
                    style: _inlineButton,
                    onPressed: session == null
                        ? null
                        : () => onResult(
                            ref
                                .read(socialRepositoryProvider)
                                .acceptFriend(
                                  actorId: session.id,
                                  friendshipId: card.friendshipId,
                                ),
                          ),
                    child: const Text('Aceitar'),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Amigos',
          key: AppKeys.friendSection,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (view.friends.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Você ainda não tem amigos aceitos.'),
          )
        else
          for (final card in view.friends)
            ListTile(
              key: AppKeys.friendRow(card.userId),
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(name: card.displayName, radius: 20),
              title: Text(card.displayName),
              subtitle: Text('@${card.username}'),
              trailing: PopupMenuButton<String>(
                key: AppKeys.friendMenu(card.userId),
                tooltip: 'Ações',
                onSelected: session == null
                    ? null
                    : (action) {
                        final repo = ref.read(socialRepositoryProvider);
                        final actorId = session.id;
                        final future = switch (action) {
                          'remove' => repo.removeFriend(
                            actorId: actorId,
                            otherUserId: card.userId,
                          ),
                          'block' => repo.blockUser(
                            actorId: actorId,
                            otherUserId: card.userId,
                          ),
                          _ => Future<SocialResult>.value(
                            const SocialFailure('Ação desconhecida.'),
                          ),
                        };
                        onResult(future);
                      },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remover')),
                  PopupMenuItem(value: 'block', child: Text('Bloquear')),
                ],
              ),
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Turmas',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              key: AppKeys.createCrew,
              onPressed: () => context.push('/account/crews/new'),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Criar turma'),
            ),
          ],
        ),
        if (view.crews.isEmpty)
          const Text('Uma turma é a dupla ou o grupo fixo com quem você joga.')
        else
          for (final crew in view.crews)
            _CrewTile(crew: crew, onResult: onResult),
        if (view.outgoing.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Pedidos enviados', style: theme.textTheme.titleMedium),
          for (final card in view.outgoing)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(card.displayName),
              subtitle: Text('@${card.username} · aguardando'),
            ),
        ],
        if (view.blocked.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Bloqueados', style: theme.textTheme.titleMedium),
          for (final card in view.blocked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(card.displayName),
              subtitle: Text('@${card.username}'),
              trailing: TextButton(
                onPressed: session == null
                    ? null
                    : () => onResult(
                        ref
                            .read(socialRepositoryProvider)
                            .unblockUser(
                              actorId: session.id,
                              otherUserId: card.userId,
                            ),
                      ),
                child: const Text('Desbloquear'),
              ),
            ),
        ],
      ],
    );
  }
}

class _CrewTile extends ConsumerWidget {
  const _CrewTile({required this.crew, required this.onResult});

  final CrewView crew;
  final Future<void> Function(Future<SocialResult> pending) onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final names = [
      for (final person in crew.people)
        if (person.status == CrewMemberStatus.accepted) person.displayName,
    ].join(', ');
    final pending = [
      for (final person in crew.people)
        if (person.status == CrewMemberStatus.invited) person.displayName,
    ];
    final subtitle = pending.isEmpty
        ? names
        : '$names · convite: ${pending.join(', ')}';
    return ListTile(
      key: AppKeys.crewRow(crew.id),
      contentPadding: EdgeInsets.zero,
      leading: _CrewPhoto(asset: crew.photoAsset, name: crew.name),
      title: Text(crew.name),
      subtitle: Text(subtitle),
      trailing: _actions(ref, session?.id),
    );
  }

  Widget? _actions(WidgetRef ref, String? actorId) {
    if (actorId == null) {
      return null;
    }
    final repo = ref.read(socialRepositoryProvider);
    if (crew.myStatus == CrewMemberStatus.invited) {
      return Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: () => onResult(
              repo.respondCrew(
                actorId: actorId,
                crewId: crew.id,
                accept: false,
              ),
            ),
            child: const Text('Recusar'),
          ),
          FilledButton(
            key: AppKeys.acceptCrew(crew.id),
            style: _inlineButton,
            onPressed: () => onResult(
              repo.respondCrew(actorId: actorId, crewId: crew.id, accept: true),
            ),
            child: const Text('Entrar'),
          ),
        ],
      );
    }
    if (crew.iAmCreator) {
      return TextButton(
        key: AppKeys.deleteCrew(crew.id),
        onPressed: () =>
            onResult(repo.deleteCrew(actorId: actorId, crewId: crew.id)),
        child: const Text('Excluir'),
      );
    }
    if (crew.myStatus == CrewMemberStatus.accepted) {
      return TextButton(
        key: AppKeys.leaveCrew(crew.id),
        onPressed: () =>
            onResult(repo.leaveCrew(actorId: actorId, crewId: crew.id)),
        child: const Text('Sair'),
      );
    }
    return null;
  }
}

const _inlineButton = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(48, 40)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

class _CrewPhoto extends StatelessWidget {
  const _CrewPhoto({required this.name, this.asset});

  final String name;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final photo = asset;
    if (photo == null || photo.isEmpty) {
      return CircleAvatar(child: Text(name.isEmpty ? '?' : name[0]));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: ScapePhoto(asset: photo, semanticLabel: name),
      ),
    );
  }
}
