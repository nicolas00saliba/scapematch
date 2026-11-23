import 'dart:convert';

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/sharing/save_bytes.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch_parceiro/features/partner/data/fiscal_zip.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PartnerInvoices extends ConsumerStatefulWidget {
  const PartnerInvoices({super.key, required this.snapshot});

  final PartnerSnapshot snapshot;

  @override
  ConsumerState<PartnerInvoices> createState() => _PartnerInvoicesState();
}

class _PartnerInvoicesState extends ConsumerState<PartnerInvoices> {
  InvoicePeriod _period = InvoicePeriod.days30;
  final Set<String> _selected = {};
  late final TextEditingController _inscription;
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _iss;
  late FiscalDocumentKind _kind;
  late bool _mei;

  @override
  void initState() {
    super.initState();
    final fiscal = widget.snapshot.fiscal;
    _kind = fiscal.documentKind;
    _mei = fiscal.mei;
    _inscription = TextEditingController(text: fiscal.municipalInscription);
    _code = TextEditingController(text: fiscal.serviceCode);
    _name = TextEditingController(text: fiscal.serviceName);
    _iss = TextEditingController(
      text: fiscal.issPercent == 0 ? '' : fiscal.issPercent.toString(),
    );
  }

  @override
  void dispose() {
    _inscription.dispose();
    _code.dispose();
    _name.dispose();
    _iss.dispose();
    super.dispose();
  }

  List<FiscalInvoiceView> get _visible {
    final now = widget.snapshot.now;
    return [
      for (final invoice in widget.snapshot.invoices)
        if (invoiceInPeriod(paidAt: invoice.paidAt, now: now, period: _period))
          invoice,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final wide = isScapeDesktop(context);
    final theme = Theme.of(context);
    final visible = _visible;
    final downloadable = visible.where((invoice) => invoice.canDownload);
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 20, wide ? 32 : 16, 32),
      children: [
        Text(
          PartnerMessages.invoices,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Duas notas por reserva paga: o serviço, da casa para o jogador, e a comissão, da EscapeMatch para a casa. No sandbox a nota é de teste.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: PartnerKeys.invoicePeriod30,
              label: const Text('30 dias'),
              selected: _period == InvoicePeriod.days30,
              onSelected: (_) => _setPeriod(InvoicePeriod.days30),
            ),
            ChoiceChip(
              key: PartnerKeys.invoicePeriodMonth,
              label: const Text('Este mês'),
              selected: _period == InvoicePeriod.thisMonth,
              onSelected: (_) => _setPeriod(InvoicePeriod.thisMonth),
            ),
            ChoiceChip(
              key: PartnerKeys.invoicePeriodAll,
              label: const Text('Tudo'),
              selected: _period == InvoicePeriod.all,
              onSelected: (_) => _setPeriod(InvoicePeriod.all),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: downloadable.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(downloadable.map((invoice) => invoice.id));
                      });
                    },
              child: const Text('Selecionar notas'),
            ),
            FilledButton(
              key: PartnerKeys.invoiceBatch,
              onPressed: _selected.isEmpty ? null : () => _downloadBatch(visible),
              child: Text(
                _selected.isEmpty
                    ? 'Baixar em lote'
                    : 'Baixar ${_selected.length} em lote',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          const Text('Nenhuma nota neste período.')
        else
          for (final invoice in visible) ...[
            _InvoiceTile(
              invoice: invoice,
              selected: _selected.contains(invoice.id),
              onSelected: invoice.canDownload
                  ? (value) {
                      setState(() {
                        if (value) {
                          _selected.add(invoice.id);
                        } else {
                          _selected.remove(invoice.id);
                        }
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 8),
        _FiscalForm(
          kind: _kind,
          mei: _mei,
          inscription: _inscription,
          code: _code,
          serviceName: _name,
          iss: _iss,
          onKind: (kind) => setState(() => _kind = kind),
          onMei: (value) => setState(() => _mei = value),
          onSave: _saveFiscal,
        ),
      ],
    );
  }

  void _setPeriod(InvoicePeriod period) {
    setState(() {
      _period = period;
      _selected.clear();
    });
  }

  Future<void> _saveFiscal() async {
    final iss = double.tryParse(_iss.text.trim().replaceAll(',', '.')) ?? 0;
    final profile = VenueFiscalProfile(
      documentKind: _kind,
      mei: _kind == FiscalDocumentKind.cnpj && _mei,
      municipalInscription: _inscription.text.trim(),
      serviceCode: _code.text.trim(),
      serviceName: _name.text.trim(),
      issPercent: iss,
    );
    ref.read(partnerFiscalProvider.notifier).save(profile);
    if (scapeUsesLiveBackend) {
      try {
        final response = await scapeSupabase.functions.invoke(
          'configure-venue-fiscal',
          body: {
            'venue_id': widget.snapshot.house.id,
            'municipal_inscription': profile.municipalInscription,
            'service_code': profile.serviceCode,
            'service_name': profile.serviceName,
            'iss_rate': profile.issPercent,
            'mei': profile.mei,
            'simples_nacional': profile.mei,
          },
        );
        if (!mounted) return;
        if (response.status != 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível gravar os dados fiscais.'),
            ),
          );
          return;
        }
        ref.invalidate(partnerDeskProvider);
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível gravar os dados fiscais.'),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          scapeUsesLiveBackend
              ? 'Dados fiscais enviados. A função configura a subconta no Asaas.'
              : 'Dados fiscais salvos nesta sessão. No servidor, a função configura a subconta no Asaas.',
        ),
      ),
    );
  }

  Future<void> _downloadBatch(List<FiscalInvoiceView> visible) async {
    final files = <String, List<int>>{};
    for (final invoice in visible) {
      if (!_selected.contains(invoice.id) || !invoice.canDownload) {
        continue;
      }
      final name = invoice.number ?? invoice.id;
      files['$name.pdf'] = invoicePdfBytes(invoice);
      files['$name.xml'] = utf8.encode(invoiceXml(invoice));
    }
    if (files.isEmpty) return;
    final saved = await saveBytes(
      filename: 'notas-fiscais.zip',
      bytes: zipStored(files),
      mime: 'application/zip',
    );
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${files.length ~/ 2} notas prontas no lote.')),
      );
    }
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.selected,
    required this.onSelected,
  });

  final FiscalInvoiceView invoice;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = invoice.kind == FiscalInvoiceKind.service
        ? 'Para ${invoice.playerName}'
        : 'Contra a casa';
    return Card(
      key: PartnerKeys.invoiceRow(invoice.id),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (onSelected != null)
                  Checkbox(
                    key: PartnerKeys.invoiceSelect(invoice.id),
                    value: selected,
                    onChanged: (value) => onSelected!(value ?? false),
                  ),
                Expanded(
                  child: Text(
                    fiscalKindLabel(invoice.kind),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  formatPrice(invoice.valueCents),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            Text('$room · ${formatSession(invoice.paidAt)}'),
            const SizedBox(height: 4),
            Text(
              invoice.number == null
                  ? fiscalStatusLabel(invoice.status)
                  : '${fiscalStatusLabel(invoice.status)} · ${invoice.number}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (invoice.skipReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(fiscalSkipLabel(invoice.skipReason!)),
              ),
            if (invoice.canDownload)
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    key: PartnerKeys.invoicePdf(invoice.id),
                    onPressed: () => _file(context, pdf: true),
                    child: const Text('PDF'),
                  ),
                  TextButton(
                    key: PartnerKeys.invoiceXml(invoice.id),
                    onPressed: () => _file(context, pdf: false),
                    child: const Text('XML'),
                  ),
                  TextButton(
                    key: PartnerKeys.invoiceShare(invoice.id),
                    onPressed: () => _share(context),
                    child: const Text('Compartilhar'),
                  ),
                  TextButton(
                    key: PartnerKeys.invoiceCopy(invoice.id),
                    onPressed: () => _copy(context),
                    child: const Text('Copiar link'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _file(BuildContext context, {required bool pdf}) async {
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
    if (!context.mounted || saved) return;
    final link = pdf ? invoice.pdfUrl : invoice.xmlUrl;
    if (link != null &&
        link.startsWith('https://') &&
        !link.contains('/notas/teste/')) {
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
    final text =
        '${fiscalKindLabel(invoice.kind)} ${invoice.number ?? ''}\n$link';
    final shared = await sharePlainText(text);
    if (!context.mounted || shared) return;
    await _copy(context);
  }

  Future<void> _copy(BuildContext context) async {
    final link = invoice.shareLink;
    if (link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link da nota copiado.')),
    );
  }
}

class _FiscalForm extends StatelessWidget {
  const _FiscalForm({
    required this.kind,
    required this.mei,
    required this.inscription,
    required this.code,
    required this.serviceName,
    required this.iss,
    required this.onKind,
    required this.onMei,
    required this.onSave,
  });

  final FiscalDocumentKind kind;
  final bool mei;
  final TextEditingController inscription;
  final TextEditingController code;
  final TextEditingController serviceName;
  final TextEditingController iss;
  final ValueChanged<FiscalDocumentKind> onKind;
  final ValueChanged<bool> onMei;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cnpj = kind == FiscalDocumentKind.cnpj;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dados fiscais da casa',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'CNPJ ou MEI emite a nota do serviço. CPF recebe e fica sem emissão de nota. A senha da prefeitura, se existir, só vai para a função do servidor.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: PartnerKeys.fiscalCnpj,
                  label: const Text('CNPJ / MEI'),
                  selected: cnpj,
                  onSelected: (_) => onKind(FiscalDocumentKind.cnpj),
                ),
                ChoiceChip(
                  key: PartnerKeys.fiscalCpf,
                  label: const Text('CPF'),
                  selected: !cnpj,
                  onSelected: (_) => onKind(FiscalDocumentKind.cpf),
                ),
              ],
            ),
            if (cnpj) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: mei,
                onChanged: onMei,
                title: const Text('MEI ou Simples Nacional'),
              ),
              TextField(
                controller: inscription,
                decoration: const InputDecoration(
                  labelText: 'Inscrição municipal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: code,
                decoration: const InputDecoration(
                  labelText: 'Código de serviço',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: serviceName,
                decoration: const InputDecoration(
                  labelText: 'Nome do serviço',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: iss,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Alíquota de ISS (%)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: PartnerKeys.fiscalSave,
              onPressed: onSave,
              child: const Text('Salvar dados fiscais'),
            ),
          ],
        ),
      ),
    );
  }
}
