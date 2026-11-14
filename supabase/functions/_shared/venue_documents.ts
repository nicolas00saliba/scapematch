// Documentos da subconta Asaas. A apiKey não sai da função.
//
// GET /v3/myAccount/documents devolve o onboardingUrl quando o envio é no
// site do Asaas (cadastro.io). Com esse link, POST /v3/myAccount/documents/{id}
// é recusado. O upload daqui só vale para grupo sem onboardingUrl.
// GET /v3/myAccount/status traz documentation e general. Os dois APPROVED
// liberam o saque na tela. A consulta logo após criar a conta pode mentir
// por cerca de 15 segundos; a tela pede para atualizar.

import {
  asaasProductionBaseUrl,
  asaasSandboxBaseUrl,
  type AsaasFetch,
} from "./asaas_provider.ts";
import { isPointsReserve } from "./asaas_transfers.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";

const maxBase64Chars = 2_800_000;
const maxBytes = 2_000_000;

const accountStatuses = [
  "PENDING",
  "AWAITING_APPROVAL",
  "APPROVED",
  "REJECTED",
] as const;

const documentStatuses = [
  "NOT_SENT",
  "PENDING",
  "APPROVED",
  "REJECTED",
] as const;

export type DocumentAccess = "owner" | "partner" | "admin" | "none";

export type PublicDocument = {
  id: string;
  status: string;
  type: string;
  title: string;
  description: string;
  onboarding_url: string | null;
  hosted: boolean;
  upload: boolean;
};

export type PublicDocuments = {
  documentation: string;
  general: string;
  commercial_info: string;
  bank_account_info: string;
  approved: boolean;
  known: boolean;
  onboarding_url: string | null;
  documents: PublicDocument[];
};

export type VenueDocumentDeps = {
  env: EnvLike;
  fetchFn: AsaasFetch;
  actor(jwt: string): Promise<{ id: string } | null>;
  role(venueId: string, userId: string, jwt: string): Promise<DocumentAccess>;
  subaccount(venueId: string): Promise<{ apiKey: string; walletId: string }>;
  strongAuth(jwt: string): Promise<boolean>;
};

export function officialAsaasBase(baseUrl: string): string | null {
  const base = baseUrl.trim().replace(/\/$/, "");
  if (base === asaasSandboxBaseUrl || base === asaasProductionBaseUrl) {
    return base;
  }
  return null;
}

/// Só https em cadastro.io ou asaas.com. Outro host não abre e não volta.
export function safeOnboardingUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length === 0 || value.length > 500) {
    return null;
  }
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password) return null;
  const host = url.hostname.toLowerCase();
  const ok = host === "cadastro.io" ||
    host.endsWith(".cadastro.io") ||
    host === "asaas.com" ||
    host.endsWith(".asaas.com");
  if (!ok) return null;
  return url.toString();
}

export function presentDocuments(
  statusBody: unknown,
  listBody: unknown,
): PublicDocuments {
  const status = record(statusBody) ?? {};
  const documentation = accountStatus(status.documentation);
  const general = accountStatus(status.general);
  const documents = parseGroups(listBody);
  const known = documentation !== "UNKNOWN" && general !== "UNKNOWN";
  const approved = documentation === "APPROVED" && general === "APPROVED";
  const onboarding = documents.find((item) => item.onboarding_url)
    ?.onboarding_url ?? null;
  return {
    documentation,
    general,
    commercial_info: accountStatus(status.commercialInfo),
    bank_account_info: accountStatus(status.bankAccountInfo),
    approved,
    known,
    onboarding_url: onboarding,
    documents,
  };
}

export function decodeDocumentPayload(
  input: string,
): { bytes: Uint8Array; mime: string } | null {
  const trimmed = input.trim();
  if (!trimmed || trimmed.length > maxBase64Chars) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(trimmed)) return null;
  let binary: string;
  try {
    binary = atob(trimmed);
  } catch {
    return null;
  }
  if (binary.length === 0 || binary.length > maxBytes) return null;
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  const mime = sniff(bytes);
  if (!mime) return null;
  return { bytes, mime };
}

export async function handleVenueDocuments(
  req: Request,
  deps: VenueDocumentDeps,
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  try {
    const body = await req.json().catch(() => null) as
      | Record<string, unknown>
      | null;
    const action = text(body?.action);
    const venueId = text(body?.venue_id);
    if (!isUuid(venueId)) return json({ error: "valor" }, 400);
    const jwt = bearer(req);
    const actor = await deps.actor(jwt);
    if (!actor) return json({ error: "not authenticated" }, 401);
    const role = await deps.role(venueId, actor.id, jwt);
    if (role === "none") return json({ error: "not owner" }, 403);
    if (action !== "list" && action !== "upload") {
      return json({ error: "valor" }, 400);
    }
    if (action === "upload") {
      const allowed = await deps.strongAuth(jwt);
      if (!allowed) return json({ error: "reauth" }, 401);
    }
    const account = await deps.subaccount(venueId);
    const apiKey = account.apiKey.trim();
    if (!apiKey) return json({ error: "sem subconta" }, 409);
    if (isPointsReserve(deps.env, account.walletId, apiKey)) {
      return json({ error: "reserva" }, 403);
    }
    const base = officialAsaasBase(
      deps.env.get("ASAAS_BASE_URL") ?? asaasSandboxBaseUrl,
    );
    if (!base) return json({ error: "asaas_unavailable" }, 503);
    if (action === "upload") {
      const uploaded = await uploadDocument(deps, base, apiKey, body, json);
      if (uploaded instanceof Response) return uploaded;
      return json(uploaded);
    }
    return json(await loadFromAsaas(deps.fetchFn, base, apiKey));
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (message === "onboarding") {
      return json({ error: "onboarding" }, 409);
    }
    if (message === "arquivo") return json({ error: "arquivo" }, 400);
    if (message === "status") return json({ error: "status" }, 409);
    return json({ error: "asaas_unavailable" }, 502);
  }
}

async function uploadDocument(
  deps: VenueDocumentDeps,
  base: string,
  apiKey: string,
  body: Record<string, unknown> | null,
  json: (body: unknown, status?: number) => Response,
): Promise<PublicDocuments | Response> {
  const documentId = text(body?.document_id);
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(documentId)) {
    return json({ error: "valor" }, 400);
  }
  const payload = decodeDocumentPayload(text(body?.content_base64));
  if (!payload) return json({ error: "arquivo" }, 400);
  const current = await loadFromAsaas(deps.fetchFn, base, apiKey);
  const group = current.documents.find((item) => item.id === documentId);
  if (!group) return json({ error: "valor" }, 404);
  if (group.hosted) {
    return json({
      error: "onboarding",
      onboarding_url: group.onboarding_url,
    }, 409);
  }
  if (!group.upload || !/^[A-Z0-9_]{1,40}$/.test(group.type)) {
    return json({ error: "status" }, 409);
  }
  const form = new FormData();
  form.append("type", group.type);
  const buffer = new ArrayBuffer(payload.bytes.byteLength);
  new Uint8Array(buffer).set(payload.bytes);
  form.append(
    "documentFile",
    new Blob([buffer], { type: payload.mime }),
    fileName(payload.mime),
  );
  const response = await deps.fetchFn(
    `${base}/myAccount/documents/${documentId}`,
    {
      method: "POST",
      headers: asaasHeaders(apiKey),
      body: form,
    },
  );
  if (!response.ok) return json({ error: "asaas_unavailable" }, 502);
  return await loadFromAsaas(deps.fetchFn, base, apiKey);
}

async function loadFromAsaas(
  fetchFn: AsaasFetch,
  base: string,
  apiKey: string,
): Promise<PublicDocuments> {
  const headers = asaasHeaders(apiKey);
  const [statusRes, docsRes] = await Promise.all([
    fetchFn(`${base}/myAccount/status`, { method: "GET", headers }),
    fetchFn(`${base}/myAccount/documents`, { method: "GET", headers }),
  ]);
  if (!statusRes.ok || !docsRes.ok) {
    throw new Error("asaas");
  }
  const statusBody = await statusRes.json().catch(() => null);
  const listBody = await docsRes.json().catch(() => null);
  return presentDocuments(statusBody, listBody);
}

function asaasHeaders(apiKey: string): Record<string, string> {
  return {
    access_token: apiKey,
    "User-Agent": "EscapeMatch",
    Accept: "application/json",
  };
}

function parseGroups(body: unknown): PublicDocument[] {
  const source = Array.isArray(body)
    ? body
    : Array.isArray(record(body)?.data)
    ? record(body)?.data as unknown[]
    : record(body)?.id
    ? [body]
    : [];
  const documents: PublicDocument[] = [];
  for (const item of source) {
    const row = record(item);
    if (!row) continue;
    const id = text(row.id);
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(id)) continue;
    const rawUrl = text(row.onboardingUrl);
    const hosted = rawUrl.length > 0;
    const onboarding = hosted ? safeOnboardingUrl(rawUrl) : null;
    const status = documentStatus(row.status);
    const type = text(row.type).slice(0, 40);
    const upload = !hosted &&
      (status === "NOT_SENT" || status === "REJECTED") &&
      /^[A-Z0-9_]{1,40}$/.test(type);
    documents.push({
      id,
      status,
      type,
      title: publicText(row.title, 120),
      description: publicText(row.description, 300),
      onboarding_url: onboarding,
      hosted,
      upload,
    });
  }
  return documents;
}

function accountStatus(value: unknown): string {
  const textValue = text(value);
  return accountStatuses.includes(textValue as typeof accountStatuses[number])
    ? textValue
    : "UNKNOWN";
}

function documentStatus(value: unknown): string {
  const textValue = text(value);
  return documentStatuses.includes(
      textValue as typeof documentStatuses[number],
    )
    ? textValue
    : "UNKNOWN";
}

function sniff(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 4 && bytes[0] === 0x25 && bytes[1] === 0x50 &&
    bytes[2] === 0x44 && bytes[3] === 0x46
  ) {
    return "application/pdf";
  }
  return null;
}

function fileName(mime: string): string {
  if (mime === "application/pdf") return "documento.pdf";
  if (mime === "image/png") return "documento.png";
  return "documento.jpg";
}

function publicText(value: unknown, max: number): string {
  const clean = text(value).replace(/\s+/g, " ");
  if (!clean || clean.includes("@")) return "";
  return clean.length > max ? clean.slice(0, max) : clean;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function record(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function bearer(req: Request): string {
  const header = req.headers.get("Authorization") ?? "";
  return header.replace(/^Bearer\s+/i, "").trim();
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(value);
}
