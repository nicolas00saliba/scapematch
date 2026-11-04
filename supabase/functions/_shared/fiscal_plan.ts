// Plano das duas NFS-e de uma cobrança paga. Sem rede e sem chave.
// A casa emite o serviço para o jogador. A ScapeMatch emite só a comissão
// contra a casa. CPF não emite o serviço e mesmo assim recebe o split.

export type DocumentKind = "cpf" | "cnpj";

export type VenueFiscal = {
  documentKind: DocumentKind;
  municipalInscription: string;
  serviceCode: string;
  serviceName: string;
  issRate: number;
};

export type InvoiceKind = "service" | "commission";

export type InvoiceDraft = {
  kind: InvoiceKind;
  issuer: "venue" | "platform";
  status: "sem_emissao" | "simulated" | "scheduled";
  skipReason: "cpf" | "dados_fiscais" | null;
  valueCents: number;
  issRate: number | null;
  serviceCode: string | null;
  serviceName: string | null;
  description: string;
};

export function canEmitService(fiscal: VenueFiscal): boolean {
  if (fiscal.documentKind !== "cnpj") return false;
  if (fiscal.municipalInscription.trim().length === 0) return false;
  if (fiscal.serviceCode.trim().length === 0) return false;
  if (!(fiscal.issRate > 0) || fiscal.issRate > 100) return false;
  return true;
}

export function serviceBlockReason(
  fiscal: VenueFiscal,
): "cpf" | "dados_fiscais" | null {
  if (canEmitService(fiscal)) return null;
  if (fiscal.documentKind === "cpf") return "cpf";
  return "dados_fiscais";
}

export function planInvoices(input: {
  amountCents: number;
  commissionCents: number;
  playerName: string;
  venue: VenueFiscal;
  sandbox: boolean;
  platform: { serviceCode: string; serviceName: string; issRate: number };
}): InvoiceDraft[] {
  if (!Number.isInteger(input.amountCents) || input.amountCents <= 0) {
    throw new Error("invalid amount");
  }
  const block = serviceBlockReason(input.venue);
  const serviceStatus = block
    ? "sem_emissao"
    : input.sandbox
    ? "simulated"
    : "scheduled";
  const drafts: InvoiceDraft[] = [
    {
      kind: "service",
      issuer: "venue",
      status: serviceStatus,
      skipReason: block,
      valueCents: input.amountCents,
      issRate: block ? null : input.venue.issRate,
      serviceCode: block ? null : input.venue.serviceCode.trim(),
      serviceName: block
        ? null
        : (input.venue.serviceName.trim() || "Serviços de recreação e lazer"),
      description: `Serviço de escape room para ${input.playerName}.`,
    },
  ];
  if (input.commissionCents > 0) {
    drafts.push({
      kind: "commission",
      issuer: "platform",
      status: input.sandbox ? "simulated" : "scheduled",
      skipReason: null,
      valueCents: input.commissionCents,
      issRate: input.platform.issRate,
      serviceCode: input.platform.serviceCode,
      serviceName: input.platform.serviceName,
      description:
        `Comissão de intermediação sobre a reserva de ${input.playerName}.`,
    });
  }
  return drafts;
}

export function testInvoiceNumber(
  suffix: "S" | "C",
  groupId: string,
  playerId: string,
): string {
  const compact = `${groupId}${playerId}`.replace(/[^A-Za-z0-9]/g, "");
  const tail = compact.length <= 8 ? compact : compact.slice(-8);
  return `TESTE-${tail}-${suffix}`.toUpperCase();
}

export function testPdfUrl(number: string): string {
  return `https://api-sandbox.asaas.com/notas/teste/${number}.pdf`;
}

export function testXmlUrl(number: string): string {
  return `https://api-sandbox.asaas.com/notas/teste/${number}.xml`;
}

export function mapAsaasInvoiceStatus(status: string): string {
  switch (status) {
    case "AUTHORIZED":
      return "authorized";
    case "SCHEDULED":
    case "SYNCHRONIZED":
      return "processing";
    case "ERROR":
      return "error";
    case "CANCELED":
    case "PROCESSING_CANCELLATION":
      return "canceled";
    default:
      return "processing";
  }
}
