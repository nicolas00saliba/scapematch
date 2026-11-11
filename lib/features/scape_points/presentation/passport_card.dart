import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/features/scape_points/domain/passport_book.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';

const _stampColors = <Color>[
  Color(0xFF0F6E6E),
  Color(0xFFB45309),
  Color(0xFF6D28D9),
  Color(0xFFB91C1C),
  Color(0xFF1D4ED8),
  Color(0xFF047857),
];

/// Passaporte na aba de recompensas. Cada sala ganha um carimbo
/// com cor própria. Jogar de novo aumenta a visita, sem segundo carimbo.
class PassportCard extends StatelessWidget {
  const PassportCard({super.key, required this.book});

  final PassportBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const Key('passport-card'),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passaporte de salas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (!book.enabled)
              const Text(
                'O passaporte de salas ainda não está aberto.',
                key: Key('passport-closed'),
              )
            else ...[
              Text(
                book.distinctRooms == 1
                    ? '1 sala carimbada.'
                    : '${book.distinctRooms} salas carimbadas.',
              ),
              if (book.nextRooms != null &&
                  book.nextPoints != null &&
                  book.nextRooms! > book.distinctRooms) ...[
                const SizedBox(height: 4),
                Text(
                  'Faltam ${book.nextRooms! - book.distinctRooms} salas para ${formatPoints(book.nextPoints!)} pontos.',
                  key: const Key('passport-next'),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Os pontos do passaporte são promoção: viram desconto na sua parte, até o teto do resgate. Não pagam a vaga inteira.',
              ),
              const SizedBox(height: 12),
              if (book.stamps.isEmpty)
                const Text('O primeiro carimbo entra quando a reserva paga termina.')
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < book.stamps.length; i++)
                      _Stamp(stamp: book.stamps[i], color: _stampColors[i % _stampColors.length]),
                  ],
                ),
              const SizedBox(height: 16),
              Text(
                'Marcos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final milestone in book.milestones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _milestoneLine(milestone),
                    key: Key('passport-milestone-${milestone.key}'),
                  ),
                ),
              if (book.gifts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Mimos da casa',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final gift in book.gifts) _GiftRow(gift: gift),
              ],
              if (book.isSample) ...[
                const SizedBox(height: 8),
                Text(
                  'Exemplo de passaporte. Estes carimbos não são seus.',
                  key: const Key('passport-sample'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _milestoneLine(PassportMilestoneView milestone) {
  final state = milestone.reached ? 'conquistado' : 'em aberto';
  if (milestone.house) {
    return 'Casa fechada · ${formatPoints(milestone.points)} pontos · $state';
  }
  final rooms = milestone.rooms ?? 0;
  return '$rooms salas · ${formatPoints(milestone.points)} pontos · $state';
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.stamp, required this.color});

  final PassportStampView stamp;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final letter = stamp.roomName.isEmpty
        ? '?'
        : stamp.roomName.substring(0, 1).toUpperCase();
    return SizedBox(
      width: 132,
      child: Column(
        children: [
          Container(
            key: Key('passport-stamp-${stamp.roomId}'),
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
            ),
            child: Text(
              letter,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stamp.roomName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            stamp.venueName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(stamp.visits, key: Key('passport-visits-${stamp.roomId}')),
        ],
      ),
    );
  }
}

class _GiftRow extends StatelessWidget {
  const _GiftRow({required this.gift});

  final PassportGiftView gift;

  @override
  Widget build(BuildContext context) {
    final where = gift.roomName == null
        ? gift.venueName
        : '${gift.roomName} · ${gift.venueName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(gift.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(where),
          if (gift.details.isNotEmpty) Text(gift.details),
          if (gift.delivered)
            const Text('Entregue na casa.')
          else
            Row(
              children: [
                Text('Código ${gift.code}', key: Key('passport-code-${gift.code}')),
                IconButton(
                  tooltip: 'Copiar código',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: gift.code));
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
