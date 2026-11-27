import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_venue_choice.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_units_screen.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_venue_screen.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

const _addUnit = '__cadastrar_unidade__';
const _manageUnits = '__gerenciar_unidades__';

/// Troca a unidade aberta e cadastra outra, no mesmo login.
///
/// Cada unidade continua com o próprio cadastro, documento, salas, agenda e
/// conta de recebimento. O seletor só escolhe qual o painel mostra.
class PartnerVenueSwitcher extends ConsumerWidget {
  const PartnerVenueSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(partnerSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      key: PartnerKeys.partnerVenueSwitcher,
      tooltip: PartnerMessages.unitsTooltip,
      icon: const Icon(Icons.storefront_outlined),
      onSelected: (value) {
        if (value == _manageUnits) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PartnerUnitsScreen()),
          );
          return;
        }
        if (value == _addUnit) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PartnerVenueScreen(addingUnit: true),
            ),
          );
          return;
        }
        ref.read(partnerSessionProvider.notifier).openVenue(value);
      },
      itemBuilder: (context) => [
        for (final venue in session.venues)
          PopupMenuItem<String>(
            key: PartnerKeys.partnerOpenUnit(venue.id),
            value: venue.id,
            child: Row(
              children: [
                Icon(
                  venue.id == session.houseId
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 18,
                  color: venue.id == session.houseId
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _label(venue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (session.venues.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: PartnerKeys.partnerManageUnits,
          value: _manageUnits,
          child: Row(
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  PartnerMessages.manageUnits,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          key: PartnerKeys.partnerAddUnit,
          value: _addUnit,
          child: Row(
            children: [
              Icon(Icons.add_business_outlined, size: 18),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  PartnerMessages.addUnit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _label(PartnerVenueOption venue) {
  final status = partnerVenueStatusLabel(venue.status);
  return status == null ? venue.name : '${venue.name} ($status)';
}
