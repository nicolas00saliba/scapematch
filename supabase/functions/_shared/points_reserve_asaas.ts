// Subconta "Reserva de pontos" no Asaas. Sandbox e produção usam o mesmo
// contrato, só nas bases oficiais (api-sandbox.asaas.com e api.asaas.com).
// A documentação não oferece um bloqueio de saque: a subconta fica sem conta
// bancária e a apiKey dela não sai do backend.
//
// O percentual do Asaas incide no líquido depois da taxa. Por isso o lastro
// vai em fixedValue, no valor em centavos da indicação (2,5% do bruto).
// O valor da cobrança do jogador não muda: a linha só reparte o que já foi
// calculado. O claim grava a linha pending antes de qualquer chamada.
// A listagem de transferências não filtra por externalReference: a busca
// usa dateCreated[ge], percorre as páginas e compara a referência no código.
// Autorização de evento crítico não liquida a reserva.

import {
  asaasSandboxBaseUrl,
  fixedReaisFromCents,
  isOfficialAsaasBase,
  type AsaasFetch,
  type ChargeSplit,
} from "./asaas_provider.ts";

/// Sem permissão de ambiente, a reserva simplesmente não entra.
export function readEnv(
  env: { get(name: string): string | undefined },
  name: string,
): string {
  try {
    return env.get(name) ?? "";
  } catch {
    return "";
  }
}

export type ReserveSplitLineInput = {
  reserveWalletId: string | null;
  rootWalletId: string | null;
  houseWalletId: string;
  referralCents: number;
};

/// Linha extra do split. `referralCents` já é zero quando a flag está
/// desligada, não há indicação ou o valor não cabe no líquido.
/// O fixedValue tem de voltar aos mesmos centavos. Se não voltar, a linha
/// não entra: a cobrança segue sem a reserva, em vez de mandar outro valor.
export function pointsReserveSplitLine(
  input: ReserveSplitLineInput,
): ChargeSplit | null {
  const wallet = (input.reserveWalletId ?? "").trim();
  const root = (input.rootWalletId ?? "").trim();
  if (!wallet || wallet === input.houseWalletId || wallet === root) return null;
  if (!Number.isInteger(input.referralCents) || input.referralCents <= 0) {
    return null;
  }
  const fixedValue = fixedReaisFromCents(input.referralCents);
  if (Math.round(fixedValue * 100) !== input.referralCents) return null;
  return { walletId: wallet, fixedValue };
}

export type ReserveMoves = {
  houseCents: number;
  platformReturnCents: number;
};

/// O que sai da subconta quando os pontos pagam uma vaga.
/// A casa recebe no máximo o lastro. O resto volta para a conta raiz,
/// que é a comissão já retirada, para o saldo da subconta acompanhar
/// os pontos que ainda existem.
export function pointsReserveMoves(input: {
  backedCents: number;
  houseOwedCents: number;
}): ReserveMoves {
  const backed = Number.isInteger(input.backedCents)
    ? Math.max(input.backedCents, 0)
    : 0;
  const owed = Number.isInteger(input.houseOwedCents)
    ? Math.max(input.houseOwedCents, 0)
    : 0;
  const houseCents = Math.min(owed, backed);
  return { houseCents, platformReturnCents: backed - houseCents };
}

export function backedCentsOf(entry: {
  backed_points?: unknown;
  points?: unknown;
  amount_cents?: unknown;
} | null): number {
  if (!entry) return 0;
  const backed = Number(entry.backed_points);
  const points = Number(entry.points);
  const amount = Number(entry.amount_cents);
  if (!Number.isInteger(backed) || backed < 0) return 0;
  if (!Number.isInteger(points) || points <= 0) return 0;
  if (!Number.isInteger(amount) || amount < 0) return 0;
  return Math.floor((backed * amount) / points);
}

export function reserveTransferAllowed(baseUrl: string, apiKey: string): boolean {
  return isOfficialAsaasBase(baseUrl) && apiKey.trim().length > 0;
}

type RpcResult = { data: unknown; error: { message: string } | null };

export type ReserveRpc = (
  fn: string,
  args: Record<string, unknown>,
) => Promise<RpcResult>;

export type ReservePayoutInput = {
  rpc: ReserveRpc;
  baseUrl: string;
  reserveApiKey: string;
  rootWalletId: string;
  houseWalletId: string;
  chargeId: string;
  backedCents: number;
  houseOwedCents: number;
  fetchFn: AsaasFetch;
};

/// Transfere da subconta da reserva. Recusa URL que não seja a API oficial
/// antes de chamar a rede. Devolve true quando a casa foi paga por aqui e o
/// crédito no repasse pode ser anulado.
export async function settlePointsReservePayout(
  input: ReservePayoutInput,
): Promise<boolean> {
  if (!reserveTransferAllowed(input.baseUrl, input.reserveApiKey)) return false;
  const houseWallet = input.houseWalletId.trim();
  const rootWallet = input.rootWalletId.trim();
  if (!houseWallet || !input.chargeId) return false;
  const moves = pointsReserveMoves(input);
  if (moves.houseCents <= 0) return false;
  if (moves.platformReturnCents > 0 && !rootWallet) return false;

  const houseSent = await sendLeg(input, {
    purpose: "house",
    cents: moves.houseCents,
    walletId: houseWallet,
  });
  if (!houseSent) return false;
  if (moves.platformReturnCents > 0) {
    const returned = await sendLeg(input, {
      purpose: "platform_return",
      cents: moves.platformReturnCents,
      walletId: rootWallet,
    });
    if (!returned) return true;
  }
  return true;
}

async function sendLeg(
  input: ReservePayoutInput,
  leg: {
    purpose:
      | "house"
      | "platform_return"
      | "cashback_in"
      | "cashback_out"
      | "cashback_excess";
    cents: number;
    walletId: string;
  },
): Promise<boolean> {
  const claim = await input.rpc("claim_points_reserve_transfer", {
    p_charge_id: input.chargeId,
    p_purpose: leg.purpose,
    p_amount_cents: leg.cents,
    p_wallet_id: leg.walletId,
  });
  if (claim.error) return false;
  if (claim.data === "done") return true;
  if (claim.data !== "send" && claim.data !== "skip") return false;
  const anchor = await input.rpc("points_reserve_transfer_anchor", {
    p_charge_id: input.chargeId,
    p_purpose: leg.purpose,
  });
  const createdOn = typeof anchor.data === "string" ? anchor.data.slice(0, 10) : "";
  if (anchor.error || !reserveDay.test(createdOn)) {
    if (claim.data === "send") {
      await input.rpc("complete_points_reserve_transfer", {
        p_charge_id: input.chargeId,
        p_purpose: leg.purpose,
        p_provider_ref: null,
        p_ok: false,
      });
    }
    return false;
  }
  const transfer = {
    baseUrl: input.baseUrl,
    apiKey: input.reserveApiKey,
    fetchFn: input.fetchFn,
    valueCents: leg.cents,
    destinationWalletId: leg.walletId,
    externalReference: `reserve:${input.chargeId}:${leg.purpose}`,
    createdOn,
  };
  try {
    const hit = claim.data === "skip"
      ? await findReserveTransfer(transfer)
      : await postReserveTransfer(transfer);
    return await finishLeg(input, leg.purpose, hit);
  } catch {
    await input.rpc("complete_points_reserve_transfer", {
      p_charge_id: input.chargeId,
      p_purpose: leg.purpose,
      p_provider_ref: null,
      p_ok: false,
    });
    return false;
  }
}

async function finishLeg(
  input: ReservePayoutInput,
  purpose: string,
  hit: ReserveHit | null,
): Promise<boolean> {
  if (!hit) return false;
  if (hit.state === "paid") {
    const saved = await input.rpc("complete_points_reserve_transfer", {
      p_charge_id: input.chargeId,
      p_purpose: purpose,
      p_provider_ref: hit.id,
      p_ok: true,
    });
    return !saved.error;
  }
  if (hit.state === "failed") {
    await input.rpc("complete_points_reserve_transfer", {
      p_charge_id: input.chargeId,
      p_purpose: purpose,
      p_provider_ref: hit.id,
      p_ok: false,
    });
    return false;
  }
  if (hit.state === "awaiting_authorization") {
    await input.rpc("note_points_reserve_awaiting", {
      p_charge_id: input.chargeId,
      p_purpose: purpose,
      p_provider_ref: hit.id,
    });
    alertReserveAuthorization({
      chargeId: input.chargeId,
      purpose,
      transferId: hit.id,
    });
    return false;
  }
  await input.rpc("remember_points_reserve_transfer", {
    p_charge_id: input.chargeId,
    p_purpose: purpose,
    p_provider_ref: hit.id,
  });
  if (hit.state === "mismatch") {
    console.error(JSON.stringify({
      scope: "points_reserve",
      code: "reserve_value_mismatch",
      purpose,
    }));
  }
  return false;
}

export type ReserveTransferInput = {
  baseUrl: string;
  apiKey: string;
  fetchFn: AsaasFetch;
  valueCents: number;
  destinationWalletId: string;
  externalReference: string;
  /// Dia da linha pending, em America/Sao_Paulo. Vira dateCreated[ge].
  createdOn: string;
};

export type ReserveHit = {
  id: string;
  state: "paid" | "awaiting_authorization" | "open" | "failed" | "mismatch";
};

/// A listagem oficial devolve no máximo 100 por página.
export const reserveTransferPageSize = 100;

const reserveListPages = 50;
const reserveDay = /^\d{4}-\d{2}-\d{2}$/;

const reservePurposes = new Set([
  "house",
  "platform_return",
  "cashback_in",
  "cashback_out",
  "cashback_excess",
]);

/// Nome antigo. Vale no sandbox e na produção oficial.
export const postSandboxTransfer = postReserveTransfer;

/// Procura a transferência nas páginas a partir da data da reserva.
/// A query não manda externalReference: esse filtro não existe na listagem.
export async function findReserveTransfer(
  input: ReserveTransferInput,
): Promise<ReserveHit | null> {
  const base = officialBase(input.baseUrl);
  const key = input.apiKey.trim();
  if (!key) throw new Error("chave da reserva ausente");
  assertReference(input.externalReference);
  if (!reserveDay.test(input.createdOn)) throw new Error("data da reserva");
  let offset = 0;
  for (let page = 0; page < reserveListPages; page++) {
    const response = await input.fetchFn(
      transferListUrl(base, input.createdOn, offset),
      { method: "GET", headers: asaasHeaders(key) },
    );
    if (!response.ok) throw new Error(`Asaas ${response.status}`);
    const body = await response.json().catch(() => null);
    if (!body || typeof body !== "object") {
      throw new Error("lista de transferências");
    }
    const record = body as Record<string, unknown>;
    const hit = matchReservePage(record, input.externalReference, input.valueCents);
    if (hit) return hit;
    const rows = Array.isArray(record.data) ? record.data.length : 0;
    if (record.hasMore !== true || rows === 0) return null;
    offset += rows;
  }
  throw new Error("lista de transferências incompleta");
}

export async function postReserveTransfer(
  input: ReserveTransferInput,
): Promise<ReserveHit> {
  const existing = await findReserveTransfer(input);
  if (existing) return existing;
  const wallet = input.destinationWalletId.trim();
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(wallet)) {
    throw new Error("carteira da reserva");
  }
  const value = fixedReaisFromCents(input.valueCents);
  if (Math.round(value * 100) !== input.valueCents) {
    throw new Error("valor da reserva");
  }
  const base = officialBase(input.baseUrl);
  const response = await input.fetchFn(`${base}/transfers`, {
    method: "POST",
    headers: {
      ...asaasHeaders(input.apiKey.trim()),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      value,
      walletId: wallet,
      externalReference: input.externalReference,
    }),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Asaas ${response.status}`);
  const hit = classifyReserveTransfer(JSON.parse(text), input.valueCents);
  if (!hit) throw new Error("Resposta do Asaas sem id");
  return hit;
}

/// DONE com authorized diferente de false está pago. Token pendente não.
export function classifyReserveTransfer(
  body: unknown,
  expectedCents: number,
): ReserveHit | null {
  if (!body || typeof body !== "object") return null;
  const item = body as Record<string, unknown>;
  const id = typeof item.id === "string" ? item.id : "";
  if (!id) return null;
  if (typeof item.value === "number" && Math.round(item.value * 100) !== expectedCents) {
    return { id, state: "mismatch" };
  }
  const status = typeof item.status === "string" ? item.status : "";
  if (
    status === "AWAITING_CRITICAL_ACTION_AUTHORIZATION" ||
    item.authorized === false
  ) {
    return { id, state: "awaiting_authorization" };
  }
  if (status === "DONE") return { id, state: "paid" };
  if (status === "FAILED" || status === "CANCELLED") {
    return { id, state: "failed" };
  }
  return { id, state: "open" };
}

export function alertReserveAuthorization(input: {
  chargeId: string;
  purpose: string;
  transferId: string;
}): void {
  const charge = safeToken(input.chargeId);
  const purpose = reservePurposes.has(input.purpose) ? input.purpose : "invalid";
  const transfer = safeToken(input.transferId);
  console.error(JSON.stringify({
    scope: "points_reserve",
    code: "awaiting_critical_action_authorization",
    charge,
    purpose,
    transfer,
  }));
}

function matchReservePage(
  body: Record<string, unknown>,
  externalReference: string,
  expectedCents: number,
): ReserveHit | null {
  const rows = Array.isArray(body.data) ? body.data : [];
  for (const row of rows) {
    if (!row || typeof row !== "object") continue;
    const item = row as Record<string, unknown>;
    if (item.externalReference !== externalReference) continue;
    return classifyReserveTransfer(item, expectedCents);
  }
  return null;
}

function transferListUrl(base: string, createdOn: string, offset: number): string {
  return `${base}/transfers?dateCreated[ge]=${createdOn}&limit=${reserveTransferPageSize}&offset=${offset}`;
}

function safeToken(value: string): string {
  return /^[A-Za-z0-9_-]{1,80}$/.test(value) ? value : "invalid";
}

function officialBase(baseUrl: string): string {
  const base = baseUrl.trim().replace(/\/$/, "");
  if (!isOfficialAsaasBase(base)) {
    throw new Error("reserva de pontos fora da API Asaas");
  }
  return base;
}

function assertReference(reference: string): void {
  const parts = reference.split(":");
  if (
    parts.length !== 3 || parts[0] !== "reserve" ||
    !/^[A-Za-z0-9_-]{1,80}$/.test(parts[1]) ||
    !reservePurposes.has(parts[2])
  ) {
    throw new Error("referência da reserva");
  }
}

function asaasHeaders(apiKey: string): Record<string, string> {
  return {
    access_token: apiKey,
    "User-Agent": "EscapeMatch",
    Accept: "application/json",
  };
}

/// Move o lastro do cashback para a mesma subconta, e devolve no estorno.
/// O valor só existe depois do sorteio, então não entra no split da cobrança.
/// Sem a API oficial ou sem as chaves, não chama a rede nem o banco.
export async function fundCashbackReserve(
  admin: unknown,
  env: { get(name: string): string | undefined },
  chargeId: string,
  fetchFn: AsaasFetch = fetch,
): Promise<void> {
  const baseUrl = (readEnv(env, "ASAAS_BASE_URL") || asaasSandboxBaseUrl)
    .replace(/\/$/, "");
  const rootKey = readEnv(env, "ASAAS_API_KEY");
  const reserveKey = readEnv(env, "ASAAS_POINTS_RESERVE_API_KEY");
  const reserveWallet = readEnv(env, "ASAAS_POINTS_RESERVE_WALLET_ID").trim();
  const rootWallet = readEnv(env, "ASAAS_ROOT_WALLET_ID").trim();
  if (!isOfficialAsaasBase(baseUrl) || !chargeId) return;
  if (!reserveWallet || !rootWallet || reserveWallet === rootWallet) return;
  if (!rootKey.trim() && !reserveKey.trim()) return;
  const client = admin as { rpc: ReserveRpc };
  const listed = await client.rpc("cashback_reserve_pending", {
    p_charge_id: chargeId,
  });
  if (listed.error || !Array.isArray(listed.data)) return;
  const payout = {
    rpc: client.rpc,
    baseUrl,
    reserveApiKey: reserveKey,
    rootWalletId: rootWallet,
    houseWalletId: reserveWallet,
    chargeId,
    backedCents: 0,
    houseOwedCents: 0,
    fetchFn,
  };
  for (const row of listed.data) {
    if (!row || typeof row !== "object") continue;
    const item = row as { purpose?: unknown; amount_cents?: unknown };
    const cents = Number(item.amount_cents);
    if (!Number.isInteger(cents) || cents <= 0) continue;
    if (item.purpose === "cashback_in" && rootKey.trim()) {
      await sendLeg(
        { ...payout, reserveApiKey: rootKey },
        { purpose: "cashback_in", cents, walletId: reserveWallet },
      );
    }
    if (
      (item.purpose === "cashback_out" || item.purpose === "cashback_excess") &&
      reserveKey.trim()
    ) {
      await sendLeg(payout, {
        purpose: item.purpose,
        cents,
        walletId: rootWallet,
      });
    }
  }
}

type ReserveQuery = {
  data: {
    redemption_id?: unknown;
    amount_cents?: unknown;
    applied_cents?: unknown;
    voided_at?: unknown;
    wallet_id?: unknown;
    backed_points?: unknown;
    points?: unknown;
  } | null;
};

/// Lê o crédito da vaga e paga a casa a partir da subconta.
/// Fora da API oficial não chama a rede e não anula o crédito do repasse.
export async function settlePaidChargeReserve(
  admin: unknown,
  env: { get(name: string): string | undefined },
  chargeId: string,
  fetchFn: AsaasFetch = fetch,
): Promise<void> {
  const client = admin as { rpc: ReserveRpc; from: (table: string) => unknown };
  const baseUrl = (readEnv(env, "ASAAS_BASE_URL") || asaasSandboxBaseUrl)
    .replace(/\/$/, "");
  const apiKey = readEnv(env, "ASAAS_POINTS_RESERVE_API_KEY");
  if (!reserveTransferAllowed(baseUrl, apiKey)) return;
  const topup = await readRow(
    client,
    "free_slot_topups",
    "payment_charge_id",
    chargeId,
    "redemption_id, amount_cents, applied_cents, voided_at",
  );
  if (!topup || topup.voided_at || Number(topup.applied_cents) > 0) return;
  const charge = await readRow(client, "payment_charges", "id", chargeId, "wallet_id");
  const redemption = await readRow(
    client,
    "scape_point_entries",
    "id",
    String(topup.redemption_id ?? ""),
    "backed_points, points, amount_cents",
  );
  const paid = await settlePointsReservePayout({
    rpc: client.rpc,
    baseUrl,
    reserveApiKey: apiKey,
    rootWalletId: readEnv(env, "ASAAS_ROOT_WALLET_ID"),
    houseWalletId: String(charge?.wallet_id ?? ""),
    chargeId,
    backedCents: backedCentsOf(redemption),
    houseOwedCents: Number(topup.amount_cents),
    fetchFn,
  });
  if (!paid) return;
  await client.rpc("void_unapplied_points_reserve", { p_charge_id: chargeId });
}

async function readRow(
  admin: { from: (table: string) => unknown },
  table: string,
  column: string,
  value: string,
  columns: string,
): Promise<ReserveQuery["data"]> {
  const from = admin.from(table) as {
    select: (columns: string) => {
      eq: (column: string, value: string) => {
        maybeSingle: () => Promise<ReserveQuery>;
      };
    };
  };
  const { data } = await from.select(columns).eq(column, value).maybeSingle();
  return data;
}
