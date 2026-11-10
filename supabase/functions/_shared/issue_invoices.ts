// Emite as duas NFS-e quando a cobrança já está paga e o grupo fechou.
// No sandbox não chama /v3/invoices: grava status simulated com links de teste.
// Em produção usa a chave da subconta para o serviço e a chave raiz para a comissão.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { storedFailure } from "./asaas_client_error.ts";
import { customerWithCpf, playerCpfDigits } from "./player_cpf.ts";
import {
  AsaasProvider,
  centsToReais,
  type ScheduleInvoiceInput,
} from "./asaas_provider.ts";
import { commissionCents } from "./asaas_provider.ts";
import {
  type InvoiceDraft,
  mapAsaasInvoiceStatus,
  planInvoices,
  testInvoiceNumber,
  testPdfUrl,
  testXmlUrl,
  type VenueFiscal,
} from "./fiscal_plan.ts";
import { todayInSaoPaulo } from "./http.ts";

// O cliente do Supabase muda o genérico entre chamadas. A função só usa
// from/select/insert, e o webhook já entrega esse cliente.
// deno-lint-ignore no-explicit-any
type Admin = any;

type ChargeRow = {
  id: string;
  group_id: string;
  user_id: string;
  venue_id: string;
  amount_cents: number;
  commission_bps: number;
};

const defaultPlatform = {
  serviceCode: "17.02",
  serviceName: "Intermediação de reservas",
  issRate: 2,
};

export async function issuePaidInvoices(
  admin: Admin,
  charge: ChargeRow,
  options: { sandbox: boolean; asaas?: AsaasProvider },
): Promise<void> {
  const closed = await groupIsClosed(admin, charge.group_id);
  if (!closed) return;

  const { data: existing } = await admin
    .from("fiscal_invoices")
    .select("kind")
    .eq("payment_charge_id", charge.id);
  const have = new Set(
    ((existing ?? []) as Array<{ kind: string }>).map((row) => row.kind),
  );
  if (
    have.has("service") &&
    (have.has("commission") ||
      commissionCents(charge.amount_cents, charge.commission_bps) === 0)
  ) {
    return;
  }

  const venue = await loadVenue(admin, charge.venue_id);
  if (!venue) return;
  const playerName = await playerNameOf(admin, charge.user_id);
  const fiscal = venue.fiscal;
  const fee = commissionCents(charge.amount_cents, charge.commission_bps);
  const drafts = planInvoices({
    amountCents: charge.amount_cents,
    commissionCents: fee,
    playerName,
    venue: fiscal,
    sandbox: options.sandbox,
    platform: platformFromEnv(),
  });

  for (const draft of drafts) {
    if (have.has(draft.kind)) continue;
    await writeDraft(admin, charge, draft, options);
  }
}

export async function cancelInvoicesForCharge(
  admin: Admin,
  chargeId: string,
  options: { sandbox: boolean; asaas?: AsaasProvider },
): Promise<void> {
  const { data } = await admin
    .from("fiscal_invoices")
    .select("id, status, provider_invoice_id, issuer")
    .eq("payment_charge_id", chargeId);
  const rows = (data ?? []) as Array<{
    id: string;
    status: string;
    provider_invoice_id: string | null;
    issuer: string;
  }>;
  for (const row of rows) {
    if (row.status === "sem_emissao" || row.status === "canceled") continue;
    if (
      !options.sandbox &&
      options.asaas &&
      row.provider_invoice_id &&
      row.status === "authorized"
    ) {
      try {
        const client = row.issuer === "venue"
          ? await venueClient(admin, options.asaas, row.id)
          : options.asaas;
        if (client) await client.cancelInvoice(row.provider_invoice_id);
      } catch (error) {
        await admin.from("fiscal_invoices").update({
          error_message: storedFailure("issue_invoices", error),
        }).eq("id", row.id);
      }
    }
    await admin.from("fiscal_invoices").update({
      status: "canceled",
    }).eq("id", row.id);
  }
}

async function venueClient(
  admin: Admin,
  root: AsaasProvider,
  invoiceId: string,
): Promise<AsaasProvider | null> {
  const { data: invoice } = await admin
    .from("fiscal_invoices")
    .select("venue_id")
    .eq("id", invoiceId)
    .maybeSingle();
  if (!invoice) return null;
  const apiKey = await venueApiKey(admin, invoice.venue_id as string);
  if (!apiKey) return null;
  return root.withKey(apiKey);
}

async function writeDraft(
  admin: Admin,
  charge: ChargeRow,
  draft: InvoiceDraft,
  options: { sandbox: boolean; asaas?: AsaasProvider },
) {
  const suffix = draft.kind === "service" ? "S" : "C";
  const number = draft.status === "simulated"
    ? testInvoiceNumber(suffix, charge.group_id, charge.user_id)
    : null;
  const base = {
    payment_charge_id: charge.id,
    group_id: charge.group_id,
    venue_id: charge.venue_id,
    player_user_id: charge.user_id,
    issuer: draft.issuer,
    kind: draft.kind,
    status: draft.status,
    skip_reason: draft.skipReason,
    number,
    pdf_url: number ? testPdfUrl(number) : null,
    xml_url: number ? testXmlUrl(number) : null,
    value_cents: draft.valueCents,
    iss_rate: draft.issRate,
    service_code: draft.serviceCode,
    description: draft.description,
    effective_date: todayInSaoPaulo(),
    issued_at: draft.status === "simulated" || draft.status === "sem_emissao"
      ? new Date().toISOString()
      : null,
  };

  if (draft.status !== "scheduled" || !options.asaas) {
    await insertInvoice(admin, base);
    return;
  }

  try {
    const emitted = await emitOnAsaas(admin, options.asaas, charge, draft);
    await insertInvoice(admin, {
      ...base,
      status: emitted.status,
      number: emitted.number || null,
      pdf_url: emitted.pdfUrl || null,
      xml_url: emitted.xmlUrl || null,
      provider_invoice_id: emitted.id,
      issued_at: emitted.status === "authorized"
        ? new Date().toISOString()
        : null,
      error_message: emitted.status === "error" ? "Asaas recusou a nota" : null,
    });
  } catch (error) {
    await insertInvoice(admin, {
      ...base,
      status: "error",
      error_message: storedFailure("issue_invoices", error),
    });
  }
}

async function insertInvoice(admin: Admin, row: Record<string, unknown>) {
  const { error } = await admin.from("fiscal_invoices").insert(row);
  if (!error) return;
  if (error.code === "23505") return;
  throw new Error("erro");
}

async function emitOnAsaas(
  admin: Admin,
  root: AsaasProvider,
  charge: ChargeRow,
  draft: InvoiceDraft,
): Promise<
  { id: string; status: string; number: string; pdfUrl: string; xmlUrl: string }
> {
  const client = draft.issuer === "venue"
    ? await subaccount(admin, root, charge.venue_id)
    : root;
  const customer = draft.issuer === "venue"
    ? await ensurePlayerCustomer(admin, client, charge)
    : await ensureHouseCustomer(admin, root, charge.venue_id);
  const input: ScheduleInvoiceInput = {
    customer,
    serviceDescription: draft.description,
    observations: "Nota emitida pelo EscapeMatch na confirmação da reserva.",
    value: centsToReais(draft.valueCents),
    deductions: 0,
    effectiveDate: todayInSaoPaulo(),
    municipalServiceCode: draft.serviceCode ?? "",
    municipalServiceName: draft.serviceName ?? "",
    externalReference: `${draft.kind}:${charge.id}`,
    taxes: {
      retainIss: false,
      iss: draft.issRate ?? 0,
      cofins: 0,
      csll: 0,
      inss: 0,
      ir: 0,
      pis: 0,
    },
  };
  const scheduled = await client.scheduleInvoice(input);
  await client.authorizeInvoice(scheduled.id);
  const view = await client.getInvoice(scheduled.id);
  return {
    id: view.id,
    status: mapAsaasInvoiceStatus(view.status),
    number: view.number,
    pdfUrl: view.pdfUrl,
    xmlUrl: view.xmlUrl,
  };
}

async function subaccount(
  admin: Admin,
  root: AsaasProvider,
  venueId: string,
): Promise<AsaasProvider> {
  const apiKey = await venueApiKey(admin, venueId);
  if (!apiKey) {
    throw new Error(
      "Subconta sem apiKey. Rode provision-venue-wallet de novo.",
    );
  }
  return root.withKey(apiKey);
}

async function venueApiKey(
  admin: Admin,
  venueId: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("read_venue_asaas_key", {
    p_venue_id: venueId,
  });
  if (error || typeof data !== "string" || data.length === 0) return null;
  return data;
}

async function ensurePlayerCustomer(
  admin: Admin,
  client: AsaasProvider,
  charge: ChargeRow,
): Promise<string> {
  const { data: found } = await admin
    .from("asaas_customers")
    .select("asaas_customer_id")
    .eq("scope", "venue_player")
    .eq("venue_id", charge.venue_id)
    .eq("user_id", charge.user_id)
    .maybeSingle();
  const name = await playerNameOf(admin, charge.user_id);
  const email = await emailOf(admin, charge.user_id);
  const cpf = playerCpfDigits(await playerCpfOf(admin, charge.user_id));
  if (!cpf) {
    const error = new Error("cpf_required");
    error.name = "CpfRequired";
    throw error;
  }
  const customerId = await customerWithCpf(client, {
    customerId: (found?.asaas_customer_id as string | null) ?? null,
    name,
    email: email ?? `jogador-${charge.user_id}@escapematch.invalid`,
    externalReference: `player:${charge.venue_id}:${charge.user_id}`,
    cpf,
  });
  if (!found?.asaas_customer_id) {
    await admin.from("asaas_customers").insert({
      scope: "venue_player",
      venue_id: charge.venue_id,
      user_id: charge.user_id,
      asaas_customer_id: customerId,
    });
  }
  return customerId;
}

async function ensureHouseCustomer(
  admin: Admin,
  client: AsaasProvider,
  venueId: string,
): Promise<string> {
  const { data: found } = await admin
    .from("asaas_customers")
    .select("asaas_customer_id")
    .eq("scope", "platform_house")
    .eq("venue_id", venueId)
    .maybeSingle();
  if (found?.asaas_customer_id) return found.asaas_customer_id as string;
  const venue = await loadVenue(admin, venueId);
  if (!venue) throw new Error("Casa ausente");
  const ownerEmail = await emailOf(admin, venue.ownerId);
  const created = await client.createCustomer({
    name: venue.name,
    email: ownerEmail ?? `casa-${venueId}@escapematch.invalid`,
    cpfCnpj: venue.documentNumber,
    externalReference: `house:${venueId}`,
  });
  await admin.from("asaas_customers").insert({
    scope: "platform_house",
    venue_id: venueId,
    user_id: null,
    asaas_customer_id: created.id,
  });
  return created.id;
}

async function groupIsClosed(admin: Admin, groupId: string): Promise<boolean> {
  const { data: group } = await admin
    .from("groups")
    .select("closed_at, total_spots, minimum_spots, cancelled_at")
    .eq("id", groupId)
    .maybeSingle();
  if (!group || group.cancelled_at) return false;
  if (group.closed_at) return true;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  const filled = count ?? 0;
  const total = Number(group.total_spots);
  const minimum = Number(group.minimum_spots);
  return filled >= total && filled >= minimum;
}

async function loadVenue(admin: Admin, venueId: string): Promise<
  {
    name: string;
    ownerId: string;
    documentNumber: string;
    fiscal: VenueFiscal;
  } | null
> {
  const { data: venue } = await admin
    .from("venues")
    .select("name, owner_id, document_kind, document_number")
    .eq("id", venueId)
    .maybeSingle();
  if (!venue) return null;
  const { data: fiscal } = await admin
    .from("venue_fiscal")
    .select("municipal_inscription, service_code, service_name, iss_rate")
    .eq("venue_id", venueId)
    .maybeSingle();
  return {
    name: venue.name as string,
    ownerId: venue.owner_id as string,
    documentNumber: venue.document_number as string,
    fiscal: {
      documentKind: venue.document_kind === "cnpj" ? "cnpj" : "cpf",
      municipalInscription: (fiscal?.municipal_inscription as string) ?? "",
      serviceCode: (fiscal?.service_code as string) ?? "",
      serviceName: (fiscal?.service_name as string) ?? "",
      issRate: Number(fiscal?.iss_rate ?? 0),
    },
  };
}

async function playerCpfOf(admin: Admin, userId: string): Promise<unknown> {
  const { data } = await admin
    .from("profiles")
    .select("cpf")
    .eq("id", userId)
    .maybeSingle();
  return data?.cpf;
}

async function playerNameOf(admin: Admin, userId: string): Promise<string> {
  const { data } = await admin
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .maybeSingle();
  const name = data?.display_name as string | undefined;
  return name && name.length > 0 ? name : "Jogador";
}

async function emailOf(admin: Admin, userId: string): Promise<string | null> {
  const user = await admin.auth.admin.getUserById(userId);
  return user.data.user?.email ?? null;
}

function platformFromEnv() {
  const code = Deno.env.get("ASAAS_FISCAL_SERVICE_CODE");
  const name = Deno.env.get("ASAAS_FISCAL_SERVICE_NAME");
  const iss = Number(Deno.env.get("ASAAS_FISCAL_ISS") ?? "");
  if (!code || !name || !(iss > 0)) return defaultPlatform;
  return { serviceCode: code, serviceName: name, issRate: iss };
}
