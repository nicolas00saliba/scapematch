import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_registry.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_board.dart';
import 'package:scapematch_parceiro/features/partner/domain/venue_duplicate.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerVenueApprovalScreen extends ConsumerStatefulWidget {
  const PartnerVenueApprovalScreen({super.key});

  @override
  ConsumerState<PartnerVenueApprovalScreen> createState() =>
      _PartnerVenueApprovalScreenState();
}

class _PartnerVenueApprovalScreenState
    extends ConsumerState<PartnerVenueApprovalScreen> {
  String? _selectedId;
  String? _mergeTarget;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(venueRegistryProvider);
    final pending = board.pendingVenues;
    final selected = _selected(pending);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final theme = Theme.of(context);
    return Scaffold(
      key: PartnerKeys.venueApproval,
      appBar: AppBar(
        title: const Text(PartnerMessages.adminQueue),
        actions: [
          TextButton(
            key: PartnerKeys.partnerSignOut,
            onPressed: () =>
                ref.read(partnerSessionProvider.notifier).signOut(),
            child: const Text(PartnerMessages.signOut),
          ),
        ],
      ),
      body: SafeArea(
        child: pending.isEmpty
            ? ListView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 28 : 16,
                  24,
                  wide ? 28 : 16,
                  28,
                ),
                children: [
                  Text(
                    PartnerMessages.noPendingVenues,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final claim in board.claims.where(
                    (claim) => claim.status == 'pending',
                  ))
                    Text(claim.note),
                ],
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 28 : 16,
                  8,
                  wide ? 28 : 16,
                  28,
                ),
                children: [
                  Text(
                    PartnerMessages.approvalIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  if (selected == null)
                    const SizedBox.shrink()
                  else
                    _Review(
                      board: board,
                      pending: selected,
                      wide: wide,
                      mergeTarget: _mergeTarget ?? selected.possibleDuplicateOf,
                      onMergeTarget: (id) => setState(() => _mergeTarget = id),
                      onApprove: () => _review(selected.id, 'approved'),
                      onReject: () => _review(selected.id, 'rejected'),
                      onMerge: () => _review(
                        selected.id,
                        'merged',
                        _mergeTarget ?? selected.possibleDuplicateOf,
                      ),
                      onApproveClaim: (id) => _reviewClaim(id, 'approved'),
                      onRejectClaim: (id) => _reviewClaim(id, 'rejected'),
                    ),
                ],
              ),
      ),
    );
  }

  VenueRecord? _selected(List<VenueRecord> pending) {
    for (final venue in pending) {
      if (venue.id == _selectedId) {
        return venue;
      }
    }
    return pending.isEmpty ? null : pending.first;
  }

  void _review(String venueId, String decision, [String? mergeInto]) {
    ref
        .read(venueRegistryProvider.notifier)
        .reviewVenue(
          venueId: venueId,
          decision: decision,
          mergeInto: mergeInto,
        );
    setState(() => _selectedId = null);
  }

  void _reviewClaim(String claimId, String decision) {
    ref
        .read(venueRegistryProvider.notifier)
        .reviewClaim(claimId: claimId, decision: decision);
  }
}

class _Review extends StatelessWidget {
  const _Review({
    required this.board,
    required this.pending,
    required this.wide,
    required this.mergeTarget,
    required this.onMergeTarget,
    required this.onApprove,
    required this.onReject,
    required this.onMerge,
    required this.onApproveClaim,
    required this.onRejectClaim,
  });

  final VenueBoard board;
  final VenueRecord pending;
  final bool wide;
  final String? mergeTarget;
  final ValueChanged<String> onMergeTarget;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onMerge;
  final ValueChanged<String> onApproveClaim;
  final ValueChanged<String> onRejectClaim;

  @override
  Widget build(BuildContext context) {
    final draft = VenueDraft(
      ownerId: pending.ownerId,
      name: pending.name,
      cityId: pending.cityId,
      postalCode: pending.postalCode,
      addressNumber: pending.addressNumber,
      document: pending.documentNumber,
    );
    final conflicts = board
        .check(draft, exceptVenueId: pending.id)
        .where((conflict) => conflict.venueId != null)
        .toList();
    final grouped = <String, List<VenueConflict>>{};
    for (final conflict in conflicts) {
      grouped.putIfAbsent(conflict.venueId!, () => []).add(conflict);
    }
    final claims = board.claims
        .where(
          (claim) =>
              claim.pendingVenueId == pending.id ||
              grouped.containsKey(claim.venueId),
        )
        .toList();
    final pendingCard = _PendingCard(venue: pending, board: board);
    final side = _SideColumn(
      board: board,
      grouped: grouped,
      claims: claims,
      mergeTarget: mergeTarget,
      onMergeTarget: onMergeTarget,
      onApproveClaim: onApproveClaim,
      onRejectClaim: onRejectClaim,
    );
    final actions = _Actions(
      wide: wide,
      canMerge: mergeTarget != null && grouped.containsKey(mergeTarget),
      onApprove: onApprove,
      onReject: onReject,
      onMerge: onMerge,
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pendingCard,
          const SizedBox(height: 12),
          side,
          const SizedBox(height: 16),
          actions,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pendingCard),
            const SizedBox(width: 20),
            Expanded(child: side),
          ],
        ),
        const SizedBox(height: 16),
        actions,
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.venue, required this.board});

  final VenueRecord venue;
  final VenueBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linked = venue.possibleDuplicateOf == null
        ? null
        : board.venueById(venue.possibleDuplicateOf!);
    return Card(
      key: PartnerKeys.venuePending,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              PartnerMessages.pendingVenue,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              venue.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(_place(venue), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '${PartnerMessages.documentLabel} ${formatVenueDocument(venue.documentDigits)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (linked != null) ...[
              const SizedBox(height: 10),
              Text(
                '${PartnerMessages.possibleDuplicateOf} ${linked.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.board,
    required this.grouped,
    required this.claims,
    required this.mergeTarget,
    required this.onMergeTarget,
    required this.onApproveClaim,
    required this.onRejectClaim,
  });

  final VenueBoard board;
  final Map<String, List<VenueConflict>> grouped;
  final List<VenueClaim> claims;
  final String? mergeTarget;
  final ValueChanged<String> onMergeTarget;
  final ValueChanged<String> onApproveClaim;
  final ValueChanged<String> onRejectClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: PartnerKeys.venueSimilar,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PartnerMessages.similarVenues,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (grouped.isEmpty)
                  Text(PartnerMessages.noSimilarVenues)
                else
                  for (final entry in grouped.entries)
                    _SimilarTile(
                      venue: board.venueById(entry.key),
                      conflicts: entry.value,
                      selected: mergeTarget == entry.key,
                      onTap: () => onMergeTarget(entry.key),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PartnerMessages.claimsTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (claims.isEmpty)
                  const Text(PartnerMessages.noClaims)
                else
                  for (final claim in claims)
                    _ClaimTile(
                      claim: claim,
                      onApprove: () => onApproveClaim(claim.id),
                      onReject: () => onRejectClaim(claim.id),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SimilarTile extends StatelessWidget {
  const _SimilarTile({
    required this.venue,
    required this.conflicts,
    required this.selected,
    required this.onTap,
  });

  final VenueRecord? venue;
  final List<VenueConflict> conflicts;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final house = venue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  house?.name ?? 'Casa aprovada',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (house != null) ...[
                  const SizedBox(height: 4),
                  Text(_place(house), style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final conflict in conflicts)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(conflict.type),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.onApprove,
    required this.onReject,
  });

  final VenueClaim claim;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = claim.status == 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            claim.note.isEmpty ? 'Pedido sem nota.' : claim.note,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(_claimStatus(claim.status), style: theme.textTheme.labelLarge),
          if (pending)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: PartnerKeys.venueApproveClaim,
                  onPressed: onApprove,
                  child: const Text(PartnerMessages.approveClaim),
                ),
                TextButton(
                  key: PartnerKeys.venueRejectClaim,
                  onPressed: onReject,
                  child: const Text(PartnerMessages.rejectClaim),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.wide,
    required this.canMerge,
    required this.onApprove,
    required this.onReject,
    required this.onMerge,
  });

  final bool wide;
  final bool canMerge;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final approve = FilledButton(
      key: PartnerKeys.venueApprove,
      onPressed: onApprove,
      child: const Text(PartnerMessages.approveVenue),
    );
    final reject = OutlinedButton(
      key: PartnerKeys.venueReject,
      onPressed: onReject,
      child: const Text(PartnerMessages.rejectVenue),
    );
    final merge = FilledButton.tonal(
      key: PartnerKeys.venueMerge,
      onPressed: canMerge ? onMerge : null,
      child: const Text(PartnerMessages.mergeVenue),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          approve,
          const SizedBox(height: 8),
          reject,
          const SizedBox(height: 8),
          merge,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: approve),
        const SizedBox(width: 12),
        Expanded(child: reject),
        const SizedBox(width: 12),
        Expanded(child: merge),
      ],
    );
  }
}

String _place(VenueRecord venue) {
  final street = venue.streetAddress.isEmpty
      ? venue.addressNumber
      : '${venue.streetAddress}, ${venue.addressNumber}';
  return '${venueCityLabel(venue.cityId)} · ${venue.neighborhood}\n$street · CEP ${venue.postalDigits}';
}

String _claimStatus(String status) {
  return switch (status) {
    'approved' => 'Aprovada',
    'rejected' => 'Recusada',
    _ => 'Pendente',
  };
}
