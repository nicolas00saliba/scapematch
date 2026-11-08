import 'package:flutter/material.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Passivo de Scape Points: emitidos e ainda não usados.
class ScapeLiabilityPanel extends StatefulWidget {
  const ScapeLiabilityPanel({super.key});

  @override
  State<ScapeLiabilityPanel> createState() => _ScapeLiabilityPanelState();
}

class _ScapeLiabilityPanelState extends State<ScapeLiabilityPanel> {
  ScapeLiability? _liability;
  var _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!scapeUsesLiveBackend) return;
    _loading = true;
    Future<void>(() async {
      try {
        final data = await scapeSupabase.rpc('admin_scape_liability');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _liability = data is Map
              ? ScapeLiability.fromJson(Map<String, dynamic>.from(data))
              : null;
          _error = _liability == null
              ? 'Não foi possível ler o passivo de pontos.'
              : null;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Não foi possível ler o passivo de pontos.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liability = _liability;
    return Column(
      key: PartnerKeys.scapeLiability,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Scape Points',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (!scapeUsesLiveBackend)
          const Text(
            'Nesta demonstração não há pontos emitidos. No app real, o passivo é o total ainda não usado.',
          )
        else if (_loading)
          const LinearProgressIndicator()
        else if (liability == null)
          Text(_error ?? 'Não foi possível ler o passivo de pontos.')
        else ...[
          Text(
            '${formatPoints(liability.unusedPoints)} pontos ainda não usados',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('Passivo ${formatPrice(liability.unusedCents)}.'),
          const SizedBox(height: 4),
          Text(
            '${formatPoints(liability.pendingPoints)} pendentes e ${formatPoints(liability.availablePoints)} disponíveis.',
          ),
          const SizedBox(height: 4),
          Text(
            'Crédito de casa ainda pendente: ${formatPrice(liability.venueCreditPendingCents)}.',
          ),
        ],
      ],
    );
  }
}
