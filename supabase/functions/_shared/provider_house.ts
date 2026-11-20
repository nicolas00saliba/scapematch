// Saldo e saque da subconta Woovi. A casa vê o número no Parceiro
// e não abre a Woovi. O saque automático não varre o saldo no cron:
// o Pix cai na subconta antes da confirmação do grupo. Ele sai na
// liquidação, só da parte da casa, quando auto_withdraw está ligado.

import { groupUnconfirmedNotice, type FetchLike } from "./payment_provider.ts";
import { WooviProvider } from "./woovi_provider.ts";
import type { EnvLike } from "./http.ts";

type Store = {
  rpc(fn: string, args: Record<string, unknown>): Promise<unknown>;
};

export type HouseDeps = {
  env: EnvLike;
  store: Store;
  fetchFn?: FetchLike;
};

export function wooviStackOn(_env: EnvLike): boolean {
  return true;
}

export async function wooviHouseBalance(
  deps: HouseDeps,
  venueId: string,
  actorId: string,
): Promise<Record<string, unknown>> {
  const account = await accountFor(deps, venueId, actorId);
  const woovi = WooviProvider.fromEnv(deps.env, deps.fetchFn);
  const balance = await woovi.balance(text(account.pix_key));
  return {
    provider: "woovi",
    balance_cents: balance,
    pix_key_masked: maskPix(text(account.pix_key)),
    can_withdraw: text(account.status) === "active",
    notice: groupUnconfirmedNotice,
  };
}

export async function wooviHouseWithdraw(
  deps: HouseDeps,
  input: { venueId: string; actorId: string; amountCents: number },
): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!Number.isInteger(input.amountCents) || input.amountCents <= 0) {
    return { status: 400, body: { error: "valor" } };
  }
  const account = await accountFor(deps, input.venueId, input.actorId);
  const pixKey = text(account.pix_key);
  const woovi = WooviProvider.fromEnv(deps.env, deps.fetchFn);
  const available = await woovi.balance(pixKey);
  const claimed = record(await deps.store.rpc("claim_provider_withdrawal", {
    p_venue_id: input.venueId,
    p_actor: input.actorId,
    p_source: "manual",
    p_period_key: "",
    p_amount_cents: input.amountCents,
    p_available_cents: available,
    p_provider: "woovi",
  }));
  const id = text(claimed.id);
  const cents = Number(claimed.amount_cents);
  if (!id || !Number.isInteger(cents) || cents <= 0) {
    return { status: 400, body: { error: "valor" } };
  }
  const send = await deps.store.rpc("begin_withdrawal_dispatch", { p_id: id });
  if (send !== true) return { status: 200, body: { ok: true, duplicate: true } };
  try {
    const withdrawal = await woovi.withdraw(pixKey, cents);
    await deps.store.rpc("attach_venue_transfer", {
      p_id: id,
      p_transfer_id: `woovi-${id}`,
      p_status: withdrawal.status === "success" ? "done" : "pending",
      p_receipt: "",
    });
    return {
      status: 200,
      body: {
        ok: true,
        id,
        provider: "woovi",
        status: withdrawal.status,
        notice: groupUnconfirmedNotice,
      },
    };
  } catch (error) {
    await deps.store.rpc("fail_venue_withdrawal", {
      p_id: id,
      p_reason: "woovi",
    }).catch(() => undefined);
    const message = error instanceof Error ? error.message : "";
    if (message === "sem subconta" || message === "not owner") {
      return { status: 403, body: { error: message } };
    }
    return { status: 502, body: { error: "woovi_unavailable" } };
  }
}

/// O cron não saca o saldo inteiro. O saque da sessão acontece quando
/// o grupo confirma. Aqui só registramos que o trilho Woovi está ativo,
/// para o cron não cair no Asaas.
export function wooviScheduledReport(): Record<string, unknown> {
  return {
    ok: true,
    provider: "woovi",
    created: 0,
    mode: "depois_da_sessao",
    notice: groupUnconfirmedNotice,
  };
}

async function accountFor(
  deps: HouseDeps,
  venueId: string,
  actorId: string,
): Promise<Record<string, unknown>> {
  const data = await deps.store.rpc("provider_house_account", {
    p_venue_id: venueId,
    p_actor: actorId,
    p_provider: "woovi",
  });
  const account = record(data);
  if (!text(account.pix_key)) throw new Error("sem subconta");
  return account;
}

function maskPix(value: string): string {
  if (value.length <= 4) return "****";
  return `${"*".repeat(Math.max(value.length - 4, 4))}${value.slice(-4)}`;
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? value as Record<string, unknown> : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}
