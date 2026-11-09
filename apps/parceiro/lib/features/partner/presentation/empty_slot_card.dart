import 'package:flutter/material.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Faixas em que a casa dobra o cashback. Sem a faixa, nada sai do repasse.
class EmptySlotCard extends StatefulWidget {
  const EmptySlotCard({super.key, required this.venueId});

  final String venueId;

  @override
  State<EmptySlotCard> createState() => _EmptySlotCardState();
}

class _EmptySlotCardState extends State<EmptySlotCard> {
  final _start = TextEditingController(text: '10:00');
  final _end = TextEditingController(text: '14:00');
  int _weekday = 2;
  var _saved = false;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!scapeUsesLiveBackend) {
      setState(() => _saved = true);
      return;
    }
    final start = _minutes(_start.text);
    final end = _minutes(_end.text);
    if (start == null || end == null || end <= start) return;
    await scapeSupabase.rpc(
      'upsert_venue_empty_slot',
      params: {
        'p_venue_id': widget.venueId,
        'p_weekday': _weekday,
        'p_starts_minute': start,
        'p_ends_minute': end,
      },
    );
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: PartnerKeys.emptySlot,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horário vazio',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Opt-in. Nessas faixas o cashback do jogador dobra e a parte extra pode sair do seu repasse.',
        ),
        const SizedBox(height: 8),
        DropdownButton<int>(
          value: _weekday,
          items: const [
            DropdownMenuItem(value: 1, child: Text('Segunda')),
            DropdownMenuItem(value: 2, child: Text('Terça')),
            DropdownMenuItem(value: 3, child: Text('Quarta')),
            DropdownMenuItem(value: 4, child: Text('Quinta')),
            DropdownMenuItem(value: 5, child: Text('Sexta')),
            DropdownMenuItem(value: 6, child: Text('Sábado')),
            DropdownMenuItem(value: 7, child: Text('Domingo')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _weekday = value);
          },
        ),
        TextField(
          controller: _start,
          decoration: const InputDecoration(labelText: 'Começa'),
        ),
        TextField(
          controller: _end,
          decoration: const InputDecoration(labelText: 'Termina'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _save, child: const Text('Marcar faixa')),
        if (_saved)
          const Text('Faixa marcada. Só vale enquanto estiver ativa.'),
      ],
    );
  }
}

int? _minutes(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}
