import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/payments/domain/card_installments.dart';
import 'package:scapematch/features/payments/presentation/installment_grid.dart';

/// Foto da sala, valor e o atalho que abre a grade de parcelas.
class ReservationPaySummary extends StatelessWidget {
  const ReservationPaySummary({
    super.key,
    required this.coverAsset,
    this.coverBytes,
    required this.houseName,
    required this.roomName,
    required this.totalLabel,
    required this.installmentLabel,
    required this.onOpenInstallments,
  });

  final String coverAsset;

  /// Foto já lida, só para o print de divulgação. A folha real usa [coverAsset].
  final Uint8List? coverBytes;
  final String houseName;
  final String roomName;
  final String totalLabel;
  final String installmentLabel;
  final VoidCallback? onOpenInstallments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final caption = [houseName, roomName].where((item) => item.isNotEmpty);
    return Column(
      key: AppKeys.payReservation,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: coverBytes == null && coverAsset.isEmpty
                    ? ColoredBox(color: scheme.primaryContainer)
                    : ScapePhoto(
                        asset: coverAsset,
                        bytes: coverBytes,
                        semanticLabel: roomName.isEmpty ? houseName : roomName,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in caption)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    totalLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            key: AppKeys.payInstallments,
            onTap: onOpenInstallments,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Parcelamento',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            installmentLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tela da grade. O toque numa parcela devolve a quantidade.
class InstallmentPickerPage extends StatelessWidget {
  const InstallmentPickerPage({
    super.key,
    required this.options,
    required this.selected,
  });

  static const title = 'Em quantas vezes quer parcelar?';

  final List<CardInstallmentOption> options;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: AppKeys.installmentPicker,
      appBar: AppBar(
        toolbarHeight: 84,
        title: Text(
          title,
          maxLines: 2,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          InstallmentGrid(
            options: options,
            selected: selected,
            onSelect: (count) => Navigator.of(context).pop(count),
          ),
        ],
      ),
    );
  }
}
