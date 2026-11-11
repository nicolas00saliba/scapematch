// Subconta "Reserva de pontos" no Asaas. Só o sandbox, e só com a flag ligada.
// A documentação não oferece um bloqueio de saque: a subconta fica sem conta
// bancária e a apiKey dela não sai do backend.
//
// O percentual do Asaas incide no líquido depois da taxa. Por isso o lastro
// vai em fixedValue, no valor em centavos da indicação (2,5% do bruto).

import {
  asaasSandboxBaseUrl,
  fixedReaisFromCents,
  isAsaasSandbox,
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
  sandbox: boolean;
  reserveWalletId: string | null;
  rootWalletId: string | null;
  houseWalletId: string;
  referralCents: number;
};

/// Linha extra do split. `referralCents` já é zero quando a flag está
/// desligada, não há indicação ou o valor não cabe no líquido.
export function pointsReserveSplitLine(
  input: ReserveSplitLineInput,
): ChargeSplit | null {
  if (!input.sandbox) return null;
  const wallet = (input.reserveWalletId ?? "").trim();
  const root = (input.rootWalletId ?? "").trim();
  if (!wallet || wallet === input.houseWalletId || wallet === root) return null;
  if (!Number.isInteger(input.referralCents) || input.referralCents <= 0) {
    return null;
  }
  return {
    walletId: wallet,
    fixedValue: fixedReaisFromCents(input.referralCents),
  };
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
  return isAsaasSandbox(baseUrl) && apiKey.trim().length > 0;
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

/// Transfere da subconta da reserva. Recusa qualquer URL que não seja o sandbox
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
    purpose: "house" | "platform_return" | "cashback_in" | "cashback_out";
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
  if (claim.data !== "send") return false;
  try {
    const id = await postSandboxTransfer({
      baseUrl: input.baseUrl,
      apiKey: input.reserveApiKey,
      fetchFn: input.fetchFn,
      valueCents: leg.cents,
      destinationWalletId: leg.walletId,
      externalReference: `reserve:${input.chargeId}:${leg.purpose}`,
    });
    const saved = await input.rpc("complete_points_reserve_transfer", {
      p_charge_id: input.chargeId,
      p_purpose: leg.purpose,
      p_provider_ref: id,
      p_ok: true,
    });
    return !saved.error;
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

export async function postSandboxTransfer(input: {
  baseUrl: string;
  apiKey: string;
  fetchFn: AsaasFetch;
  valueCents: number;
  destinationWalletId: string;
  externalReference: string;
}): Promise<string> {
  if (!isAsaasSandbox(input.baseUrl)) {
    throw new Error("reserva de pontos só no sandbox");
  }
  const key = input.apiKey.trim();
  if (!key) throw new Error("chave da reserva ausente");
  const base = input.baseUrl.replace(/\/$/, "");
  if (base !== asaasSandboxBaseUrl) {
    throw new Error("reserva de pontos só no sandbox");
  }
  const response = await input.fetchFn(`${base}/transfers`, {
    method: "POST",
    headers: {
      access_token: key,
      "User-Agent": "EscapeMatch",
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      value: fixedReaisFromCents(input.valueCents),
      walletId: input.destinationWalletId,
      externalReference: input.externalReference,
    }),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Asaas ${response.status}`);
  }
  const body = JSON.parse(text) as { id?: unknown };
  if (typeof body.id !== "string" || body.id.length === 0) {
    throw new Error("Resposta do Asaas sem id");
  }
  return body.id;
}

/// Move o lastro do cashback para a mesma subconta, e devolve no estorno.
/// O valor só existe depois do sorteio, então não entra no split da cobrança.
/// Sem sandbox ou sem as chaves, não chama a rede nem o banco.
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
  if (!isAsaasSandbox(baseUrl) || !chargeId) return;
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
    if (item.purpose === "cashback_out" && reserveKey.trim()) {
      await sendLeg(payout, {
        purpose: "cashback_out",
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

/// Lê o crédito da vaga e, no sandbox, paga a casa a partir da subconta.
/// Fora do sandbox não chama a rede e não anula o crédito do repasse.
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
