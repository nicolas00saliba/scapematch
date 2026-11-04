import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_palette.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Abre o formulário de sala. Devolve verdadeiro quando a sala foi gravada.
Future<bool?> showPartnerRoomForm(
  BuildContext context, {
  required PartnerSnapshot snapshot,
  EscapeRoom? room,
}) {
  final wide = isScapeDesktop(context);
  final height = MediaQuery.sizeOf(context).height;
  if (wide) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 480,
            height: height > 760 ? 640 : height * 0.86,
            child: PartnerRoomForm(snapshot: snapshot, room: room),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height * 0.92,
          child: PartnerRoomForm(snapshot: snapshot, room: room),
        ),
      );
    },
  );
}

class PartnerRoomForm extends ConsumerStatefulWidget {
  const PartnerRoomForm({super.key, required this.snapshot, this.room});

  final PartnerSnapshot snapshot;
  final EscapeRoom? room;

  @override
  ConsumerState<PartnerRoomForm> createState() => _PartnerRoomFormState();
}

class _PartnerRoomFormState extends ConsumerState<PartnerRoomForm> {
  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _price;
  late Difficulty _difficulty;
  late int _accent;
  String? _error;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room?.name ?? '');
    _duration = TextEditingController(text: '${room?.durationMinutes ?? 60}');
    _minimum = TextEditingController(text: '${room?.minimumPlayers ?? 2}');
    _maximum = TextEditingController(text: '${room?.capacity ?? 6}');
    _price = TextEditingController(text: reaisField(room?.priceCents ?? 10900));
    _difficulty = room?.difficulty ?? Difficulty.medium;
    final index = room == null
        ? widget.snapshot.rooms.length
        : widget.snapshot.rooms.indexWhere((item) => item.id == room.id);
    final paletteIndex = index < 0 ? widget.snapshot.rooms.length : index;
    _accent = room == null || room.accent == 0
        ? agendaPalette[paletteIndex % agendaPalette.length]
        : room.accent;
  }

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final price = parseReais(_price.text);
    if (price == null) {
      setState(() => _error = 'Informe o preço em reais.');
      return;
    }
    final error = ref.read(partnerRepositoryProvider).saveRoom(
      houseId: widget.snapshot.house.id,
      roomId: widget.room?.id,
      name: _name.text,
      difficulty: _difficulty,
      durationMinutes: int.tryParse(_duration.text.trim()) ?? 0,
      minimumPlayers: int.tryParse(_minimum.text.trim()) ?? 0,
      capacity: int.tryParse(_maximum.text.trim()) ?? 0,
      priceCents: price,
      accent: _accent,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.read(partnerRevisionProvider.notifier).bump();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.room == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          creating ? PartnerMessages.newRoom : PartnerMessages.editRoom,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: PartnerKeys.agendaRoomName,
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: PartnerMessages.roomName,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Dificuldade',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final level in Difficulty.values)
              ChoiceChip(
                label: Text(level.labelPt),
                selected: _difficulty == level,
                onSelected: (_) => setState(() => _difficulty = level),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: PartnerMessages.roomDuration,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minimum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: PartnerMessages.roomMinimum,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maximum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: PartnerMessages.roomMaximum,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: PartnerMessages.priceLabel,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.roomColor,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in agendaPalette)
              Tooltip(
                message: PartnerMessages.roomColor,
                child: InkWell(
                  onTap: () => setState(() => _accent = value),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _accent == value
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: PartnerKeys.agendaSaveRoom,
          onPressed: _save,
          child: const Text(PartnerMessages.saveRoom),
        ),
      ],
    );
  }
}
