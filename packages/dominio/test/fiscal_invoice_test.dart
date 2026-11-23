import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  final paidAt = DateTime(2026, 11, 3, 19);
  final share = PaidShare(
    chargeId: 'ch-1',
    groupId: 'grp-cwb-xv-fechado',
    venueId: 'cwb-rua-xv',
    venueName: 'Mistério da Rua XV',
    playerId: 'user-local',
    playerName: 'Nícolas',
    amountCents: 12000,
    commissionCents: commissionOfShare(12000, 1000),
    paidAt: paidAt,
  );

  test('CNPJ com dados fiscais gera serviço e comissão de teste', () {
    final notes = planChargeInvoices(share: share, venue: demoHouseFiscal);
    expect(notes, hasLength(2));
    final service = notes.first;
    final commission = notes.last;
    expect(service.kind, FiscalInvoiceKind.service);
    expect(service.issuer, FiscalIssuer.venue);
    expect(service.status, FiscalInvoiceStatus.simulated);
    expect(service.valueCents, 12000);
    expect(service.playerId, 'user-local');
    expect(service.number, isNotNull);
    expect(service.pdfUrl, contains('api-sandbox.asaas.com'));
    expect(service.xmlUrl, endsWith('.xml'));
    expect(commission.kind, FiscalInvoiceKind.commission);
    expect(commission.issuer, FiscalIssuer.platform);
    expect(commission.valueCents, 1200);
    expect(commission.status, FiscalInvoiceStatus.simulated);
    expect(service.id, isNot(commission.id));
  });

  test('CPF recebe e a nota de serviço fica sem emissão', () {
    const cpf = VenueFiscalProfile(documentKind: FiscalDocumentKind.cpf);
    final notes = planChargeInvoices(share: share, venue: cpf);
    expect(notes.first.status, FiscalInvoiceStatus.semEmissao);
    expect(notes.first.skipReason, FiscalSkipReason.cpf);
    expect(notes.first.canDownload, isFalse);
    expect(notes.first.pdfUrl, isNull);
    expect(notes.last.kind, FiscalInvoiceKind.commission);
    expect(notes.last.status, FiscalInvoiceStatus.simulated);
    expect(
      fiscalStatusLabel(FiscalInvoiceStatus.semEmissao),
      'Sem emissão de nota',
    );
  });

  test('CNPJ sem inscrição não emite o serviço', () {
    const incomplete = VenueFiscalProfile(
      documentKind: FiscalDocumentKind.cnpj,
      serviceCode: '12.08',
      issPercent: 2,
    );
    final notes = planChargeInvoices(share: share, venue: incomplete);
    expect(notes.first.status, FiscalInvoiceStatus.semEmissao);
    expect(notes.first.skipReason, FiscalSkipReason.dadosFiscais);
  });

  test('fora do sandbox a nota fica agendada, sem URL de teste', () {
    final notes = planChargeInvoices(
      share: share,
      venue: demoHouseFiscal,
      sandbox: false,
    );
    expect(notes.first.status, FiscalInvoiceStatus.scheduled);
    expect(notes.first.pdfUrl, isNull);
    expect(notes.last.status, FiscalInvoiceStatus.scheduled);
  });

  test('comissão zero não gera a segunda nota', () {
    final free = PaidShare(
      chargeId: share.chargeId,
      groupId: share.groupId,
      venueId: share.venueId,
      venueName: share.venueName,
      playerId: share.playerId,
      playerName: share.playerName,
      amountCents: share.amountCents,
      commissionCents: 0,
      paidAt: paidAt,
    );
    final notes = planChargeInvoices(share: free, venue: demoHouseFiscal);
    expect(notes, hasLength(1));
    expect(notes.single.kind, FiscalInvoiceKind.service);
  });

  test('o período de 30 dias inclui ontem e o mês corrente filtra o mês', () {
    final now = DateTime(2026, 11, 4);
    expect(
      invoiceInPeriod(paidAt: paidAt, now: now, period: InvoicePeriod.days30),
      isTrue,
    );
    expect(
      invoiceInPeriod(
        paidAt: paidAt,
        now: now,
        period: InvoicePeriod.thisMonth,
      ),
      isTrue,
    );
    expect(
      invoiceInPeriod(
        paidAt: DateTime(2026, 10, 1),
        now: now,
        period: InvoicePeriod.thisMonth,
      ),
      isFalse,
    );
    expect(
      invoiceInPeriod(
        paidAt: DateTime(2026, 9, 1),
        now: now,
        period: InvoicePeriod.days30,
      ),
      isFalse,
    );
  });

  test('o XML e o PDF de teste nascem da nota', () {
    final note = planChargeInvoices(
      share: share,
      venue: demoHouseFiscal,
    ).first;
    final xml = invoiceXml(note);
    expect(xml, contains('Nícolas'));
    expect(xml, contains(note.number));
    final pdf = invoicePdfBytes(note);
    expect(String.fromCharCodes(pdf), startsWith('%PDF-1.4'));
  });
}
