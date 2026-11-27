import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch_parceiro/features/partner/data/partner_units_repository.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Unidades do login: abrir, cadastrar outra e remover.
///
/// Cada unidade tem cidade, salas, agenda e conta de recebimento próprias. No
/// app do jogador, ela aparece na cidade dela, com as salas dela.
class PartnerUnitsScreen extends ConsumerStatefulWidget {
  const PartnerUnitsScreen({super.key});

  @override
  ConsumerState<PartnerUnitsScreen> createState() => _PartnerUnitsScreenState();
}

class _PartnerUnitsScreenState extends ConsumerState<PartnerUnitsScreen> {
  String? _busyId;

  Future<void> _remove(PartnerVenueOption venue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(PartnerMessages.removeUnitTitle(venue.name)),
        content: Text(PartnerMessages.removeUnitBody(venue.cityName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(PartnerMessages.cancel),
          ),
          FilledButton(
            key: PartnerKeys.partnerConfirmRemoveUnit,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(PartnerMessages.removeUnit),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = venue.id);
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(partnerSessionProvider.notifier);
    final error = await ref
        .read(partnerUnitsRepositoryProvider)
        .deactivate(venue.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? PartnerUnitMessages.removed)),
    );
    if (error == null) await session.reload();
  }

  Future<void> _reactivate(PartnerVenueOption venue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(PartnerUnitMessages.reactivateConfirmTitle),
        content: const Text(PartnerUnitMessages.reactivateConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(PartnerMessages.cancel),
          ),
          FilledButton(
            key: PartnerKeys.partnerConfirmReactivateUnit,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(PartnerUnitMessages.reactivate),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = venue.id);
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(partnerSessionProvider.notifier);
    final error = await ref
        .read(partnerUnitsRepositoryProvider)
        .reactivate(venue.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? PartnerUnitMessages.reactivated)),
    );
    if (error == null) await session.reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(partnerSessionProvider);
    final venues = session?.venues ?? const <PartnerVenueOption>[];
    final removed = session?.removedVenues ?? const <PartnerVenueOption>[];
    final theme = Theme.of(context);
    final canRemove = venues.length > 1;
    return AppScaffold(
      desktopMaxWidth: 640,
      appBar: AppBar(title: const Text(PartnerMessages.unitsTitle)),
      body: ListView(
        key: PartnerKeys.partnerUnitsScreen,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            PartnerMessages.unitsIntro,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final venue in venues)
            Card(
              child: ListTile(
                title: Text(venue.cityName ?? venue.name),
                subtitle: Text(_subtitle(venue)),
                selected: venue.id == session?.houseId,
                onTap: venue.id == session?.houseId
                    ? null
                    : () {
                        ref
                            .read(partnerSessionProvider.notifier)
                            .openVenue(venue.id);
                        Navigator.of(context).pop();
                      },
                trailing: !canRemove
                    ? null
                    : _busyId == venue.id
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        key: PartnerKeys.partnerRemoveUnit(venue.id),
                        tooltip: PartnerMessages.removeUnit,
                        onPressed: _busyId == null
                            ? () => _remove(venue)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: PartnerKeys.partnerAddUnit,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PartnerVenueScreen(addingUnit: true),
              ),
            ),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text(PartnerMessages.addUnit),
          ),
          if (!canRemove) ...[
            const SizedBox(height: 12),
            Text(
              PartnerMessages.unitsSingleHint,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              PartnerUnitMessages.removedTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              PartnerUnitMessages.removedHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final venue in removed)
              Card(
                child: ListTile(
                  title: Text(venue.cityName ?? venue.name),
                  subtitle: Text(_subtitle(venue)),
                  trailing: _busyId == venue.id
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          key: PartnerKeys.partnerReactivateUnit(venue.id),
                          onPressed: _busyId == null
                              ? () => _reactivate(venue)
                              : null,
                          child: const Text(PartnerUnitMessages.reactivate),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _subtitle(PartnerVenueOption venue) {
  final parts = [
    if (venue.cityName != null) venue.name,
    if (partnerVenueStatusLabel(venue.status) != null)
      partnerVenueStatusLabel(venue.status)!,
  ];
  return parts.isEmpty ? '' : parts.join(' · ');
}
