import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Data e hora exatas de um horário novo, no fuso da casa.
///
/// Hoje a casa está em Curitiba (`America/Sao_Paulo`). A hora escolhida
/// é a hora de parede dessa região, não a do aparelho.
Future<DateTime?> showNewSlotSheet(
  BuildContext context, {
  required DateTime now,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => NewSlotSheet(now: now),
  );
}

class NewSlotSheet extends StatefulWidget {
  const NewSlotSheet({super.key, required this.now, this.initial});

  final DateTime now;

  /// Hora de parede inicial. Sem valor, o padrão é amanhã às 19:00.
  final DateTime? initial;

  @override
  State<NewSlotSheet> createState() => _NewSlotSheetState();
}

class _NewSlotSheetState extends State<NewSlotSheet> {
  late DateTime _day;
  late TimeOfDay _time;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seed =
        widget.initial ??
        DateTime(
          widget.now.year,
          widget.now.month,
          widget.now.day,
          19,
        ).add(const Duration(days: 1));
    _day = DateTime(seed.year, seed.month, seed.day);
    _time = TimeOfDay(hour: seed.hour, minute: seed.minute);
  }

  DateTime get _startsAt {
    return DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(widget.now.year, widget.now.month, widget.now.day),
      lastDate: widget.now.add(const Duration(days: 365)),
      helpText: 'Data do horário',
    );
    if (picked == null) return;
    setState(() {
      _day = DateTime(picked.year, picked.month, picked.day);
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Hora do horário',
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      _error = null;
    });
  }

  void _save() {
    final startsAt = _startsAt;
    if (!startsAt.isAfter(widget.now)) {
      setState(() => _error = 'Esse horário já passou.');
      return;
    }
    Navigator.pop(context, startsAt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayLabel = DateFormat('EEE, d MMM y', 'pt_BR').format(_day);
    final timeLabel =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    return AlertDialog(
      key: PartnerKeys.newSlotSheet,
      title: const Text(PartnerMessages.addSlot),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Horário de Curitiba. Entra no app do jogador na hora.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: PartnerKeys.newSlotDate,
            onPressed: _pickDay,
            child: Text(dayLabel),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: PartnerKeys.newSlotTime,
            onPressed: _pickTime,
            child: Text(timeLabel),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(PartnerMessages.removeSlotCancel),
        ),
        FilledButton(
          key: PartnerKeys.newSlotSave,
          onPressed: _save,
          child: const Text('Abrir horário'),
        ),
      ],
    );
  }
}
