import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_pagbank_balance.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

bool pagbankBalanceIsEstimate(AsyncValue<VenuePagbankBalance> balance) {
  if (balance.hasError) return true;
  return balance.asData?.value.kind == VenuePagbankBalanceKind.unavailable;
}

class VenuePagbankBalanceCard extends StatelessWidget {
  const VenuePagbankBalanceCard({super.key, required this.balance});

  final AsyncValue<VenuePagbankBalance> balance;

  @override
  Widget build(BuildContext context) {
    return balance.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _Unavailable(),
      data: (value) {
        if (value.kind == VenuePagbankBalanceKind.unavailable) {
          return const _Unavailable();
        }
        if (value.kind != VenuePagbankBalanceKind.live ||
            value.availableCents == null) {
          return const SizedBox.shrink();
        }
        return _Live(value: value);
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        key: PartnerKeys.pagbankBalanceUnavailable,
        color: status.alertContainer,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PartnerMessages.pagbankBalanceUnavailable,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: status.onAlertContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                PartnerMessages.pagbankBalanceUnavailableBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: status.onAlertContainer,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.value});

  final VenuePagbankBalance value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        key: PartnerKeys.pagbankBalance,
        color: scheme.primary,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                PartnerMessages.pagbankBalanceTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _Amount(
                label: PartnerMessages.pagbankBalanceAvailable,
                cents: value.availableCents!,
                amountKey: PartnerKeys.pagbankBalanceAvailable,
                onColor: scheme.onPrimary,
              ),
              if (value.blockedCents != null) ...[
                const SizedBox(height: 10),
                _Amount(
                  label: PartnerMessages.pagbankBalanceBlocked,
                  cents: value.blockedCents!,
                  amountKey: PartnerKeys.pagbankBalanceBlocked,
                  onColor: scheme.onPrimary,
                ),
              ],
              if (value.heldCents != null) ...[
                const SizedBox(height: 10),
                _Amount(
                  label: PartnerMessages.pagbankBalanceHeld,
                  cents: value.heldCents!,
                  amountKey: PartnerKeys.pagbankBalanceHeld,
                  onColor: scheme.onPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.label,
    required this.cents,
    required this.amountKey,
    required this.onColor,
  });

  final String label;
  final int cents;
  final Key amountKey;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(color: onColor),
        ),
        const SizedBox(height: 2),
        Text(
          formatPrice(cents),
          key: amountKey,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: onColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
