import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_pages.dart';

class PagamentosPage extends ConsumerStatefulWidget {
  const PagamentosPage({super.key});

  @override
  ConsumerState<PagamentosPage> createState() => _PagamentosPageState();
}

class _PagamentosPageState extends ConsumerState<PagamentosPage> {
  PaymentsBoard? _board;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final board = await ref.read(adminApiProvider).payments();
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

  Future<void> _toggle(bool next) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(next ? 'Ligar saques automáticos' : 'Desligar saques automáticos'),
        content: Text(
          next
              ? 'O cron passa a pedir saque das casas com saldo. A mudança fica na auditoria.'
              : 'O cron deixa de criar saques. Os que já saíram não voltam. A mudança fica na auditoria.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('admin-payouts-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).setVenuePayoutsEnabled(next);
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return AdminFrame(
      key: const Key('admin-pagamentos'),
      title: 'Pagamentos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) Text(_error!),
          if (board == null)
            const Text('Carregando pagamentos.')
          else ...[
            SwitchListTile(
              key: const Key('admin-payouts-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Saques automáticos'),
              subtitle: Text(board.payoutsEnabled ? 'Ligados' : 'Desligados'),
              value: board.payoutsEnabled,
              onChanged: _saving ? null : _toggle,
            ),
            const SizedBox(height: 8),
            const Text('Prontidão'),
            const SizedBox(height: 8),
            _HealthRow('Chave da API do Asaas', _yn(board.asaasApiKey)),
            _HealthRow(
              'URL do Asaas em produção',
              _yn(board.asaasBaseUrlProduction),
            ),
            _HealthRow('Token do webhook', _yn(board.asaasWebhookToken)),
            _HealthRow('E-mail do webhook', _yn(board.asaasWebhookEmail)),
            _HealthRow(
              'Segredo do cron de saques',
              _yn(board.venueWithdrawalsSecret),
            ),
            _HealthRow('Vault da URL de saques', _yn(board.vaultUrl)),
            _HealthRow('Vault do segredo de saques', _yn(board.vaultSecret)),
            _HealthRow(
              'Última execução do cron',
              board.cronLastFailed == null
                  ? 'sem leitura'
                  : board.cronLastFailed!
                  ? 'falhou${board.cronFailureCode == null || board.cronFailureCode!.isEmpty ? '' : ' · ${board.cronFailureCode}'}'
                  : 'ok',
            ),
            const SizedBox(height: 16),
            _Lines(title: 'Cobranças', rows: board.charges, empty: 'Nenhuma cobrança recente.'),
            _Lines(title: 'Estornos', rows: board.refunds, empty: 'Nenhum estorno recente.'),
            _Lines(title: 'Saques', rows: board.withdrawals, empty: 'Nenhum saque recente.'),
            const SizedBox(height: 16),
            const Text('Erros do webhook'),
            const SizedBox(height: 8),
            if (board.webhookErrors.isEmpty)
              const Text('Nenhum erro recente.')
            else
              for (final row in board.webhookErrors)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row.source} · ${row.code}'),
                  subtitle: Text(
                    '${whenLabel(row.when)}${row.providerRef.isEmpty ? '' : ' · ${row.providerRef}'}',
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

String _yn(bool? value) {
  return switch (value) {
    true => 'sim',
    false => 'não',
    null => 'sem leitura',
  };
}

class _HealthRow extends StatelessWidget {
  const _HealthRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: $value'),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.title,
    required this.rows,
    required this.empty,
  });

  final String title;
  final List<PaymentLine> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(title),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text(empty)
        else
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row.title),
              subtitle: Text('${row.detail} · ${whenLabel(row.when)}'),
            ),
      ],
    );
  }
}
