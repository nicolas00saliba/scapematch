import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/data/commission_admin_repository.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Taxa global e por casa. Só quem passa no `private.is_admin` grava.
class CommissionAdminPanel extends ConsumerStatefulWidget {
  const CommissionAdminPanel({super.key});

  @override
  ConsumerState<CommissionAdminPanel> createState() =>
      _CommissionAdminPanelState();
}

class _CommissionAdminPanelState extends ConsumerState<CommissionAdminPanel> {
  List<CommissionRow> _rows = const [];
  final _fields = <String, TextEditingController>{};
  String? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(commissionAdminRepositoryProvider).board();
      if (!mounted) return;
      for (final row in rows) {
        final key = row.venueId ?? '';
        _fields.putIfAbsent(
          key,
          () => TextEditingController(
            text: formatCommissionPercent(row.commissionBps),
          ),
        );
        _fields[key]!.text = formatCommissionPercent(row.commissionBps);
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler a comissão.';
      });
    }
  }

  Future<void> _save(CommissionRow row) async {
    final raw = _fields[row.venueId ?? '']?.text ?? '';
    final bps = parseCommissionPercent(raw);
    if (bps == null) {
      setState(() => _error = 'A comissão fica entre 0 e 30%.');
      return;
    }
    final repo = ref.read(commissionAdminRepositoryProvider);
    final error = row.venueId == null
        ? await repo.setPlatform(bps)
        : await repo.setVenue(row.venueId!, bps);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: PartnerKeys.commissionAdmin,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Comissão EscapeMatch',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Padrão da plataforma e override por casa. De 0 a 30%.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        for (final row in _rows) ...[
          _CommissionField(
            row: row,
            controller: _fields[row.venueId ?? '']!,
            onSave: () => _save(row),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CommissionField extends StatelessWidget {
  const _CommissionField({
    required this.row,
    required this.controller,
    required this.onSave,
  });

  final CommissionRow row;
  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(row.name)),
        SizedBox(
          width: 88,
          child: TextField(
            key: Key('commission-field-${row.venueId ?? 'platform'}'),
            controller: controller,
            keyboardType: TextInputType.text,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: row.venueId == null
              ? PartnerKeys.savePlatformCommission
              : PartnerKeys.saveVenueCommission(row.venueId!),
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: onSave,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
