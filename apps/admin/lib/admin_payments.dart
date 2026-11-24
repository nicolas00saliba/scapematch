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
  PlatformCacReport? _cac;
  PagbankSignupSettings? _signup;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(adminApiProvider);
      final now = DateTime.now();
      final board = await api.payments();
      final cac = await api.platformCac(
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month + 1, 0),
      );
      final signup = await api.pagbankSignupSettings();
      if (!mounted) return;
      setState(() {
        _board = board;
        _cac = cac;
        _signup = signup;
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
              ? 'A flag do banco liga, mas o código continua sem transferir. O valor fica disponível na conta PagBank da casa.'
              : 'O cron deixa de criar saques. O valor fica disponível na conta PagBank da casa.',
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

  Future<void> _disableSignup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desligar o cadastro pela API'),
        content: const Text(
          'O Parceiro volta a orientar a página oficial do PagBank. A checagem não liga de novo até você religar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('admin-pagbank-signup-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desligar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).disablePagbankSignup();
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _releaseSignup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Religar o cadastro pela API'),
        content: const Text(
          'O Parceiro volta a enviar o cadastro pelo servidor. A casa que já tem conta segue para o Connect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('admin-pagbank-signup-release-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Religar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminApiProvider).releasePagbankSignupHold();
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
            const Text(
              'O saque pelo EscapeMatch está desligado no código. O valor fica disponível na conta PagBank da casa.',
            ),
            const SizedBox(height: 8),
            const Text('Cadastro de contas no PagBank'),
            const SizedBox(height: 8),
            Text(_signupLine(_signup)),
            if (_signup?.apiEnabled == true)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const Key('admin-pagbank-signup-off'),
                  onPressed: _saving ? null : _disableSignup,
                  child: const Text('Desligar'),
                ),
              ),
            if (_signup?.heldOff == true && _signup?.apiEnabled != true)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const Key('admin-pagbank-signup-release'),
                  onPressed: _saving ? null : _releaseSignup,
                  child: const Text('Religar'),
                ),
              ),
            const SizedBox(height: 8),
            const Text('Prontidão'),
            const SizedBox(height: 8),
            _HealthRow('Chave da API do PagBank', _yn(board.pagbankToken)),
            _HealthRow(
              'URL do PagBank em produção',
              _yn(board.pagbankBaseUrlProduction),
            ),
            _HealthRow('Token do webhook', _yn(board.pagbankWebhookSecret)),
            _HealthRow('E-mail do webhook', _yn(board.pagbankWebhookEmail)),
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
            _CacReport(report: _cac),
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

String _signupLine(PagbankSignupSettings? signup) {
  if (signup == null) return 'Carregando o cadastro.';
  if (signup.apiEnabled) {
    return 'Ligada. O Parceiro envia o cadastro pelo servidor.';
  }
  if (signup.heldOff) {
    return 'Desligada pelo admin. Religar devolve o envio pelo servidor.';
  }
  final probe = signup.lastProbeCode.isEmpty ? '' : ' Última checagem: ${signup.lastProbeCode}.';
  return 'Desligada. A casa cria a conta na página do PagBank.$probe';
}

String _yn(bool? value) {
  return switch (value) {
    true => 'sim',
    false => 'não',
    null => 'sem leitura',
  };
}

class _CacReport extends StatelessWidget {
  const _CacReport({required this.report});

  final PlatformCacReport? report;

  @override
  Widget build(BuildContext context) {
    final data = report;
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('CAC assumido no mês: ${reais(data.assumedCents)}'),
        Text('Pago pela conta da EscapeMatch: ${reais(data.paidCents)}'),
        Text('Pendente: ${reais(data.pendingCents)}'),
        Text('Falhou: ${reais(data.failedCents)}'),
        if (data.alerts.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Alerta de CAC'),
          for (final alert in data.alerts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${alert.venueName} · ${reais(alert.amountCents)}'),
              subtitle: Text(
                '${alert.status} · ${alert.lastError.isEmpty ? 'sem detalhe' : alert.lastError} · tentativa ${alert.attempts}',
              ),
            ),
        ],
      ],
    );
  }
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
