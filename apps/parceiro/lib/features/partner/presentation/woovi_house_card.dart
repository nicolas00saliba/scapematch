import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/data/provider_payments.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Saldo e saque da subconta Woovi, e a conexão com o Mercado Pago.
class WooviHouseCard extends ConsumerStatefulWidget {
  const WooviHouseCard({super.key, required this.venueId, this.launchUrl});

  final String venueId;

  final Future<bool> Function(Uri uri)? launchUrl;

  @override
  ConsumerState<WooviHouseCard> createState() => _WooviHouseCardState();
}

class _WooviHouseCardState extends ConsumerState<WooviHouseCard> {
  WooviHouseBalance? _balance;
  var _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stack = ref.read(paymentsStackProvider);
    if (!wooviPaymentsOn(stack)) return;
    try {
      final balance = await ref
          .read(providerPaymentsRepositoryProvider)
          .balance(widget.venueId);
      if (!mounted) return;
      setState(() => _balance = balance);
    } on Object {
      if (!mounted) return;
      setState(() => _message = PartnerMessages.withdrawalsLoadError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stack = ref.watch(paymentsStackProvider);
    if (!wooviPaymentsOn(stack)) return const SizedBox.shrink();
    final balance = _balance;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: PartnerKeys.wooviBalance,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PartnerMessages.wooviBalanceTitle,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(PartnerMessages.groupUnconfirmed),
              const SizedBox(height: 12),
              Text(
                balance == null ? '—' : formatPrice(balance.balanceCents),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (balance != null && balance.pixKeyMasked.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(balance.pixKeyMasked),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: PartnerKeys.wooviWithdraw,
                onPressed: _busy || balance == null || !balance.canWithdraw
                    ? null
                    : _withdraw,
                child: const Text(PartnerMessages.wooviWithdraw),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: PartnerKeys.mpConnect,
                onPressed: _busy ? null : _connect,
                child: const Text(PartnerMessages.mpConnect),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _withdraw() async {
    final balance = _balance;
    if (balance == null || balance.balanceCents <= 0) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(providerPaymentsRepositoryProvider)
          .withdraw(venueId: widget.venueId, amountCents: balance.balanceCents);
      await _load();
    } on Object {
      if (mounted) {
        setState(() => _message = PartnerMessages.withdrawalsLoadError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final uri = await ref
          .read(providerPaymentsRepositoryProvider)
          .mpConnectUrl(widget.venueId);
      final launch = widget.launchUrl ?? launchExternalUrl;
      await launch(uri);
      if (mounted) setState(() => _message = PartnerMessages.mpConnectOpened);
    } on Object {
      if (mounted) {
        setState(() => _message = PartnerMessages.withdrawalsLoadError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
