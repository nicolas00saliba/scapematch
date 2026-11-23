import 'package:flutter/material.dart';
import 'package:scapematch/core/sharing/external_url_launch.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Explica o recebimento na conta PagBank e a Transferência Automática.
///
/// Não pede conta, chave Pix nem valor de saque. O token da casa não
/// cadastra destino nem transfere.
class VenueWithdrawalsPanel extends StatelessWidget {
  const VenueWithdrawalsPanel({
    super.key,
    required this.venueId,
    this.email,
    this.onOpenPagBank,
  });

  final String venueId;
  final String? email;
  final void Function(Uri uri)? onOpenPagBank;

  static final pagBankUri = Uri.parse(PartnerMessages.receivePagBankUrl);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    assert(venueId.isNotEmpty || email == null);
    return Column(
      key: PartnerKeys.withdrawals,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          PartnerMessages.withdrawalsTitle,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PartnerMessages.withdrawalsBody,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 20),
        Text(
          PartnerMessages.receiveStepsTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (final step in const [
          PartnerMessages.receiveStepAccount,
          PartnerMessages.receiveStepMenu,
          PartnerMessages.receiveStepDestination,
          PartnerMessages.receiveStepEnable,
        ]) ...[
          Text(step, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: PartnerKeys.receiveOpenPagBank,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            onPressed: () {
              final open = onOpenPagBank ?? launchExternalUrl;
              open(pagBankUri);
            },
            icon: Icon(Icons.open_in_new, color: scheme.onPrimary),
            label: const Text(PartnerMessages.receiveOpenPagBank),
          ),
        ),
      ],
    );
  }
}
