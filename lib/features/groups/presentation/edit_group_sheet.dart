import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/group_detail_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';

/// Lets the creator change the desired size and the note.
Future<void> showEditGroupSheet(BuildContext context, {required Group group}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _EditGroupSheet(group: group),
  );
}

class _EditGroupSheet extends ConsumerStatefulWidget {
  const _EditGroupSheet({required this.group});

  final Group group;

  @override
  ConsumerState<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends ConsumerState<_EditGroupSheet> {
  late int _totalSpots;
  late final TextEditingController _note;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _totalSpots = widget.group.totalSpots;
    _note = TextEditingController(text: widget.group.note);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occupied = widget.group.occupiedSpots;
    final minimum = math.max(
      GroupRules.minimumTotalSpots(occupiedSpots: occupied),
      widget.group.minimumSpots,
    );
    final maximum = widget.group.roomCapacity;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Editar grupo',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'O grupo pode ter de $minimum a $maximum pessoas. Não dá para ficar abaixo de quem já entrou.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                key: AppKeys.editSpotsDecrement,
                onPressed: _totalSpots > minimum
                    ? () => setState(() => _totalSpots -= 1)
                    : null,
                icon: const Icon(Icons.remove),
                tooltip: 'Diminuir vagas',
              ),
              Text(
                '$_totalSpots',
                key: AppKeys.editSpotsValue,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                key: AppKeys.editSpotsIncrement,
                onPressed: _totalSpots < maximum
                    ? () => setState(() => _totalSpots += 1)
                    : null,
                icon: const Icon(Icons.add),
                tooltip: 'Aumentar vagas',
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('pessoas no grupo')),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: AppKeys.editNote,
            controller: _note,
            maxLength: GroupRules.maxNoteLength,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [
              LengthLimitingTextInputFormatter(GroupRules.maxNoteLength),
            ],
            decoration: const InputDecoration(
              labelText: 'Observação',
              hintText: 'Algo que o grupo precise saber',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: AppKeys.editError,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: AppKeys.editSave,
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final reason = await ref
          .read(groupDetailViewModelProvider(widget.group.id).notifier)
          .edit(totalSpots: _totalSpots, note: _note.text);
      if (!mounted) {
        return;
      }
      if (reason != null) {
        setState(() => _error = GroupMessages.editFailure(reason));
        return;
      }
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = GroupMessages.actionFailed);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
