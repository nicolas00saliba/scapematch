import { assertEquals } from "jsr:@std/assert@1";
import {
  canEmitService,
  mapAsaasInvoiceStatus,
  planInvoices,
  testInvoiceNumber,
} from "./fiscal_plan.ts";
import { commissionCents } from "./asaas_provider.ts";

const venue = {
  documentKind: "cnpj" as const,
  municipalInscription: "12345678",
  serviceCode: "12.08",
  serviceName: "Organização de jogos de escape",
  issRate: 2,
};

const platform = {
  serviceCode: "17.02",
  serviceName: "Intermediação de reservas",
  issRate: 2,
};

Deno.test("CNPJ completo no sandbox simula as duas notas", () => {
  const drafts = planInvoices({
    amountCents: 12000,
    commissionCents: commissionCents(12000, 1000),
    playerName: "Nícolas",
    venue,
    sandbox: true,
    platform,
  });
  assertEquals(drafts.length, 2);
  assertEquals(drafts[0].kind, "service");
  assertEquals(drafts[0].issuer, "venue");
  assertEquals(drafts[0].status, "simulated");
  assertEquals(drafts[0].valueCents, 12000);
  assertEquals(drafts[1].kind, "commission");
  assertEquals(drafts[1].issuer, "platform");
  assertEquals(drafts[1].valueCents, 1200);
  assertEquals(drafts[1].status, "simulated");
  assertEquals(canEmitService(venue), true);
});

Deno.test("CPF fica sem emissão no serviço e a comissão segue", () => {
  const drafts = planInvoices({
    amountCents: 8000,
    commissionCents: 800,
    playerName: "Ana",
    venue: {
      documentKind: "cpf",
      municipalInscription: "",
      serviceCode: "",
      serviceName: "",
      issRate: 0,
    },
    sandbox: true,
    platform,
  });
  assertEquals(drafts[0].status, "sem_emissao");
  assertEquals(drafts[0].skipReason, "cpf");
  assertEquals(drafts[1].status, "simulated");
});

Deno.test("produção agenda e não simula", () => {
  const drafts = planInvoices({
    amountCents: 8000,
    commissionCents: 800,
    playerName: "Ana",
    venue,
    sandbox: false,
    platform,
  });
  assertEquals(drafts[0].status, "scheduled");
  assertEquals(drafts[1].status, "scheduled");
});

Deno.test("o número de teste é estável", () => {
  assertEquals(
    testInvoiceNumber("S", "grp-cwb-xv-fechado", "user-local"),
    testInvoiceNumber("S", "grp-cwb-xv-fechado", "user-local"),
  );
});

Deno.test("status do Asaas vira o status da tabela", () => {
  assertEquals(mapAsaasInvoiceStatus("AUTHORIZED"), "authorized");
  assertEquals(mapAsaasInvoiceStatus("SCHEDULED"), "processing");
  assertEquals(mapAsaasInvoiceStatus("ERROR"), "error");
  assertEquals(mapAsaasInvoiceStatus("CANCELED"), "canceled");
});
