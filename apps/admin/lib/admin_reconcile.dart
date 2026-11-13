import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_pages.dart';

class ConciliacaoPage extends ConsumerStatefulWidget {
  const ConciliacaoPage({super.key});

  @override
  ConsumerState<ConciliacaoPage> createState() => _ConciliacaoPageState();
}

class _ConciliacaoPageState extends ConsumerState<ConciliacaoPage> {
  DivergenceBoard? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final board = await ref.read(adminApiProvider).divergences();
      if (!mounted) return;
      setState(() {
        _board = board;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return AdminFrame(
      key: const Key('admin-conciliacao'),
      title: 'Conciliação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Comparação diária das cobranças e transferências do Asaas com o livro. Só leitura.',
          ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!),
          if (board == null)
            const Text('Carregando conciliação.')
          else if (board.startedAt == null)
            const Text('Nenhuma conciliação rodou ainda.')
          else ...[
            Text(
              '${whenLabel(board.startedAt)} · ${board.paymentCount} cobranças · ${board.transferCount} transferências · ${board.divergenceCount} divergências',
            ),
            if (board.truncated)
              const Text('A lista do Asaas veio incompleta. Ausências não foram marcadas.'),
            const SizedBox(height: 12),
            if (board.rows.isEmpty)
              const Text('Nenhuma divergência nesta execução.')
            else
              for (final row in board.rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_kindLabel(row.kind)),
                  subtitle: Text(_detail(row)),
                ),
          ],
        ],
      ),
    );
  }
}

String _kindLabel(String kind) {
  return switch (kind) {
    'charge_missing_local' => 'Cobrança no Asaas sem livro',
    'charge_missing_asaas' => 'Cobrança no livro sem Asaas',
    'charge_status' => 'Status da cobrança diferente',
    'charge_amount' => 'Valor da cobrança diferente',
    'ledger_missing' => 'Cobrança paga sem lançamento',
    'ledger_refund_missing' => 'Estorno sem lançamento',
    'transfer_missing_local' => 'Transferência no Asaas sem saque',
    'transfer_missing_asaas' => 'Saque sem transferência no Asaas',
    'transfer_status' => 'Status do saque diferente',
    'transfer_amount' => 'Valor do saque diferente',
    'asaas_truncated' => 'A lista do Asaas veio incompleta',
    _ => kind,
  };
}

String _detail(DivergenceRow row) {
  final parts = <String>[
    if (row.providerRef.isNotEmpty) row.providerRef,
    if (row.expected.isNotEmpty || row.actual.isNotEmpty)
      '${row.expected} → ${row.actual}',
    whenLabel(row.when),
  ];
  return parts.join(' · ');
}
