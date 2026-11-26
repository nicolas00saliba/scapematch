import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch_parceiro/features/partner/data/venue_pagbank_balance.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

bool pagbankBalanceIsEstimate(AsyncValue<VenuePagbankBalance> balance) {
  if (balance.hasError) return true;
  final kind = balance.asData?.value.kind;
  return kind == VenuePagbankBalanceKind.unavailable ||
      kind == VenuePagbankBalanceKind.unlinked;
}

/// "hoje às 14:52" ou "26/11 às 14:52".
String formatPagbankReadAt(DateTime readAt, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(readAt.hour)}:${two(readAt.minute)}';
  final sameDay =
      readAt.year == now.year &&
      readAt.month == now.month &&
      readAt.day == now.day;
  if (sameDay) return 'hoje às $time';
  return '${two(readAt.day)}/${two(readAt.month)} às $time';
}

class VenuePagbankBalanceCard extends StatelessWidget {
  const VenuePagbankBalanceCard({
    super.key,
    required this.balance,
    this.onRefresh,
  });

  final AsyncValue<VenuePagbankBalance> balance;

  /// Lê o saldo de novo na PagBank.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final refreshing = balance.isRefreshing;
    return balance.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _Notice(
        noticeKey: PartnerKeys.pagbankBalanceUnavailable,
        title: PartnerMessages.pagbankBalanceFailed,
        body: PartnerMessages.pagbankBalanceFailedBody,
        onRefresh: onRefresh,
        refreshing: refreshing,
      ),
      data: (value) {
        switch (value.kind) {
          case VenuePagbankBalanceKind.absent:
            return const SizedBox.shrink();
          case VenuePagbankBalanceKind.unlinked:
            return _Notice(
              noticeKey: PartnerKeys.pagbankBalanceUnlinked,
              title: PartnerMessages.pagbankBalanceUnlinked,
              body: PartnerMessages.pagbankBalanceUnlinkedBody,
              onRefresh: onRefresh,
              refreshing: refreshing,
            );
          case VenuePagbankBalanceKind.unavailable:
            return _Notice(
              noticeKey: PartnerKeys.pagbankBalanceUnavailable,
              title: value.forbidden
                  ? PartnerMessages.pagbankBalanceUnavailable
                  : PartnerMessages.pagbankBalanceFailed,
              body: value.forbidden
                  ? PartnerMessages.pagbankBalanceUnavailableBody
                  : PartnerMessages.pagbankBalanceFailedBody,
              onRefresh: onRefresh,
              refreshing: refreshing,
            );
          case VenuePagbankBalanceKind.live:
            if (value.availableCents == null) return const SizedBox.shrink();
            return _Live(
              value: value,
              onRefresh: onRefresh,
              refreshing: refreshing,
            );
        }
      },
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.onRefresh,
    required this.refreshing,
    required this.color,
  });

  final VoidCallback? onRefresh;
  final bool refreshing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (onRefresh == null) return const SizedBox.shrink();
    return TextButton.icon(
      key: PartnerKeys.pagbankBalanceRefresh,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 48),
      ),
      onPressed: refreshing ? null : onRefresh,
      icon: refreshing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          : const Icon(Icons.refresh),
      label: const Text(PartnerMessages.pagbankBalanceRefresh),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.noticeKey,
    required this.title,
    required this.body,
    required this.onRefresh,
    required this.refreshing,
  });

  final Key noticeKey;
  final String title;
  final String body;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        key: noticeKey,
        color: status.alertContainer,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: status.onAlertContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: status.onAlertContainer,
                  height: 1.35,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _RefreshButton(
                  onRefresh: onRefresh,
                  refreshing: refreshing,
                  color: status.onAlertContainer,
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
  const _Live({
    required this.value,
    required this.onRefresh,
    required this.refreshing,
  });

  final VenuePagbankBalance value;
  final VoidCallback? onRefresh;
  final bool refreshing;

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      PartnerMessages.pagbankBalanceTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _RefreshButton(
                    onRefresh: onRefresh,
                    refreshing: refreshing,
                    color: scheme.onPrimary,
                  ),
                ],
              ),
              if (value.readAt != null)
                Text(
                  '${PartnerMessages.pagbankBalanceLastRead}: '
                  '${formatPagbankReadAt(value.readAt!, DateTime.now())}',
                  key: PartnerKeys.pagbankBalanceReadAt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary,
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
