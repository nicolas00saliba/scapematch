import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/reviews/data/venue_staff_gateway.dart';

/// Convite pendente. A pessoa entra na equipe só depois de aceitar.
class VenueInviteBanner extends StatelessWidget {
  const VenueInviteBanner({
    super.key,
    required this.invites,
    required this.onAccept,
    required this.onDecline,
  });

  final List<VenueInvite> invites;
  final Future<String?> Function(VenueInvite invite) onAccept;
  final Future<String?> Function(VenueInvite invite) onDecline;

  @override
  Widget build(BuildContext context) {
    if (invites.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final invite in invites)
          _InviteCard(
            invite: invite,
            onAccept: onAccept,
            onDecline: onDecline,
          ),
      ],
    );
  }
}

class _InviteCard extends StatefulWidget {
  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  final VenueInvite invite;
  final Future<String?> Function(VenueInvite invite) onAccept;
  final Future<String?> Function(VenueInvite invite) onDecline;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  String? _error;
  var _busy = false;

  Future<void> _run(Future<String?> Function(VenueInvite invite) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await action(widget.invite);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    return Card(
      key: AppKeys.venueInvite(invite.venueId),
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${invite.venueName} convidou você para a equipe (${invite.roleLabel}).',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'O convite fica pendente até você aceitar. Só então a casa conta você na equipe.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: AppKeys.venueInviteAccept(invite.venueId),
                  onPressed: _busy ? null : () => _run(widget.onAccept),
                  child: const Text('Aceitar'),
                ),
                TextButton(
                  key: AppKeys.venueInviteDecline(invite.venueId),
                  onPressed: _busy ? null : () => _run(widget.onDecline),
                  child: const Text('Recusar'),
                ),
              ],
            ),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    );
  }
}
