import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/person_avatar.dart';
import 'package:scapematch/core/ui/scape_back_button.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/features/social/presentation/social_providers.dart';
import 'package:scapematch/providers/repositories.dart';

/// Cria uma turma fixa com amigos. A foto é opcional.
class CreateCrewScreen extends ConsumerStatefulWidget {
  const CreateCrewScreen({super.key});

  @override
  ConsumerState<CreateCrewScreen> createState() => _CreateCrewScreenState();
}

class _CreateCrewScreenState extends ConsumerState<CreateCrewScreen> {
  final _name = TextEditingController();
  final _picked = <String>{};
  String? _photo;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(socialViewProvider).asData?.value;
    final friends = view?.friends ?? const <FriendCard>[];
    final theme = Theme.of(context);
    return AppScaffold(
      desktopMaxWidth: 720,
      appBar: AppBar(
        leading: const ScapeBackButton(),
        title: const Text('Criar turma'),
      ),
      body: ListView(
        key: AppKeys.createCrewForm,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 12),
          Text(
            'Uma turma é a dupla ou o grupo que já joga junto. Quem você chamar precisa aceitar.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 16),
          TextField(
            key: AppKeys.crewName,
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome da turma',
              hintText: 'Dupla do centro',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Foto, se quiser',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _PhotoChoice(
                  selected: _photo == null,
                  label: 'Sem foto',
                  onTap: () => setState(() => _photo = null),
                  child: const Icon(Icons.hide_image_outlined),
                ),
                for (var index = 0; index < 4; index++)
                  _PhotoChoice(
                    selected:
                        _photo == 'assets/images/people/0${index + 1}.jpg',
                    label: 'Foto ${index + 1}',
                    onTap: () => setState(
                      () => _photo = 'assets/images/people/0${index + 1}.jpg',
                    ),
                    child: ScapePhoto(
                      asset: 'assets/images/people/0${index + 1}.jpg',
                      semanticLabel: 'Foto ${index + 1}',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Amigos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Aceite um amigo antes de criar a turma.'),
            )
          else
            for (final friend in friends)
              CheckboxListTile(
                key: AppKeys.crewFriend(friend.userId),
                contentPadding: EdgeInsets.zero,
                secondary: PersonAvatar(name: friend.displayName, radius: 18),
                value: _picked.contains(friend.userId),
                title: Text(friend.displayName),
                subtitle: Text('@${friend.username}'),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _picked.add(friend.userId);
                    } else {
                      _picked.remove(friend.userId);
                    }
                  });
                },
              ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      bottomBar: FilledButton(
        key: AppKeys.crewCreateSubmit,
        onPressed: _saving ? null : _submit,
        child: Text(_saving ? 'Criando...' : 'Criar turma'),
      ),
    );
  }

  Future<void> _submit() async {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      setState(() => _error = 'Entre na conta para criar a turma.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(socialRepositoryProvider)
        .createCrew(
          actorId: session.id,
          name: _name.text,
          friendIds: _picked.toList(),
          photoAsset: _photo,
        );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    switch (result) {
      case SocialOk(:final message):
        ref.read(socialTickProvider.notifier).bump();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message ?? 'Turma criada.')));
        context.pop();
      case SocialFailure(:final message):
        setState(() => _error = message);
    }
  }
}

class _PhotoChoice extends StatelessWidget {
  const _PhotoChoice({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        key: AppKeys.crewPhoto(label),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
