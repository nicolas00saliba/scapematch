import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/social/domain/social_models.dart';
import 'package:scapematch/features/social/domain/social_rules.dart';
import 'package:scapematch/features/social/presentation/social_providers.dart';

/// Como a pessoa ocupa as vagas: sozinha, com a turma ou com amigos.
enum PartyChoice { solo, crew, friends }

class PartyJoinRequest {
  const PartyJoinRequest({required this.choice, this.companions = const []});

  final PartyChoice choice;
  final List<PartyCompanion> companions;

  int get seats => 1 + companions.length;
}

/// Folha para entrar sozinho ou reservar as vagas da turma de uma vez.
Future<PartyJoinRequest?> showPartyJoinSheet(
  BuildContext context, {
  required Group group,
}) {
  return showModalBottomSheet<PartyJoinRequest>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PartyJoinSheet(group: group),
  );
}

class _PartyJoinSheet extends ConsumerStatefulWidget {
  const _PartyJoinSheet({required this.group});

  final Group group;

  @override
  ConsumerState<_PartyJoinSheet> createState() => _PartyJoinSheetState();
}

class _PartyJoinSheetState extends ConsumerState<_PartyJoinSheet> {
  PartyChoice _choice = PartyChoice.crew;
  String? _crewId;
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(socialViewProvider).asData?.value;
    final theme = Theme.of(context);
    final open = widget.group.openSeats;
    final crews = view?.readyCrews ?? const <CrewView>[];
    final friends = view?.friends ?? const <FriendCard>[];
    _crewId ??= crews.isEmpty ? null : crews.first.id;
    final crew = _selected(crews);
    final companions = switch (_choice) {
      PartyChoice.solo => const <PartyCompanion>[],
      PartyChoice.crew => _crewCompanions(view, crew),
      PartyChoice.friends => _friendCompanions(friends),
    };
    final seats = 1 + companions.length;
    final soloFits = open >= 1;
    final fits = _choice == PartyChoice.solo
        ? soloFits
        : companions.isNotEmpty && seats <= open;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: AppKeys.partyJoinSheet,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Entrar com a turma',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Este grupo tem $open ${open == 1 ? 'vaga' : 'vagas'}. '
              'Cada pessoa paga a própria parte. O líder não paga pelos outros.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _choiceTile(
              key: AppKeys.partySolo,
              choice: PartyChoice.solo,
              title: 'Eu sozinho',
              subtitle: soloFits ? '1 vaga' : 'Sem vaga',
              enabled: soloFits,
            ),
            if (crews.isNotEmpty)
              _choiceTile(
                key: AppKeys.partyCrew,
                choice: PartyChoice.crew,
                title: crew == null ? 'Minha turma' : crew.name,
                subtitle: crew == null
                    ? 'Escolha uma turma'
                    : _crewSubtitle(crew, open),
                enabled: true,
              ),
            if (_choice == PartyChoice.crew && crews.length > 1)
              for (final item in crews)
                ListTile(
                  key: AppKeys.partyCrewOption(item.id),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _crewId == item.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(item.name),
                  subtitle: Text('${item.acceptedCount} pessoas'),
                  onTap: () => setState(() => _crewId = item.id),
                ),
            _choiceTile(
              key: AppKeys.partyFriends,
              choice: PartyChoice.friends,
              title: 'Eu + amigos',
              subtitle: 'Você escolhe quem ocupa vaga com você',
              enabled: friends.isNotEmpty,
            ),
            if (_choice == PartyChoice.friends)
              for (final friend in friends)
                CheckboxListTile(
                  key: AppKeys.partyFriend(friend.userId),
                  contentPadding: EdgeInsets.zero,
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
            const SizedBox(height: 8),
            if (!fits && _choice != PartyChoice.solo)
              Text(
                'A seleção precisa de $seats ${seats == 1 ? 'vaga' : 'vagas'} e há $open. Ninguém entra pela metade.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: AppKeys.partyJoinConfirm,
              onPressed:
                  !fits || (_choice != PartyChoice.solo && companions.isEmpty)
                  ? null
                  : () {
                      final request = PartyJoinRequest(
                        choice: _choice,
                        companions: companions,
                      );
                      Navigator.pop(context, request);
                    },
              child: Text(
                _choice == PartyChoice.solo
                    ? 'Entrar sozinho'
                    : 'Reservar $seats vagas',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceTile({
    required Key key,
    required PartyChoice choice,
    required String title,
    required String subtitle,
    required bool enabled,
  }) {
    final selected = _choice == choice;
    return ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: enabled ? () => setState(() => _choice = choice) : null,
    );
  }

  CrewView? _selected(List<CrewView> crews) {
    for (final crew in crews) {
      if (crew.id == _crewId) {
        return crew;
      }
    }
    return crews.isEmpty ? null : crews.first;
  }

  List<PartyCompanion> _crewCompanions(SocialView? view, CrewView? crew) {
    if (view == null || crew == null) {
      return const [];
    }
    return [
      for (final person in crew.companionsOf(view.me.id))
        PartyCompanion(userId: person.userId, displayName: person.displayName),
    ];
  }

  List<PartyCompanion> _friendCompanions(List<FriendCard> friends) {
    return [
      for (final friend in friends)
        if (_picked.contains(friend.userId))
          PartyCompanion(
            userId: friend.userId,
            displayName: friend.displayName,
          ),
    ];
  }

  String _crewSubtitle(CrewView crew, int open) {
    final fits = SocialRules.groupFitsCrew(
      openSeats: open,
      crewSeats: crew.acceptedCount,
    );
    if (!fits) {
      return '${crew.acceptedCount} pessoas · não cabe neste grupo';
    }
    return '${crew.acceptedCount} pessoas · ocupa ${crew.acceptedCount} vagas';
  }
}
