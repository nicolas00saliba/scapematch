// Emite as duas NFS-e quando a cobrança já está paga e o grupo fechou.
// No sandbox não chama /v3/invoices: grava status simulated com links de teste.
// Em produção a emissão fica desligada até ASAAS_INVOICE_EMISSION=on.
// Desligada, a nota que seria enviada fica scheduled, sem chamar o Asaas,
// para sair depois que o certificado A1 estiver na conta. A cobrança não falha.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import {
  asaasUnavailable,
  asaasErrorItems,
  isAsaasFailure,
  logCaught,
  storedFailure,
} from "./asaas_client_error.ts";
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
import { bandConfirmed } from "./group_band.ts";
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

/// Só o valor `on` liga a emissão. Qualquer outra coisa, inclusive vazio, desliga.
export const invoiceEmissionSetting = "ASAAS_INVOICE_EMISSION";

export function invoiceEmissionEnabled(
  env: { get(name: string): string | undefined },
): boolean {
  try {
    return (env.get(invoiceEmissionSetting) ?? "").trim().toLowerCase() === "on";
  } catch {
    return false;
  }
}

/// Produção com a chave ligada e cliente Asaas. Sandbox continua simulado.
export function shouldEmitInvoice(input: {
  status: string;
  sandbox: boolean;
  emissionEnabled: boolean;
  hasClient: boolean;
}): boolean {
  return input.status === "scheduled" &&
    !input.sandbox &&
    input.emissionEnabled &&
    input.hasClient;
}

/// Tentativas de uma nota que falhou sem id no Asaas.
export const invoiceAttemptLimit = 5;

/// Uma trava `processing` mais velha que isso pode ser reaberta.
export const invoiceProcessingStaleMs = 15 * 60 * 1000;

/// Sem certificado e indisponibilidade do Asaas podem sair de novo.
export function invoiceErrorRetryable(reason: unknown): boolean {
  return reason === "sem_certificado" || reason === asaasUnavailable;
}

export function invoiceFailureReason(error: unknown): string {
  const blob = asaasErrorItems(error)
    .map((item) => item.description)
    .join(" ")
    .toLowerCase();
  if (blob.includes("certificado")) return "sem_certificado";
  if (isAsaasFailure(error)) return asaasUnavailable;
  return storedFailure("issue_invoices", error);
}

type StoredInvoice = {
  id: string;
  kind: string;
  status: string;
  provider_invoice_id: string | null;
  attempt_count: number;
  updated_at: string | null;
  error_message: string | null;
};

export async function issuePaidInvoices(
  admin: Admin,
  charge: ChargeRow,
  options: { sandbox: boolean; asaas?: AsaasProvider; emissionEnabled?: boolean },
): Promise<void> {
  try {
    await issuePaidInvoicesBody(admin, charge, options);
  } catch (error) {
    logCaught("issue_invoices", error);
  }
}

/// Reprocessa notas em error por motivo transitório, com a chave ligada.
export async function retryFailedInvoices(
  admin: Admin,
  options: { sandbox: boolean; asaas?: AsaasProvider; emissionEnabled?: boolean },
): Promise<number> {
  const emissionEnabled = options.emissionEnabled ??
    invoiceEmissionEnabled(safeEnv());
  if (!emissionEnabled || options.sandbox || !options.asaas) return 0;
  const { data } = await admin
    .from("fiscal_invoices")
    .select(
      "payment_charge_id, error_message, attempt_count, provider_invoice_id, status",
    )
    .eq("status", "error")
    .is("provider_invoice_id", null)
    .lt("attempt_count", invoiceAttemptLimit)
    .limit(20);
  const ids = new Set<string>();
  for (const row of (data ?? []) as Array<Record<string, unknown>>) {
    if (!invoiceErrorRetryable(row.error_message)) continue;
    if (row.provider_invoice_id) continue;
    if (typeof row.payment_charge_id !== "string") continue;
    ids.add(row.payment_charge_id);
  }
  let retried = 0;
  for (const id of ids) {
    const { data: row } = await admin
      .from("payment_charges")
      .select("id, group_id, user_id, venue_id, amount_cents, commission_bps")
      .eq("id", id)
      .maybeSingle();
    if (!row?.id || !row.group_id || !row.user_id || !row.venue_id) continue;
    await issuePaidInvoices(admin, {
      id: String(row.id),
      group_id: String(row.group_id),
      user_id: String(row.user_id),
      venue_id: String(row.venue_id),
      amount_cents: Number(row.amount_cents),
      commission_bps: Number(row.commission_bps),
    }, { ...options, emissionEnabled });
    retried += 1;
  }
  return retried;
}

async function issuePaidInvoicesBody(
  admin: Admin,
  charge: ChargeRow,
  options: { sandbox: boolean; asaas?: AsaasProvider; emissionEnabled?: boolean },
): Promise<void> {
  const emissionEnabled = options.emissionEnabled ??
    invoiceEmissionEnabled(safeEnv());
  const resolved = { ...options, emissionEnabled };
  const closed = await groupIsClosed(admin, charge.group_id);
  if (!closed) return;

  const stored = await loadInvoices(admin, charge.id);
  const byKind = new Map(stored.map((row) => [row.kind, row]));

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
    sandbox: resolved.sandbox,
    platform: platformFromEnv(),
  });

  for (const draft of drafts) {
    await writeDraft(admin, charge, draft, resolved, byKind.get(draft.kind));
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
  options: { sandbox: boolean; asaas?: AsaasProvider; emissionEnabled: boolean },
  existing?: StoredInvoice,
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
    attempt_count: 0,
    error_message: null,
  };

  const emit = shouldEmitInvoice({
    status: draft.status,
    sandbox: options.sandbox,
    emissionEnabled: options.emissionEnabled,
    hasClient: Boolean(options.asaas),
  });
  if (!emit || !options.asaas) {
    if (existing) return;
    await insertInvoice(admin, base);
    return;
  }

  let row = existing;
  if (!row) {
    const inserted = await insertInvoice(admin, { ...base, status: "scheduled" });
    row = inserted ?? await reloadKind(admin, charge.id, draft.kind);
  }
  if (!row || row.provider_invoice_id) return;
  const now = new Date();
  if (!invoiceClaimable(row, now)) return;
  const won = await claimInvoice(admin, row, now);
  if (!won) return;

  try {
    const emitted = await emitOrAdopt(admin, options.asaas, charge, draft);
    await admin.from("fiscal_invoices").update({
      status: emitted.status,
      number: emitted.number || null,
      pdf_url: emitted.pdfUrl || null,
      xml_url: emitted.xmlUrl || null,
      provider_invoice_id: emitted.id,
      issued_at: emitted.status === "authorized" ? now.toISOString() : null,
      error_message: emitted.status === "error" ? "Asaas recusou a nota" : null,
      updated_at: new Date().toISOString(),
    }).eq("id", row.id).eq("status", "processing");
  } catch (error) {
    await admin.from("fiscal_invoices").update({
      status: "error",
      error_message: invoiceFailureReason(error),
      updated_at: new Date().toISOString(),
    }).eq("id", row.id).eq("status", "processing");
  }
}

function invoiceClaimable(row: StoredInvoice, now: Date): boolean {
  if (row.status === "scheduled") return true;
  if (row.status === "error") {
    return invoiceErrorRetryable(row.error_message) &&
      row.attempt_count < invoiceAttemptLimit;
  }
  if (row.status !== "processing" || !row.updated_at) return false;
  const at = Date.parse(row.updated_at);
  return Number.isFinite(at) && now.getTime() - at >= invoiceProcessingStaleMs;
}

async function claimInvoice(
  admin: Admin,
  row: StoredInvoice,
  now: Date,
): Promise<boolean> {
  let query = admin
    .from("fiscal_invoices")
    .update({
      status: "processing",
      updated_at: now.toISOString(),
      attempt_count: row.attempt_count + 1,
    })
    .eq("id", row.id)
    .eq("status", row.status)
    .is("provider_invoice_id", null);
  if (row.status === "error") {
    query = query.lt("attempt_count", invoiceAttemptLimit);
  }
  if (row.status === "processing") {
    query = query.lt(
      "updated_at",
      new Date(now.getTime() - invoiceProcessingStaleMs).toISOString(),
    );
  }
  const { data, error } = await query.select("id");
  return !error && Array.isArray(data) && data.length > 0;
}

async function emitOrAdopt(
  admin: Admin,
  root: AsaasProvider,
  charge: ChargeRow,
  draft: InvoiceDraft,
): Promise<{
  id: string;
  status: string;
  number: string;
  pdfUrl: string;
  xmlUrl: string;
}> {
  const client = draft.issuer === "venue"
    ? await subaccount(admin, root, charge.venue_id)
    : root;
  const reference = `${draft.kind}:${charge.id}`;
  const found = await client.findInvoiceByReference(reference);
  if (found) {
    const view = await client.getInvoice(found.id);
    return {
      id: view.id,
      status: mapAsaasInvoiceStatus(view.status),
      number: view.number,
      pdfUrl: view.pdfUrl,
      xmlUrl: view.xmlUrl,
    };
  }
  return await emitOnAsaas(admin, root, charge, draft);
}

async function loadInvoices(
  admin: Admin,
  chargeId: string,
): Promise<StoredInvoice[]> {
  const { data } = await admin
    .from("fiscal_invoices")
    .select(
      "id, kind, status, provider_invoice_id, attempt_count, updated_at, error_message",
    )
    .eq("payment_charge_id", chargeId);
  return ((data ?? []) as Array<Record<string, unknown>>).map(asStored);
}

async function reloadKind(
  admin: Admin,
  chargeId: string,
  kind: string,
): Promise<StoredInvoice | undefined> {
  const rows = await loadInvoices(admin, chargeId);
  return rows.find((row) => row.kind === kind);
}

function asStored(row: Record<string, unknown>): StoredInvoice {
  const attempts = Number(row.attempt_count);
  return {
    id: String(row.id ?? ""),
    kind: String(row.kind ?? ""),
    status: String(row.status ?? ""),
    provider_invoice_id: typeof row.provider_invoice_id === "string"
      ? row.provider_invoice_id
      : null,
    attempt_count: Number.isInteger(attempts) && attempts > 0 ? attempts : 0,
    updated_at: typeof row.updated_at === "string" ? row.updated_at : null,
    error_message: typeof row.error_message === "string"
      ? row.error_message
      : null,
  };
}

async function insertInvoice(
  admin: Admin,
  row: Record<string, unknown>,
): Promise<StoredInvoice | null> {
  const stored = {
    ...row,
    id: typeof row.id === "string" ? row.id : crypto.randomUUID(),
    attempt_count: 0,
    updated_at: new Date().toISOString(),
  };
  const { data, error } = await admin.from("fiscal_invoices").insert(stored);
  if (!error) {
    const saved = Array.isArray(data) && data[0] ? data[0] : stored;
    return asStored(saved as Record<string, unknown>);
  }
  if (error.code === "23505") return null;
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
    .select(
      "cancelled_at, confirmed_at, closed_at, closes_at, total_spots, minimum_spots",
    )
    .eq("id", groupId)
    .maybeSingle();
  if (!group) return false;
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return bandConfirmed(group, count ?? 0);
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
  const code = envValue("ASAAS_FISCAL_SERVICE_CODE");
  const name = envValue("ASAAS_FISCAL_SERVICE_NAME");
  const iss = Number(envValue("ASAAS_FISCAL_ISS"));
  if (!code || !name || !(iss > 0)) return defaultPlatform;
  return { serviceCode: code, serviceName: name, issRate: iss };
}

function envValue(name: string): string {
  try {
    return Deno.env.get(name) ?? "";
  } catch {
    return "";
  }
}

function safeEnv(): { get(name: string): string | undefined } {
  return {
    get(name: string) {
      try {
        return Deno.env.get(name);
      } catch {
        return undefined;
      }
    },
  };
}
