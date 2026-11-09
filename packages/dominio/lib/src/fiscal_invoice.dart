import 'package:dominio/src/commission.dart';

/// Versão publicada dos textos jurídicos. O aceite grava este valor.
const legalDocumentVersion = '2026-11-06';

const playerAcceptanceCodes = ['player_terms', 'privacy', 'cancellation'];

const partnerAcceptanceCodes = ['partner_terms', 'privacy', 'cancellation'];

/// Aceite de um documento. A data vem do servidor (ou do relógio do exemplo).
class LegalAcceptance {
  const LegalAcceptance({
    required this.userId,
    required this.audience,
    required this.documentCode,
    required this.documentVersion,
    required this.acceptedAt,
    this.venueId,
  });

  final String userId;
  final String audience;
  final String documentCode;
  final String documentVersion;
  final DateTime acceptedAt;
  final String? venueId;
}

enum FiscalDocumentKind { cpf, cnpj }

enum FiscalInvoiceKind { service, commission }

enum FiscalIssuer { venue, platform }

enum FiscalInvoiceStatus {
  scheduled,
  processing,
  authorized,
  error,
  canceled,
  semEmissao,
  simulated,
}

enum FiscalSkipReason { cpf, dadosFiscais }

/// Dados fiscais da casa. CPF não emite. CNPJ/MEI emite com inscrição,
/// código de serviço e alíquota de ISS.
class VenueFiscalProfile {
  const VenueFiscalProfile({
    required this.documentKind,
    this.mei = false,
    this.municipalInscription = '',
    this.serviceCode = '',
    this.serviceName = '',
    this.issPercent = 0,
  });

  final FiscalDocumentKind documentKind;
  final bool mei;
  final String municipalInscription;
  final String serviceCode;
  final String serviceName;

  /// Alíquota de ISS em porcentagem. 2 significa 2%.
  final double issPercent;

  bool get canEmitService {
    if (documentKind != FiscalDocumentKind.cnpj) {
      return false;
    }
    if (municipalInscription.trim().isEmpty) {
      return false;
    }
    if (serviceCode.trim().isEmpty) {
      return false;
    }
    if (issPercent <= 0 || issPercent > 100) {
      return false;
    }
    return true;
  }

  FiscalSkipReason? get serviceBlockReason {
    if (canEmitService) {
      return null;
    }
    if (documentKind == FiscalDocumentKind.cpf) {
      return FiscalSkipReason.cpf;
    }
    return FiscalSkipReason.dadosFiscais;
  }

  String get serviceNameOrDefault {
    final name = serviceName.trim();
    if (name.isEmpty) {
      return 'Serviços de recreação e lazer';
    }
    return name;
  }

  VenueFiscalProfile copyWith({
    FiscalDocumentKind? documentKind,
    bool? mei,
    String? municipalInscription,
    String? serviceCode,
    String? serviceName,
    double? issPercent,
  }) {
    return VenueFiscalProfile(
      documentKind: documentKind ?? this.documentKind,
      mei: mei ?? this.mei,
      municipalInscription: municipalInscription ?? this.municipalInscription,
      serviceCode: serviceCode ?? this.serviceCode,
      serviceName: serviceName ?? this.serviceName,
      issPercent: issPercent ?? this.issPercent,
    );
  }
}

/// Casa de exemplo com CNPJ/MEI e dados fiscais completos.
const demoHouseFiscal = VenueFiscalProfile(
  documentKind: FiscalDocumentKind.cnpj,
  mei: true,
  municipalInscription: '12345678',
  serviceCode: '12.08',
  serviceName: 'Organização de jogos de escape',
  issPercent: 2,
);

/// NFS-e da intermediação, emitida pela conta raiz da EscapeMatch.
class PlatformFiscalProfile {
  const PlatformFiscalProfile({
    this.serviceCode = '17.02',
    this.serviceName = 'Intermediação de reservas',
    this.issPercent = 2,
  });

  final String serviceCode;
  final String serviceName;
  final double issPercent;
}

const demoPlatformFiscal = PlatformFiscalProfile();

/// Uma parte já paga. A nota nasce daqui, não da pré-autorização.
class PaidShare {
  const PaidShare({
    required this.chargeId,
    required this.groupId,
    required this.venueId,
    required this.venueName,
    required this.playerId,
    required this.playerName,
    required this.amountCents,
    required this.commissionCents,
    required this.paidAt,
  });

  final String chargeId;
  final String groupId;
  final String venueId;
  final String venueName;
  final String playerId;
  final String playerName;
  final int amountCents;
  final int commissionCents;
  final DateTime paidAt;
}

/// Nota que a tela lista. No sandbox o status é [FiscalInvoiceStatus.simulated].
class FiscalInvoiceView {
  const FiscalInvoiceView({
    required this.id,
    required this.chargeId,
    required this.groupId,
    required this.venueId,
    required this.playerId,
    required this.playerName,
    required this.venueName,
    required this.kind,
    required this.issuer,
    required this.status,
    required this.valueCents,
    required this.paidAt,
    required this.description,
    this.skipReason,
    this.number,
    this.pdfUrl,
    this.xmlUrl,
    this.issPercent,
    this.serviceCode,
  });

  final String id;
  final String chargeId;
  final String groupId;
  final String venueId;
  final String playerId;
  final String playerName;
  final String venueName;
  final FiscalInvoiceKind kind;
  final FiscalIssuer issuer;
  final FiscalInvoiceStatus status;
  final FiscalSkipReason? skipReason;
  final int valueCents;
  final DateTime paidAt;
  final String description;
  final String? number;
  final String? pdfUrl;
  final String? xmlUrl;
  final double? issPercent;
  final String? serviceCode;

  bool get canDownload =>
      status == FiscalInvoiceStatus.simulated ||
      status == FiscalInvoiceStatus.authorized;

  String get shareLink => pdfUrl ?? xmlUrl ?? '';
}

enum InvoicePeriod { days30, thisMonth, all }

/// Duas notas por parte paga: serviço (casa → jogador) e comissão
/// (EscapeMatch → casa). Casa com CPF recebe e a nota de serviço fica
/// sem emissão. A comissão continua.
List<FiscalInvoiceView> planChargeInvoices({
  required PaidShare share,
  required VenueFiscalProfile venue,
  bool sandbox = true,
  PlatformFiscalProfile platform = demoPlatformFiscal,
}) {
  if (share.amountCents <= 0) {
    throw ArgumentError.value(share.amountCents, 'amountCents');
  }
  final service = _serviceInvoice(share, venue, sandbox);
  final invoices = <FiscalInvoiceView>[service];
  if (share.commissionCents > 0) {
    invoices.add(_commissionInvoice(share, platform, sandbox));
  }
  return invoices;
}

int commissionOfShare(int amountCents, int commissionBps) {
  return commissionCents(amountCents, commissionBps);
}

bool invoiceInPeriod({
  required DateTime paidAt,
  required DateTime now,
  required InvoicePeriod period,
}) {
  final paid = DateTime(paidAt.year, paidAt.month, paidAt.day);
  final today = DateTime(now.year, now.month, now.day);
  return switch (period) {
    InvoicePeriod.all => true,
    InvoicePeriod.thisMonth =>
      paid.year == today.year && paid.month == today.month,
    InvoicePeriod.days30 => !paid.isBefore(today.subtract(const Duration(days: 30))),
  };
}

String fiscalStatusLabel(FiscalInvoiceStatus status) {
  return switch (status) {
    FiscalInvoiceStatus.scheduled => 'Agendada',
    FiscalInvoiceStatus.processing => 'Em processamento',
    FiscalInvoiceStatus.authorized => 'Emitida',
    FiscalInvoiceStatus.error => 'Erro na emissão',
    FiscalInvoiceStatus.canceled => 'Cancelada',
    FiscalInvoiceStatus.semEmissao => 'Sem emissão de nota',
    FiscalInvoiceStatus.simulated => 'Nota de teste',
  };
}

String fiscalKindLabel(FiscalInvoiceKind kind) {
  return switch (kind) {
    FiscalInvoiceKind.service => 'Serviço da casa',
    FiscalInvoiceKind.commission => 'Comissão da EscapeMatch',
  };
}

String fiscalSkipLabel(FiscalSkipReason reason) {
  return switch (reason) {
    FiscalSkipReason.cpf =>
      'A casa é pessoa física (CPF). O valor é recebido, sem NFS-e do serviço.',
    FiscalSkipReason.dadosFiscais =>
      'Faltam inscrição municipal, código de serviço ou alíquota de ISS.',
  };
}

String invoiceXml(FiscalInvoiceView invoice) {
  String tag(String name, String value) =>
      '<$name>${_xmlEscape(value)}</$name>';
  final number = invoice.number ?? '';
  final reais = (invoice.valueCents / 100).toStringAsFixed(2);
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<nfse>
  ${tag('id', invoice.id)}
  ${tag('status', invoice.status.name)}
  ${tag('numero', number)}
  ${tag('tipo', invoice.kind.name)}
  ${tag('valor', reais)}
  ${tag('descricao', invoice.description)}
  ${tag('prestador', invoice.kind == FiscalInvoiceKind.service ? invoice.venueName : 'EscapeMatch')}
  ${tag('tomador', invoice.kind == FiscalInvoiceKind.service ? invoice.playerName : invoice.venueName)}
</nfse>
''';
}

/// PDF mínimo, só com texto ASCII. O XML guarda o texto com acento.
List<int> invoicePdfBytes(FiscalInvoiceView invoice) {
  final number = invoice.number ?? 'sem numero';
  final reais = (invoice.valueCents / 100).toStringAsFixed(2);
  final line =
      'NFSe ${invoice.kind.name} $number R\$ $reais ${invoice.status.name}';
  return _simplePdf(line);
}

FiscalInvoiceView _serviceInvoice(
  PaidShare share,
  VenueFiscalProfile venue,
  bool sandbox,
) {
  final blocked = venue.serviceBlockReason;
  final status = blocked != null
      ? FiscalInvoiceStatus.semEmissao
      : sandbox
      ? FiscalInvoiceStatus.simulated
      : FiscalInvoiceStatus.scheduled;
  final number = status == FiscalInvoiceStatus.simulated
      ? _testNumber('S', share.groupId, share.playerId)
      : null;
  return FiscalInvoiceView(
    id: 'service-${share.groupId}-${share.playerId}',
    chargeId: share.chargeId,
    groupId: share.groupId,
    venueId: share.venueId,
    playerId: share.playerId,
    playerName: share.playerName,
    venueName: share.venueName,
    kind: FiscalInvoiceKind.service,
    issuer: FiscalIssuer.venue,
    status: status,
    skipReason: blocked,
    valueCents: share.amountCents,
    paidAt: share.paidAt,
    description: 'Serviço de escape room para ${share.playerName}.',
    number: number,
    pdfUrl: number == null ? null : _testPdf(number),
    xmlUrl: number == null ? null : _testXml(number),
    issPercent: blocked == null ? venue.issPercent : null,
    serviceCode: blocked == null ? venue.serviceCode.trim() : null,
  );
}

FiscalInvoiceView _commissionInvoice(
  PaidShare share,
  PlatformFiscalProfile platform,
  bool sandbox,
) {
  final status = sandbox
      ? FiscalInvoiceStatus.simulated
      : FiscalInvoiceStatus.scheduled;
  final number = status == FiscalInvoiceStatus.simulated
      ? _testNumber('C', share.groupId, share.playerId)
      : null;
  return FiscalInvoiceView(
    id: 'commission-${share.groupId}-${share.playerId}',
    chargeId: share.chargeId,
    groupId: share.groupId,
    venueId: share.venueId,
    playerId: share.playerId,
    playerName: share.playerName,
    venueName: share.venueName,
    kind: FiscalInvoiceKind.commission,
    issuer: FiscalIssuer.platform,
    status: status,
    valueCents: share.commissionCents,
    paidAt: share.paidAt,
    description:
        'Comissão de intermediação sobre a reserva de ${share.playerName}.',
    number: number,
    pdfUrl: number == null ? null : _testPdf(number),
    xmlUrl: number == null ? null : _testXml(number),
    issPercent: platform.issPercent,
    serviceCode: platform.serviceCode,
  );
}

String _testNumber(String suffix, String groupId, String playerId) {
  final compact = ('$groupId$playerId').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final tail = compact.length <= 8
      ? compact
      : compact.substring(compact.length - 8);
  return 'TESTE-$tail-$suffix'.toUpperCase();
}

String _testPdf(String number) =>
    'https://api-sandbox.asaas.com/notas/teste/$number.pdf';

String _testXml(String number) =>
    'https://api-sandbox.asaas.com/notas/teste/$number.xml';

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

List<int> _simplePdf(String text) {
  final safe = text
      .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .replaceAll('\\', ' ');
  final stream = 'BT /F1 12 Tf 48 740 Td ($safe) Tj ET';
  final objects = <String>[
    '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n',
    '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n',
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj\n',
    '4 0 obj<< /Length ${stream.length} >>stream\n$stream\nendstream\nendobj\n',
    '5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (final object in objects) {
    offsets.add(buffer.length);
    buffer.write(object);
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (var i = 1; i < offsets.length; i++) {
    buffer.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  buffer.write('startxref\n$xref\n%%EOF');
  return buffer.toString().codeUnits;
}
