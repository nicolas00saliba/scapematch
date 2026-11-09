import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';

/// Saldo e extrato. No modo real lê `my_scape_wallet`. Na demonstração,
/// os números são de exemplo.
class ScapePointsBody extends ConsumerStatefulWidget {
  const ScapePointsBody({super.key, this.preview});

  /// Quando preenchido, a tela não chama o servidor.
  final ScapeWallet? preview;

  @override
  ConsumerState<ScapePointsBody> createState() => _ScapePointsBodyState();
}

class _ScapePointsBodyState extends ConsumerState<ScapePointsBody> {
  ScapeWallet? _wallet;
  var _loading = false;
  String? _error;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.preview != null || !scapeUsesLiveBackend) return;
    _loading = true;
    Future<void>(() async {
      await _load();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await scapeSupabase.rpc('my_scape_wallet');
      if (!mounted) return;
      setState(() {
        _wallet = data is Map
            ? ScapeWallet.fromJson(Map<String, dynamic>.from(data))
            : null;
        _loading = false;
        _error = _wallet == null
            ? 'Não foi possível ler os Scape Points.'
            : null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler os Scape Points.';
      });
    }
  }

  Future<void> _claim() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    try {
      final result = await scapeSupabase.rpc(
        'claim_referral_code',
        params: {'p_code': code},
      );
      if (!mounted) return;
      final message = switch (result) {
        'ok' => 'Código aplicado.',
        'blocked' => 'Este código não pode ser usado nesta conta.',
        'late' => 'O código só entra no cadastro.',
        'exists' => 'Esta conta já tem um código.',
        'self' => 'Use o código de outra pessoa.',
        _ => 'Código não encontrado.',
      };
      setState(() => _error = result == 'ok' ? null : message);
      if (result == 'ok') await _load();
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível aplicar o código.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preview != null) {
      return ScapePointsView(
        wallet: widget.preview!,
        sample: identical(widget.preview, ScapeWallet.sample),
      );
    }
    if (!scapeUsesLiveBackend) {
      return const ScapePointsView(wallet: ScapeWallet.sample, sample: true);
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final wallet = _wallet;
    if (wallet == null) {
      return Text(_error ?? 'Não foi possível ler os Scape Points.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScapePointsView(wallet: wallet, sample: false),
        if (wallet.canClaim) ...[
          const SizedBox(height: 16),
          TextField(
            key: AppKeys.scapeReferralClaim,
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Código de quem indicou',
              helperText: 'Só no cadastro, nas primeiras 24 horas.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _claim,
              child: const Text('Aplicar código'),
            ),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
      ],
    );
  }
}

class ScapePointsView extends StatelessWidget {
  const ScapePointsView({
    super.key,
    required this.wallet,
    required this.sample,
  });

  final ScapeWallet wallet;
  final bool sample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          key: AppKeys.scapePointsBalance,
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
                  'Scape Points',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatPoints(wallet.availablePoints)} disponíveis',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(formatPrice(wallet.availableCents)),
                const SizedBox(height: 8),
                Text('${formatPoints(wallet.pendingPoints)} pontos chegando'),
                const SizedBox(height: 8),
                if (wallet.availablePoints < wallet.redeemMinPoints) ...[
                  LinearProgressIndicator(
                    value: wallet.redeemMinPoints == 0
                        ? 1
                        : wallet.availablePoints / wallet.redeemMinPoints,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Faltam ${formatPoints(wallet.redeemMinPoints - wallet.availablePoints)} pontos pra usar na sua próxima sala.',
                  ),
                ] else
                  const Text('Você já pode usar pontos na próxima sala.'),
                const SizedBox(height: 8),
                Text('Nível ${wallet.tierLabel}. ${wallet.tierProgress}'),
                const SizedBox(height: 8),
                Text(
                  '1 ponto = ${formatPrice(wallet.pointValueCents)}. Não vencem e não sacam. Servem para pagar a sua parte da sala.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (sample) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Números de exemplo. Nada aqui é uma carteira real.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CodeRow(code: wallet.referralCode),
        const SizedBox(height: 16),
        Text(
          'Extrato',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (wallet.entries.isEmpty)
          const Text('Nenhum lançamento ainda.')
        else
          for (final entry in wallet.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.title),
                subtitle: Text(entry.detail),
                trailing: Text(
                  entry.kind == 'release'
                      ? 'liberado'
                      : '${entry.adds ? '+' : '−'}${formatPoints(entry.points)}',
                ),
              ),
            ),
      ],
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final shown = code.isEmpty
        ? 'Seu código aparece depois do cadastro.'
        : code;
    return Row(
      children: [
        Expanded(
          child: Text('Seu código: $shown', key: AppKeys.scapeReferralCode),
        ),
        if (code.isNotEmpty)
          IconButton(
            tooltip: 'Copiar código',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
            },
            icon: const Icon(Icons.copy_outlined),
          ),
      ],
    );
  }
}
