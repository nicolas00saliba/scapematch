// Cadastro de conta SELLER na PagBank. O cliente não vê token, client id
// nem client secret. CPF e CNPJ não entram em log nem em tabela.
//
// Sonda (não cria conta): POST /accounts com o corpo {"type":"SELLER"}.
// Liga a flag só com HTTP 400, error_messages 40001 ou 40002 em todos os
// itens, parameter_name preenchido, e sem ACCO_, token ou texto de
// permissão. 401, 403, 404, 2xx e o resto ficam desligados.

import { clientIp } from "./client_ip.ts";
import { resolveCronSecret, type SecretCache } from "./cron_secret.ts";
import { bindJson, corsHeadersFor, type EnvLike } from "./http.ts";
import {
  isOfficialPagBankBase,
  pagbankApiBaseUrl,
} from "./pagbank_provider.ts";
import { secretMatches } from "./venue_payouts.ts";

export const pagbankSignupUrl = "https://cadastro.pagbank.com.br/";

export const pagbankBusinessCategories = [
  "BUTCHERY",
  "LEGAL_SERVICE",
  "TAILOR_AND_SEAMSTRESS",
  "ITINERANT_SALE",
  "ARCHITECTURAL_AND_ENGINEERING",
  "ART_AND_ANTIQUE",
  "RELIGION_AND_SPIRITUALITY",
  "VEHICLE_AND_PARTS",
  "BABY",
  "VEHICLE_SERVICES",
  "BEAUTY_AND_BARBER",
  "BED_AND_BATH",
  "TELECOMMUNICATION",
  "KEY_CHAIN",
  "PACKAGE_STORE",
  "FOOD_SERVICE",
  "ADULT_CONTENT",
  "REAL_ESTATE_AGENT",
  "BROKER",
  "DENTISTRY",
  "FREIGHT_FORWARDER",
  "CANDIES_AND_CONFECTIONERIES",
  "HOUSEHOLD_APPLIANCE",
  "GENERAL_CONTRACTOR",
  "GOVERNMENT",
  "SPORT",
  "HEALTH_AND_BEAUTY_SERVICE",
  "NONDURABLE_GOODS",
  "MEDICAL_SERVICE",
  "PHOTOGRAPHY_AND_VIDEO",
  "SUPERMARKET",
  "LODGING",
  "FLORIST",
  "JEWELRY_AND_WATCH",
  "OTHER_SERVICES",
  "DOCTOR",
  "FURNITURE_AND_DECORATION",
  "BAKERY",
  "PERSONAL_TRAINER",
  "PET_SUPPLIES",
  "PODIATRIST_AND_CHIROPODIST",
  "REPAIR_SHOPS",
  "RESTAURANT",
  "CLOTHING_AND_ACCESSORIES",
  "SHOE_STORE",
  "EDUCATION",
  "ENTERTAINMENT",
  "PROFESSIONAL_SERVICE",
  "TATTOOIST",
  "TRANSPORTATION_SERVICE",
  "DOOR_TO_DOOR_SALES",
  "VETERINARY_SERVICE",
] as const;

const categorySet = new Set<string>(pagbankBusinessCategories);

const regions = new Set([
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS",
  "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC",
  "SP", "SE", "TO",
]);

const accountIdPattern =
  /^ACCO_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

const probeCodePattern = /^[a-z0-9_]{1,48}$/;

const permissionText =
  /unauthorized|forbidden|permission|not_authorized|access_denied|invalid_scope|insufficient_scope|escopo/i;

export const signupProbeBody = Object.freeze({ type: "SELLER" });

export type SignupDraft = {
  venueId: string;
  documentKind: "cpf" | "cnpj";
  documentNumber: string;
  companyName: string;
  postalCode: string;
  street: string;
  number: string;
  complement: string;
  locality: string;
  city: string;
  regionCode: string;
  responsibleName: string;
  responsibleCpf: string;
  birthDate: string;
  phone: string;
  email: string;
  businessCategory: string;
};

export type ProbeDecision =
  | { decision: "enabled"; code: "40001" | "40002" }
  | { decision: "closed"; code: string }
  | { decision: "accident"; code: "probe_criou_conta" };

export type SignupActor = { id: string; admin: boolean };

export type SignupVenue = { id: string; ownerId: string; status: string };

export type SignupStore = {
  actor(authHeader: string): Promise<SignupActor | null>;
  venue(id: string): Promise<SignupVenue | null>;
  apiEnabled(): Promise<boolean>;
  existingAccount(venueId: string): Promise<string | null>;
  saveAccount(input: {
    venueId: string;
    status: string;
    accountId: string | null;
    documentKind: "cpf" | "cnpj";
    businessCategory: string;
  }): Promise<void>;
};

export type ProbeStore = {
  apply(input: { http: number; code: string; enable: boolean }): Promise<{
    enabled: boolean;
    changed: boolean;
  }>;
};

export type SignupFetch = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export function classifySignupProbe(status: number, raw: string): ProbeDecision {
  if (status === 200 || status === 201) {
    return { decision: "accident", code: "probe_criou_conta" };
  }
  if (status === 401) return { decision: "closed", code: "http_401" };
  if (status === 403) return { decision: "closed", code: "http_403" };
  if (status === 404) return { decision: "closed", code: "http_404" };
  if (status !== 400) {
    const code = status >= 100 && status <= 599 ? `http_${status}` : "http_0";
    return { decision: "closed", code };
  }
  if (
    raw.includes("ACCO_") ||
    /access_token|refresh_token/i.test(raw) ||
    permissionText.test(raw)
  ) {
    if (raw.includes("ACCO_") || /access_token|refresh_token/i.test(raw)) {
      return { decision: "accident", code: "probe_criou_conta" };
    }
    return { decision: "closed", code: "http_400_auth" };
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { decision: "closed", code: "http_400_sem_json" };
  }
  const items = errorItems(parsed);
  if (items.length === 0) return { decision: "closed", code: "http_400_sem_codigo" };
  const codes = items.map((item) => item.code);
  if (codes.some((code) => code !== "40001" && code !== "40002")) {
    return { decision: "closed", code: "http_400_misto" };
  }
  const named = items.some((item) => /^[A-Za-z0-9_.]{1,64}$/.test(item.parameter));
  if (!named) return { decision: "closed", code: "http_400_sem_campo" };
  return { decision: "enabled", code: codes[0] === "40002" ? "40002" : "40001" };
}

export function parseSignup(
  body: Record<string, unknown>,
  today: Date,
): SignupDraft | string {
  const venueId = text(body.venue_id);
  if (!isUuid(venueId)) return "venue_id";
  const documentKind = text(body.document_kind);
  if (documentKind !== "cpf" && documentKind !== "cnpj") return "documento";
  const documentNumber = digits(body.document_number);
  if (documentKind === "cpf" && !cpfOk(documentNumber)) return "documento";
  if (documentKind === "cnpj" && !cnpjOk(documentNumber)) return "documento";
  const responsibleCpf = digits(body.responsible_cpf);
  if (documentKind === "cnpj" && !cpfOk(responsibleCpf)) return "cpf_responsavel";
  if (documentKind === "cpf" && responsibleCpf !== "") return "cpf_responsavel";
  const companyName = collapse(body.company_name);
  const nameLimit = documentKind === "cnpj" ? 144 : 80;
  const nameMin = documentKind === "cnpj" ? 3 : 2;
  if (companyName.length < nameMin || companyName.length > nameLimit) {
    return "razao";
  }
  const street = collapse(body.street);
  const number = collapse(body.number);
  const complement = collapse(body.complement);
  const locality = collapse(body.locality);
  const city = collapse(body.city);
  const regionCode = text(body.region_code).toUpperCase();
  const postalCode = digits(body.postal_code);
  if (
    street.length < 1 || street.length > 150 ||
    number.length < 1 || number.length > 8 ||
    complement.length > 40 ||
    locality.length < 1 || locality.length > 60 ||
    city.length < 1 || city.length > 90 ||
    !regions.has(regionCode) ||
    !/^[0-9]{8}$/.test(postalCode)
  ) {
    return "endereco";
  }
  const responsibleName = collapse(body.responsible_name);
  if (responsibleName.length < 2 || responsibleName.length > 50) {
    return "responsavel";
  }
  const birthDate = text(body.birth_date);
  if (!adultBirth(birthDate, today)) return "nascimento";
  const phone = digits(body.phone);
  if (!/^([1-9][0-9])9[0-9]{8}$/.test(phone)) return "celular";
  const email = text(body.email).toLowerCase();
  if (email.length > 60 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return "email";
  }
  const businessCategory = text(body.business_category);
  if (!categorySet.has(businessCategory)) return "categoria";
  if (body.terms_accepted !== true) return "termos";
  return {
    venueId,
    documentKind,
    documentNumber,
    companyName,
    postalCode,
    street,
    number,
    complement,
    locality,
    city,
    regionCode,
    responsibleName,
    responsibleCpf: documentKind === "cnpj" ? responsibleCpf : "",
    birthDate,
    phone,
    email,
    businessCategory,
  };
}

export function sellerAccountBody(
  draft: SignupDraft,
  userIp: string,
  acceptedAt: Date,
): Record<string, unknown> {
  const personTax = draft.documentKind === "cpf"
    ? draft.documentNumber
    : draft.responsibleCpf;
  const person: Record<string, unknown> = {
    name: draft.responsibleName,
    birth_date: draft.birthDate,
    tax_id: personTax,
    address: addressOf(draft),
    phones: [phoneOf(draft.phone)],
  };
  const body: Record<string, unknown> = {
    type: "SELLER",
    business_category: draft.businessCategory,
    email: draft.email,
    person,
    tos_acceptance: {
      user_ip: userIp,
      date: acceptedAt.toISOString(),
    },
  };
  if (draft.documentKind === "cnpj") {
    body.company = {
      name: draft.companyName,
      tax_id: draft.documentNumber,
      address: addressOf(draft),
      phones: [phoneOf(draft.phone)],
    };
  }
  return body;
}

export function readCreatedAccount(status: number, raw: string): {
  accountId: string;
  accountStatus: "pending_activation" | "exists" | "email";
} | { error: "pagbank_unavailable" | "pagbank_resposta" } {
  const code = firstErrorCode(raw);
  if (code === "42001") return { accountId: "", accountStatus: "exists" };
  if (code === "42002") return { accountId: "", accountStatus: "email" };
  if (status !== 201) return { error: "pagbank_unavailable" };
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { error: "pagbank_resposta" };
  }
  const id = parsed && typeof parsed === "object"
    ? text((parsed as { id?: unknown }).id)
    : "";
  if (!accountIdPattern.test(id)) return { error: "pagbank_resposta" };
  return { accountId: id, accountStatus: "pending_activation" };
}

export async function handlePagbankSignup(
  req: Request,
  deps: {
    env: EnvLike;
    fetchFn: SignupFetch;
    now: () => Date;
    store: SignupStore;
  },
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const actor = await deps.store.actor(req.headers.get("Authorization") ?? "");
  if (!actor) return json({ error: "not authenticated" }, 401);
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "valor" }, 400);
  }
  const record = body as Record<string, unknown>;
  const venueId = text(record.venue_id);
  if (!isUuid(venueId)) return json({ error: "venue_id" }, 400);
  const venue = await deps.store.venue(venueId);
  if (!venue || venue.status !== "approved") return json({ error: "casa" }, 400);
  if (!actor.admin && venue.ownerId !== actor.id) {
    return json({ error: "not owner" }, 403);
  }
  if (!(await deps.store.apiEnabled())) {
    return json({ error: "api_indisponivel" }, 409);
  }
  const parsed = parseSignup(record, deps.now());
  if (typeof parsed === "string") return json({ error: parsed }, 400);
  const existing = await deps.store.existingAccount(venueId);
  if (existing && accountIdPattern.test(existing)) {
    return json({
      mode: "api",
      account_id: existing,
      account_status: "pending_activation",
    });
  }
  const ip = clientIp(req);
  if (!ip) return json({ error: "ip" }, 400);
  const credentials = signupCredentials(deps.env);
  if (!credentials) return json({ error: "pagbank_connect" }, 500);
  const acceptedAt = deps.now();
  const payload = sellerAccountBody(parsed, ip, acceptedAt);
  let status = 0;
  let raw = "";
  try {
    const response = await deps.fetchFn(`${credentials.baseUrl}/accounts`, {
      method: "POST",
      redirect: "error",
      headers: accountHeaders(credentials),
      body: JSON.stringify(payload),
    });
    status = response.status;
    raw = await response.text();
  } catch {
    return json({ error: "pagbank_unavailable" }, 502);
  }
  const created = readCreatedAccount(status, raw);
  if ("error" in created) {
    console.error(JSON.stringify({
      scope: "pagbank-signup",
      code: created.error,
      http: status,
    }));
    return json({ error: created.error }, 502);
  }
  if (created.accountStatus === "email") {
    return json({ error: "conta_email" }, 409);
  }
  const accountStatus = created.accountStatus === "exists"
    ? "exists"
    : "pending_activation";
  await deps.store.saveAccount({
    venueId,
    status: accountStatus,
    accountId: created.accountId || null,
    documentKind: parsed.documentKind,
    businessCategory: parsed.businessCategory,
  });
  if (accountStatus === "exists") {
    return json({ error: "conta_existente", account_status: "exists" }, 409);
  }
  return json({
    mode: "api",
    account_id: created.accountId,
    account_status: "pending_activation",
  });
}

export async function handlePagbankSignupProbe(
  req: Request,
  deps: {
    env: EnvLike;
    fetchFn: SignupFetch;
    store: ProbeStore;
    secretCache?: SecretCache;
    readVault?: () => Promise<unknown>;
    alert: (code: string) => Promise<void>;
  },
): Promise<Response> {
  const json = bindJson(req, deps.env);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, deps.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
  const secret = await resolveCronSecret({
    envValue: deps.env.get("PAGBANK_SIGNUP_PROBE_SECRET"),
    vaultName: "pagbank_signup_probe_secret",
    cache: deps.secretCache,
    readVault: deps.readVault,
  });
  if (secret === "") return json({ error: "config_ausente" }, 503);
  const header = req.headers.get("x-pagbank-signup-probe-secret") ?? "";
  if (!(await secretMatches(header, secret))) {
    return json({ error: "not authenticated" }, 401);
  }
  const credentials = signupCredentials(deps.env);
  if (!credentials) {
    const applied = await deps.store.apply({
      http: 0,
      code: "config_ausente",
      enable: false,
    });
    return json({ ok: true, enabled: applied.enabled, changed: false });
  }
  let status = 0;
  let raw = "";
  try {
    const response = await deps.fetchFn(`${credentials.baseUrl}/accounts`, {
      method: "POST",
      redirect: "error",
      headers: accountHeaders(credentials),
      body: JSON.stringify(signupProbeBody),
    });
    status = response.status;
    raw = (await response.text()).slice(0, 4000);
  } catch {
    status = 0;
    raw = "";
  }
  const decision = status === 0
    ? { decision: "closed" as const, code: "http_0" }
    : classifySignupProbe(status, raw);
  const enable = decision.decision === "enabled";
  const applied = await deps.store.apply({
    http: status,
    code: probeCodePattern.test(decision.code) ? decision.code : "http_0",
    enable,
  });
  if (decision.decision === "accident") {
    await deps.alert("probe_criou_conta");
  } else if (applied.changed) {
    await deps.alert("api_liberada");
  }
  return json({
    ok: true,
    enabled: applied.enabled,
    changed: applied.changed,
  });
}

function signupCredentials(env: EnvLike): {
  baseUrl: string;
  token: string;
  clientId: string;
  clientSecret: string;
} | null {
  const baseUrl = pagbankApiBaseUrl(env);
  if (!isOfficialPagBankBase(baseUrl)) return null;
  const token = (env.get("PAGBANK_TOKEN") ?? "").trim();
  const clientId = (env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "").trim();
  const clientSecret = (env.get("PAGBANK_CONNECT_CLIENT_SECRET") ?? "").trim();
  if (token.length < 8 || clientId.length < 8 || clientSecret.length < 8) {
    return null;
  }
  return { baseUrl, token, clientId, clientSecret };
}

function accountHeaders(credentials: {
  token: string;
  clientId: string;
  clientSecret: string;
}): Record<string, string> {
  return {
    Authorization: `Bearer ${credentials.token}`,
    "x-client-id": credentials.clientId,
    "x-client-secret": credentials.clientSecret,
    "Content-Type": "application/json",
    Accept: "application/json",
    "User-Agent": "EscapeMatch",
  };
}

function addressOf(draft: SignupDraft): Record<string, unknown> {
  const address: Record<string, unknown> = {
    street: draft.street,
    number: draft.number,
    locality: draft.locality,
    city: draft.city,
    region_code: draft.regionCode,
    country: "BRA",
    postal_code: draft.postalCode,
  };
  if (draft.complement) address.complement = draft.complement;
  return address;
}

function phoneOf(phone: string): Record<string, string> {
  return {
    country: "55",
    area: phone.slice(0, 2),
    number: phone.slice(2),
    type: "MOBILE",
  };
}

function errorItems(parsed: unknown): { code: string; parameter: string }[] {
  if (!parsed || typeof parsed !== "object") return [];
  const record = parsed as { error_messages?: unknown; errors?: unknown };
  const list = Array.isArray(record.error_messages)
    ? record.error_messages
    : Array.isArray(record.errors)
    ? record.errors
    : [];
  const items: { code: string; parameter: string }[] = [];
  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const code = text((item as { code?: unknown }).code);
    const parameter = text(
      (item as { parameter_name?: unknown }).parameter_name,
    );
    if (!/^[0-9]{5}$/.test(code)) continue;
    items.push({ code, parameter });
  }
  return items;
}

function firstErrorCode(raw: string): string {
  try {
    const items = errorItems(JSON.parse(raw));
    return items[0]?.code ?? "";
  } catch {
    return "";
  }
}

function adultBirth(value: string, today: Date): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return false;
  }
  const adult = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  const limit = new Date(Date.UTC(adult.getUTCFullYear() - 18, adult.getUTCMonth(), adult.getUTCDate()));
  const oldest = new Date(Date.UTC(adult.getUTCFullYear() - 120, adult.getUTCMonth(), adult.getUTCDate()));
  return date.getTime() <= limit.getTime() && date.getTime() >= oldest.getTime();
}

function cpfOk(value: string): boolean {
  if (!/^[0-9]{11}$/.test(value) || /^(\d)\1{10}$/.test(value)) return false;
  const digit = (length: number, factor: number) => {
    let sum = 0;
    for (let i = 0; i < length; i++) sum += Number(value[i]) * (factor - i);
    const mod = (sum * 10) % 11;
    return mod === 10 ? 0 : mod;
  };
  return digit(9, 10) === Number(value[9]) && digit(10, 11) === Number(value[10]);
}

function cnpjOk(value: string): boolean {
  if (!/^[0-9]{14}$/.test(value) || /^(\d)\1{13}$/.test(value)) return false;
  const weights = [
    [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
    [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  ];
  const calc = (weight: number[]) => {
    let sum = 0;
    for (let i = 0; i < weight.length; i++) sum += Number(value[i]) * weight[i];
    const mod = sum % 11;
    return mod < 2 ? 0 : 11 - mod;
  };
  return calc(weights[0]) === Number(value[12]) &&
    calc(weights[1]) === Number(value[13]);
}

function digits(value: unknown): string {
  return text(value).replace(/\D/g, "");
}

function collapse(value: unknown): string {
  return text(value).replace(/\s+/g, " ").trim();
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}
