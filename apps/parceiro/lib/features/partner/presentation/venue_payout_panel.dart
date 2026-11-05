import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_payout_repository.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Status da subconta de cada casa e a nova tentativa de criação.
class VenuePayoutPanel extends ConsumerStatefulWidget {
  const VenuePayoutPanel({super.key});

  @override
  ConsumerState<VenuePayoutPanel> createState() => _VenuePayoutPanelState();
}

class _VenuePayoutPanelState extends ConsumerState<VenuePayoutPanel> {
  List<VenuePayoutStatus> _rows = const [];
  String? _error;
  var _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(venuePayoutRepositoryProvider).list();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível ler as subcontas.';
      });
    }
  }

  Future<void> _retry(String venueId) async {
    setState(() => _busyId = venueId);
    final error = await ref.read(venuePayoutRepositoryProvider).retry(venueId);
    if (!mounted) return;
    setState(() => _busyId = null);
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
      key: PartnerKeys.venuePayouts,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Subcontas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        for (final row in _rows) ...[
          Text(row.name, style: theme.textTheme.titleSmall),
          Text(
            row.receivesPayments
                ? 'Subconta pronta'
                : 'Conta de recebimento pendente',
          ),
          if (row.status == 'approved' && !row.receivesPayments) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: PartnerKeys.retryVenueWallet(row.id),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busyId == row.id ? null : () => _retry(row.id),
                child: const Text('Tentar criar subconta de novo'),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Faixa da casa que ainda não recebe pagamento.
class PayoutPendingBanner extends StatelessWidget {
  const PayoutPendingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: PartnerKeys.payoutPending,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          'Conta de recebimento pendente',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: scheme.onErrorContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
