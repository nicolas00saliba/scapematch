import 'package:flutter/material.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// O horário vazio não dobra mais pontos. A tela só registra isso para a casa.
class EmptySlotCard extends StatelessWidget {
  const EmptySlotCard({super.key, required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.emptySlot,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horário vazio',
          key: ValueKey('empty-slot-$venueId'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Horário vazio não dobra cashback nem indicação. Não há faixa para marcar e nada extra sai do repasse por causa do horário.',
        ),
      ],
    );
  }
}
