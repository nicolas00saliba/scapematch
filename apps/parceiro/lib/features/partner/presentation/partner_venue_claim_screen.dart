import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_registry.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_board.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerVenueClaimScreen extends ConsumerStatefulWidget {
  const PartnerVenueClaimScreen({
    super.key,
    required this.venueId,
    required this.venueName,
    this.ownerId = venueSignupOwnerId,
    this.pendingVenueId,
  });

  final String venueId;
  final String venueName;
  final String ownerId;
  final String? pendingVenueId;

  @override
  ConsumerState<PartnerVenueClaimScreen> createState() =>
      _PartnerVenueClaimScreenState();
}

class _PartnerVenueClaimScreenState
    extends ConsumerState<PartnerVenueClaimScreen> {
  final _note = TextEditingController();
  String? _error;
  var _sent = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      ref
          .read(venueRegistryProvider.notifier)
          .claim(
            venueId: widget.venueId,
            claimantId: widget.ownerId,
            note: _note.text,
            pendingVenueId: widget.pendingVenueId,
          );
      setState(() {
        _sent = true;
        _error = null;
      });
    } on VenueClaimProblem catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      appBar: AppBar(title: const Text(PartnerMessages.claimTitle)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 880 : 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                wide ? 8 : 16,
                12,
                wide ? 8 : 16,
                28,
              ),
              children: [
                Text(
                  widget.venueName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  PartnerMessages.claimBody,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
                const SizedBox(height: 16),
                if (_sent)
                  Material(
                    key: PartnerKeys.venueClaimSent,
                    color: ScapeStatusColors.of(context).successContainer,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        PartnerMessages.claimSent,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: ScapeStatusColors.of(context)
                              .onSuccessContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    key: PartnerKeys.venueClaimNote,
                    controller: _note,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: PartnerMessages.claimNote,
                      hintText: PartnerMessages.claimNoteHint,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton(
                    key: PartnerKeys.venueClaimSubmit,
                    onPressed: _submit,
                    child: const Text(PartnerMessages.sendClaim),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
