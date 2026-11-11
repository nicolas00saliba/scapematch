import 'dart:convert';

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/sharing/save_bytes.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Nota de serviço da casa para o jogador desta reserva.
///
/// A comissão não entra aqui: ela é a nota da EscapeMatch contra a casa.
class ServiceInvoiceCard extends StatelessWidget {
  const ServiceInvoiceCard({super.key, required this.invoice});

  final FiscalInvoiceView invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skipped = invoice.status == FiscalInvoiceStatus.semEmissao;
    return Column(
      key: AppKeys.serviceInvoice,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          skipped ? 'Sem emissão de nota' : 'Nota fiscal do serviço',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          skipped
              ? fiscalSkipLabel(invoice.skipReason ?? FiscalSkipReason.cpf)
              : '${fiscalStatusLabel(invoice.status)} · ${invoice.number ?? ''}',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 4),
        Text(
          formatPrice(invoice.valueCents),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        if (invoice.canDownload) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: AppKeys.serviceInvoicePdf,
                onPressed: () => _download(context, pdf: true),
                child: const Text('Baixar PDF'),
              ),
              OutlinedButton(
                key: AppKeys.serviceInvoiceXml,
                onPressed: () => _download(context, pdf: false),
                child: const Text('Baixar XML'),
              ),
              TextButton(
                key: AppKeys.serviceInvoiceShare,
                onPressed: () => _share(context),
                child: const Text('Compartilhar'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _download(BuildContext context, {required bool pdf}) async {
    final name = invoice.number ?? invoice.id;
    final saved = pdf
        ? await saveBytes(
            filename: '$name.pdf',
            bytes: invoicePdfBytes(invoice),
            mime: 'application/pdf',
          )
        : await saveBytes(
            filename: '$name.xml',
            bytes: utf8.encode(invoiceXml(invoice)),
            mime: 'application/xml',
          );
    if (!context.mounted) return;
    if (saved) return;
    final link = pdf ? invoice.pdfUrl : invoice.xmlUrl;
    if (link != null && link.startsWith('https://') && !link.contains('/notas/teste/')) {
      await openExternalUrl(Uri.parse(link));
      return;
    }
    if (link != null) {
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link da nota copiado.')),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    final link = invoice.shareLink;
    final text = 'Nota ${invoice.number ?? ''} da sua reserva no EscapeMatch.\n$link';
    final shared = await sharePlainText(text);
    if (!context.mounted || shared) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link da nota copiado.')),
    );
  }
}

FiscalInvoiceView? serviceInvoiceFor({
  required Group group,
  required Participant seat,
}) {
  if (seat.payment != PaymentStatus.paid || !seat.occupiesSeat) {
    return null;
  }
  final playerId = seat.userId ?? seat.id;
  final notes = planChargeInvoices(
    share: PaidShare(
      chargeId: '${group.id}-$playerId',
      groupId: group.id,
      venueId: group.houseId,
      venueName: group.houseName,
      playerId: playerId,
      playerName: seat.displayName,
      amountCents: group.priceCents,
      commissionCents: commissionOfShare(
        group.priceCents,
        PlatformSettings.openingCommissionBps,
      ),
      paidAt: group.startsAt,
    ),
    venue: demoHouseFiscal,
  );
  for (final note in notes) {
    if (note.kind == FiscalInvoiceKind.service) {
      return note;
    }
  }
  return null;
}
