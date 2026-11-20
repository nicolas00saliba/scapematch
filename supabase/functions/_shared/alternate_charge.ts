// Pix na Woovi e cartão no Mercado Pago. Cobrança com provider asaas
// não entra aqui: ela fica só como registro.

import { commissionCents } from "./scape_points.ts";
import { cardDecisionAt, planCardHold } from "./card_hold.ts";
import { commissionBpsForVenue } from "./commission_rate.ts";
import { MercadoPagoProvider, storedCardStatus } from "./mercadopago_provider.ts";
import {
  denoEnv,
  groupUnconfirmedNotice,
  looksLikePan,
  providerForBilling,
  readEnv,
  wooviSplits,
  type FetchLike,
} from "./payment_provider.ts";
import { hasRawCardData } from "./raw_card.ts";
import { WooviProvider } from "./woovi_provider.ts";
import type { EnvLike } from "./http.ts";

type Json = Record<string, unknown>;

type Admin = {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        eq(column: string, value: string): {
          maybeSingle(): Promise<{ data: Json | null; error: unknown }>;
        };
        maybeSingle(): Promise<{ data: Json | null; error: unknown }>;
      };
    };
    insert(row: Json): Promise<{ error: { message?: string } | null }>;
    update(row: Json): {
      eq(column: string, value: string): Promise<{ error: unknown }>;
    };
  };
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { message?: string } | null }>;
};

export type AlternateChargeInput = {
  json: (body: unknown, status?: number) => Response;
  admin: Admin;
  user: { id: string; email?: string | null };
  group: Json;
  existing: Json | null;
  body: Json;
  groupId: string;
  billingType: "PIX" | "CREDIT_CARD";
  idempotencyKey: string;
  woovi?: WooviProvider;
  mercadoPago?: MercadoPagoProvider;
  now?: Date;
  env?: EnvLike;
  fetchFn?: FetchLike;
};

export async function createAlternateCharge(
  input: AlternateChargeInput,
): Promise<Response> {
  const env = input.env ?? denoEnv();
  const now = input.now ?? new Date();
  if (hasRawCardData(input.body)) {
    return input.json({ error: "A cobrança não recebe dados do cartão." }, 400);
  }
  const open = input.existing &&
    !["failed", "cancelled", "refunded"].includes(text(input.existing.status));
  if (open && text(input.existing?.provider_ref)) {
    return input.json(chargeView(input.existing as Json));
  }

  const venueId = text(input.group.venue_id);
  const { data: venue, error: venueError } = await input.admin
    .from("venues")
    .select("id, name, status")
    .eq("id", venueId)
    .maybeSingle();
  if (venueError || !venue || text(venue.status) !== "approved") {
    return input.json({ error: "A casa ainda não recebe por este provedor." }, 409);
  }

  const provider = providerForBilling(input.billingType);
  const accountProvider = provider === "mercadopago" ? "mercadopago" : "woovi";
  const { data: account, error: accountError } = await input.admin
    .from("provider_payout_accounts")
    .select("pix_key, external_id, status, expires_at")
    .eq("venue_id", venueId)
    .eq("provider", accountProvider)
    .maybeSingle();
  if (accountError || !account || text(account.status) !== "active") {
    return input.json({ error: "A casa ainda não tem conta de repasse." }, 409);
  }

  let amountCents = Number(input.group.price_cents);
  if (!Number.isInteger(amountCents) || amountCents <= 0) {
    return input.json({ error: "valor" }, 400);
  }
  const commissionBps = await commissionBpsForVenue(input.admin, venueId);
  let referralCents = 0;
  const requested = Number(input.body.points ?? 0);
  if (Number.isInteger(requested) && requested > 0) {
    const capped = await input.admin.rpc("cap_point_redemption", {
      p_group_id: input.groupId,
      p_user_id: input.user.id,
      p_points: requested,
    });
    const points = typeof capped.data === "number" ? capped.data : 0;
    if (!capped.error && points > 0) {
      const held = await input.admin.rpc("hold_point_redemption", {
        p_user_id: input.user.id,
        p_idempotency_key: input.idempotencyKey,
        p_gross: amountCents,
        p_commission_bps: commissionBps,
        p_points: points,
      });
      if (held.error || !held.data || typeof held.data !== "object") {
        throw new Error("pontos");
      }
      const row = held.data as Json;
      amountCents = Number(row.charged_cents);
      if (!Number.isInteger(amountCents) || amountCents <= 0) {
        await input.admin.rpc("release_point_hold", {
          p_idempotency_key: input.idempotencyKey,
        });
        return input.json({ error: "pontos_somente_no_asaas" }, 409);
      }
      const reserve = await input.admin.rpc("points_reserve_split_cents", {
        p_user_id: input.user.id,
        p_venue_id: venueId,
        p_gross: Number(row.gross_cents) || Number(input.group.price_cents),
        p_charged: amountCents,
        p_house_fixed: Math.max(amountCents - commissionCents(amountCents, commissionBps), 0),
        p_billing_type: input.billingType,
      });
      if (!reserve.error && Number.isInteger(reserve.data) && Number(reserve.data) > 0) {
        referralCents = Number(reserve.data);
      }
    }
  }

  const houseCents = Math.max(amountCents - commissionCents(amountCents, commissionBps), 0);
  const chargeId = crypto.randomUUID();

  if (provider === "mercadopago") {
    const decision = cardDecisionAt({
      closes_at: text(input.group.closes_at) || null,
      starts_at: text(input.group.starts_at) || null,
    });
    if (!decision) return input.json({ error: "sessao" }, 409);
    const plan = planCardHold(now, decision);
    if (!plan.authorizeNow) {
      return input.json({
        error: "card_hold_deferred",
        authorize_at: plan.authorizeAt,
        notice: groupUnconfirmedNotice,
      }, 409);
    }
    const token = text(input.body.card_token);
    const method = text(input.body.payment_method_id);
    if (!token || !method || looksLikePan(token)) {
      return input.json({ error: "A cobrança não recebe dados do cartão." }, 400);
    }
    const email = (input.user.email ?? "").trim();
    const accessToken = await houseAccessToken(input.admin, env, venueId, now, input.fetchFn);
    const mp = input.mercadoPago ?? MercadoPagoProvider.fromEnv(env, input.fetchFn);
    let authorized;
    try {
      authorized = await mp.authorizeCard({
        token,
        paymentMethodId: method,
        transactionAmountCents: amountCents,
        applicationFeeCents: amountCents - houseCents,
        description: `EscapeMatch ${text(venue.name)}`.slice(0, 140),
        payerEmail: email,
        idempotencyKey: input.idempotencyKey,
        accessToken,
      });
    } catch (error) {
      try {
        await input.admin.rpc("release_point_hold", {
          p_idempotency_key: input.idempotencyKey,
        });
      } catch {
        // A reserva de pontos fica para a reconciliação se o RPC falhar.
      }
      throw error;
    }
    await saveCharge(input.admin, {
      id: chargeId,
      group_id: input.groupId,
      user_id: input.user.id,
      venue_id: venueId,
      amount_cents: amountCents,
      billing_type: "CREDIT_CARD",
      status: storedCardStatus(authorized.status),
      provider: "mercadopago",
      provider_ref: authorized.id,
      idempotency_key: input.idempotencyKey,
      wallet_id: text(account.external_id),
      commission_bps: commissionBps,
      house_fixed_cents: houseCents,
    });
    return input.json({
      ...chargeView({
        id: chargeId,
        status: authorized.status,
        provider: "mercadopago",
        provider_ref: authorized.id,
        billing_type: "CREDIT_CARD",
        amount_cents: amountCents,
      }),
      notice: groupUnconfirmedNotice,
    });
  }

  const housePixKey = text(account.pix_key) || text(account.external_id);
  const splits = wooviSplits({
    housePixKey,
    houseCents,
    chargeCents: amountCents,
    reservePixKey: readEnv(env, "WOOVI_POINTS_RESERVE_PIX_KEY"),
    referralCents,
  });
  const woovi = input.woovi ?? WooviProvider.fromEnv(env, input.fetchFn);
  let pix;
  try {
    pix = await woovi.createPix({
      correlationId: input.idempotencyKey,
      valueCents: amountCents,
      comment: groupUnconfirmedNotice,
      splits,
    });
  } catch (error) {
    try {
      await input.admin.rpc("release_point_hold", {
        p_idempotency_key: input.idempotencyKey,
      });
    } catch {
      // A reserva de pontos fica para a reconciliação se o RPC falhar.
    }
    throw error;
  }
  await saveCharge(input.admin, {
    id: chargeId,
    group_id: input.groupId,
    user_id: input.user.id,
    venue_id: venueId,
    amount_cents: amountCents,
    billing_type: "PIX",
    status: pix.status === "paid" ? "paid" : "pending",
    provider: "woovi",
    provider_ref: pix.providerRef,
    qr_code: pix.brCode,
    qr_code_base64: pix.qrCodeImage,
    idempotency_key: input.idempotencyKey,
    wallet_id: housePixKey,
    house_pix_key: housePixKey,
    commission_bps: commissionBps,
    house_fixed_cents: houseCents,
  });
  return input.json({
    charge_id: chargeId,
    status: pix.status === "paid" ? "paid" : "pending",
    provider: "woovi",
    provider_ref: pix.providerRef,
    qr_code: pix.brCode,
    qr_code_base64: pix.qrCodeImage,
    billing_type: "PIX",
    amount_cents: amountCents,
    notice: groupUnconfirmedNotice,
  });
}

async function houseAccessToken(
  admin: Admin,
  env: EnvLike,
  venueId: string,
  now: Date,
  fetchFn?: FetchLike,
): Promise<string> {
  const loaded = await admin.rpc("read_provider_oauth", {
    p_venue_id: venueId,
    p_provider: "mercadopago",
  });
  if (loaded.error || !loaded.data || typeof loaded.data !== "object") {
    throw new Error("oauth ausente");
  }
  const row = loaded.data as Json;
  const access = text(row.access_token);
  const refresh = text(row.refresh_token);
  const expires = new Date(text(row.expires_at));
  const { shouldRefreshOauth, refreshAccessToken } = await import(
    "./mercadopago_provider.ts"
  );
  if (!access) throw new Error("oauth ausente");
  if (!refresh || Number.isNaN(expires.getTime()) || !shouldRefreshOauth(expires, now)) {
    return access;
  }
  const renewed = await refreshAccessToken({
    clientId: readEnv(env, "MP_CLIENT_ID"),
    clientSecret: readEnv(env, "MP_CLIENT_SECRET"),
    refreshToken: refresh,
    now,
  }, fetchFn);
  await admin.rpc("store_provider_oauth", {
    p_venue_id: venueId,
    p_provider: "mercadopago",
    p_access_token: renewed.accessToken,
    p_refresh_token: renewed.refreshToken,
    p_expires_at: renewed.expiresAt,
  });
  return renewed.accessToken;
}

async function saveCharge(admin: Admin, row: Json): Promise<void> {
  const { error } = await admin.from("payment_charges").insert(row);
  if (error) throw new Error("erro");
}

function chargeView(row: Json): Json {
  return {
    charge_id: text(row.id),
    status: text(row.status),
    provider: text(row.provider),
    provider_ref: text(row.provider_ref),
    qr_code: text(row.qr_code),
    qr_code_base64: row.qr_code_base64 ?? null,
    billing_type: text(row.billing_type),
    amount_cents: Number(row.amount_cents) || 0,
    notice: groupUnconfirmedNotice,
  };
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}
