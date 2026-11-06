import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import {
  cardDeclined,
  clientFailure,
  isCardDeclined,
  logAsaasFailure,
} from "../_shared/asaas_client_error.ts";
import {
  asaasPaymentGone,
  AsaasProvider,
  houseSplitPercent,
  PixReservationLost,
  PixReuseRejected,
} from "../_shared/asaas_provider.ts";
import { confirmedChargeStatus } from "../_shared/charge_patch.ts";
import { applyPaymentTransition } from "../_shared/ledger.ts";
import {
  cardSwitchBlock,
  cardSwitchDecision,
  localChargeStatus,
  lostAttemptCompensation,
  pixExternalReference,
  pixLeaseExpired,
  pixMatchesCharge,
  pixReservationAction,
  releaseReservationOnError,
} from "../_shared/pix_charge.ts";
import { clientIp } from "../_shared/client_ip.ts";
import { commissionBpsForVenue } from "../_shared/commission_rate.ts";
import { customerWithCpf, playerCpfDigits } from "../_shared/player_cpf.ts";
import {
  bindJson,
  corsHeadersFor,
  publicError,
  todayInSaoPaulo,
} from "../_shared/http.ts";
import { hasRawCardData } from "../_shared/raw_card.ts";
import {
  cardForCharge,
  loadOwnedCard,
  requestedSavedCardId,
  type SavedCard,
  savedCardView,
} from "../_shared/saved_card.ts";

type ChargeBody = {
  group_id?: string;
  billing_type?: string;
  idempotency_key?: string;
  saved_card_id?: string;
};

type ChargeUser = { id: string; email?: string | null };

export type ChargeRuntime = {
  user: ChargeUser;
  admin: ChargeDb;
  asaas: AsaasProvider;
};

export async function createCharge(
  req: Request,
  deps?: ChargeRuntime,
): Promise<Response> {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    let user: ChargeUser;
    let admin: ChargeDb;
    if (deps) {
      user = deps.user;
      admin = deps.admin;
    } else {
      const authHeader = req.headers.get("Authorization") ?? "";
      const url = Deno.env.get("SUPABASE_URL") ?? "";
      const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
      const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: userError } = await userClient.auth
        .getUser();
      if (userError || !userData.user) {
        return json({ error: "not authenticated" }, 401);
      }
      user = userData.user;
      admin = createClient(url, service);
    }

    const body = await req.json() as ChargeBody;
    if (hasRawCardData(body)) {
      return json({ error: "A cobrança não recebe dados do cartão." }, 400);
    }
    const groupId = body.group_id ?? "";
    const billingType = body.billing_type === "CREDIT_CARD"
      ? "CREDIT_CARD"
      : "PIX";
    const idempotencyKey = (body.idempotency_key ?? "").trim();
    if (!groupId || idempotencyKey.length < 8) {
      return json(
        { error: "group_id e idempotency_key são obrigatórios" },
        400,
      );
    }

    const { data: group } = await admin
      .from("groups")
      .select(
        "id, venue_id, price_cents, cancelled_at, closed_at, starts_at, total_spots, minimum_spots",
      )
      .eq("id", groupId)
      .maybeSingle();
    if (!group || group.cancelled_at) {
      return json({ error: "group not found" }, 404);
    }
    if (new Date(group.starts_at).getTime() <= Date.now()) {
      return json({ error: "session started" }, 409);
    }

    const { data: member } = await admin
      .from("group_members")
      .select("id, attendance")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!member || member.attendance === "cancelled") {
      return json({ error: "not member" }, 403);
    }

    const { data: existing } = await admin
      .from("payment_charges")
      .select(
        "id, status, qr_code, qr_code_base64, provider_ref, billing_type, amount_cents, reserved_at, attempt_id, idempotency_key",
      )
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (
      existing &&
      existing.billing_type !== "PIX" &&
      !["failed", "cancelled", "refunded"].includes(existing.status) &&
      existing.provider_ref
    ) {
      return json({
        charge_id: existing.id,
        status: existing.status,
        provider_ref: existing.provider_ref,
        qr_code: existing.qr_code,
        qr_code_base64: existing.qr_code_base64,
        billing_type: existing.billing_type,
        amount_cents: existing.amount_cents,
      });
    }

    const { data: venue } = await admin
      .from("venues")
      .select("id, name, asaas_wallet_id, status")
      .eq("id", group.venue_id)
      .maybeSingle();
    if (!venue || venue.status !== "approved" || !venue.asaas_wallet_id) {
      return json({ error: "A casa ainda não tem subconta Asaas." }, 409);
    }

    const asaas = deps?.asaas ?? AsaasProvider.fromEnv(Deno.env);
    const commissionBps = await commissionBpsForVenue(
      admin,
      venue.id as string,
    );
    const split = {
      walletId: venue.asaas_wallet_id as string,
      percentualValue: houseSplitPercent(commissionBps),
    };

    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, asaas_customer_id, cpf")
      .eq("id", user.id)
      .maybeSingle();
    const cpf = playerCpfDigits(profile?.cpf);
    if (!cpf) return json({ error: "cpf_required" }, 422);
    const previousCustomer = profile?.asaas_customer_id as string | null;
    const customerId = await customerWithCpf(asaas, {
      customerId: previousCustomer,
      name: profile?.display_name ?? "Jogador",
      email: user.email ?? "",
      externalReference: user.id,
      cpf,
    });
    if (customerId !== previousCustomer) {
      await admin.from("profiles").update({ asaas_customer_id: customerId }).eq(
        "id",
        user.id,
      );
    }

    const amountCents = group.price_cents as number;
    const dueDate = todayInSaoPaulo();
    const description = `${venue.name}`;
    let providerRef = "";
    let status = "pending";
    let qrCode: string | null = null;
    let qrImage: string | null = null;
    let cardView: ReturnType<typeof savedCardView> | null = null;
    let savedId = "";

    const mayCredit = await groupClosedForCredit(admin, group);

    if (billingType === "PIX") {
      const reserved = await reservePixCharge(admin, {
        groupId,
        userId: user.id,
        venueId: venue.id as string,
        amountCents,
        idempotencyKey,
        walletId: venue.asaas_wallet_id as string,
        commissionBps,
      });
      const action = pixReservationAction({
        inserted: reserved.inserted,
        providerRef: reserved.provider_ref,
        billingType: reserved.billing_type,
        leaseExpired: reserved.lease_expired,
      });
      if (action === "refuse") {
        return json({ error: "pix_reuse_mismatch" }, 409);
      }
      if (action === "busy") {
        return json({ error: "pagamento em andamento" }, 409);
      }
      savedId = reserved.id;
      const expected = {
        customer: customerId,
        valueCents: amountCents,
        walletId: split.walletId,
        percentualValue: split.percentualValue,
      };
      let attemptId = reserved.attempt_id;
      let createPix = action === "create";
      if (action === "reclaim") {
        const found = await asaas.findPix(
          pixExternalReference(groupId, user.id),
        );
        if (found) {
          const full = await asaas.readPayment(found.id);
          if (!pixMatchesCharge(full, expected)) {
            return json({ error: "pix_reuse_mismatch" }, 409);
          }
          const stored = await attachPixProvider(
            admin,
            reserved.id,
            found.id,
            attemptId,
          );
          if (!stored) return json({ error: "pagamento em andamento" }, 409);
          const remote = stored === found.id
            ? full
            : await asaas.readPayment(stored);
          if (stored !== found.id && !pixMatchesCharge(remote, expected)) {
            return json({ error: "pix_reuse_mismatch" }, 409);
          }
          const confirmed = confirmedChargeStatus(String(remote.status ?? ""));
          if (!confirmed) return json({ error: "pix_reuse_mismatch" }, 409);
          const transition = await applyPaymentTransition(
            admin,
            reserved.id,
            confirmed,
            mayCredit && confirmed === "paid",
          );
          status = transition.status;
          providerRef = stored;
          if (status === "pending" && !existing?.qr_code) {
            const qr = await asaas.getPixQrCode(providerRef);
            qrCode = qr.payload;
            qrImage = qr.encodedImage;
            const qrSaved = await admin.from("payment_charges").update({
              qr_code: qrCode,
              qr_code_base64: qrImage,
            }).eq("id", savedId);
            if (qrSaved.error) return json({ error: publicError("erro") }, 400);
          } else {
            qrCode = existing?.qr_code ?? null;
            qrImage = existing?.qr_code_base64 ?? null;
          }
        } else {
          const claimed = await claimExpiredPixReservation(admin, reserved.id);
          if (!claimed) return json({ error: "pagamento em andamento" }, 409);
          attemptId = claimed;
          createPix = true;
        }
      }
      if (action === "reuse" && reserved.provider_ref) {
        const full = await asaas.readPayment(reserved.provider_ref);
        if (asaasPaymentGone(full)) {
          const reopened = await detachGonePix(
            admin,
            reserved.id,
            reserved.provider_ref,
          );
          if (!reopened) return json({ error: "pix_em_aberto" }, 409);
          attemptId = reopened;
          createPix = true;
        } else if (!pixMatchesCharge(full, expected)) {
          return json({ error: "pix_reuse_mismatch" }, 409);
        } else {
          const confirmed = confirmedChargeStatus(String(full.status ?? ""));
          if (!confirmed) return json({ error: "pix_reuse_mismatch" }, 409);
          const transition = await applyPaymentTransition(
            admin,
            reserved.id,
            confirmed,
            mayCredit && confirmed === "paid",
          );
          status = transition.status;
          providerRef = reserved.provider_ref;
          if (status === "pending" && !existing?.qr_code) {
            const qr = await asaas.getPixQrCode(providerRef);
            qrCode = qr.payload;
            qrImage = qr.encodedImage;
            const qrSaved = await admin.from("payment_charges").update({
              qr_code: qrCode,
              qr_code_base64: qrImage,
            }).eq("id", savedId);
            if (qrSaved.error) return json({ error: publicError("erro") }, 400);
          } else {
            qrCode = existing?.qr_code ?? null;
            qrImage = existing?.qr_code_base64 ?? null;
          }
        }
      }
      if (createPix) {
        try {
          const pix = await asaas.createPix({
            customer: customerId,
            value: amountCents / 100,
            dueDate,
            description,
            externalReference: pixExternalReference(groupId, user.id),
            split,
            onCreated: async (payment) => {
              const stored = await attachPixProvider(
                admin,
                reserved.id,
                payment.id,
                attemptId,
              );
              if (stored && stored !== payment.id) {
                if (payment.created) throw new PixReservationLost(payment.id);
                return stored;
              }
              if (!stored || stored !== payment.id) {
                throw new PixReservationLost(payment.id);
              }
              const next = localChargeStatus(payment.status);
              await applyPaymentTransition(
                admin,
                reserved.id,
                next,
                mayCredit && next === "paid",
              );
            },
            onCancelFailed: (paymentId) =>
              recordOrphanPayment(admin, {
                providerRef: paymentId,
                chargeId: reserved.id,
                attemptId,
                billingType: "PIX",
                reason: "cancel_failed",
              }),
          });
          const next = localChargeStatus(pix.status);
          const transition = await applyPaymentTransition(
            admin,
            reserved.id,
            next,
            mayCredit && next === "paid",
          );
          providerRef = pix.id;
          status = transition.status;
          qrCode = pix.payload || null;
          qrImage = pix.encodedImage || null;
          const qrSaved = await admin.from("payment_charges").update({
            qr_code: qrCode,
            qr_code_base64: qrImage,
          }).eq("id", savedId);
          if (qrSaved.error) return json({ error: publicError("erro") }, 400);
        } catch (error) {
          if (releaseReservationOnError(error)) {
            await releasePixReservation(admin, reserved.id, attemptId);
          }
          if (error instanceof PixReservationLost) {
            return json({ error: "pagamento em andamento" }, 409);
          }
          if (error instanceof PixReuseRejected) {
            return json({ error: "pix_reuse_mismatch" }, 409);
          }
          throw error;
        }
      }
    } else {
      const savedCardId = requestedSavedCardId(body);
      if (!savedCardId) {
        return json({ error: "saved_card_id é obrigatório" }, 400);
      }
      const owned = await cardForCharge(
        {
          findOwned: (userId, customerIdForCard, cardId) =>
            findOwnedCard(admin, userId, customerIdForCard, cardId),
        },
        user.id,
        customerId,
        savedCardId,
      );
      let cardChargeId = existing?.id ?? "";
      let attemptId = "";
      const switchInput = existing
        ? {
          billingType: existing.billing_type,
          status: existing.status,
          providerRef: existing.provider_ref,
          leaseExpired: pixLeaseExpired(
            existing.reserved_at ?? null,
            Date.now(),
          ),
        }
        : null;
      const decision = cardSwitchDecision(switchInput);
      if (decision === "refuse") {
        return json({ error: cardSwitchBlock(switchInput) }, 409);
      }
      const remoteIp = clientIp(req) ?? undefined;
      let authorized: { id: string; status: string };
      try {
        authorized = await asaas.authorizeCard({
          customer: customerId,
          value: amountCents / 100,
          dueDate,
          description,
          externalReference: idempotencyKey,
          split,
          remoteIp,
          creditCardToken: owned.creditCardToken,
        });
      } catch (error) {
        if (isCardDeclined(error)) {
          logAsaasFailure("create-charge", error);
          return json({ error: cardDeclined }, 422);
        }
        throw error;
      }
      const loseCard = (chargeId: string, attempt: string | null) =>
        compensateLostPayment(asaas, admin, {
          providerRef: authorized.id,
          status: authorized.status,
          chargeId,
          attemptId: attempt,
          billingType: "CREDIT_CARD",
        });
      if (decision === "cancel_pix" && existing?.provider_ref) {
        const gone = await asaas.cancelPaymentConfirmed(existing.provider_ref);
        if (!gone) {
          await loseCard(existing.id, existing.attempt_id ?? null);
          await recordOrphanPayment(admin, {
            providerRef: existing.provider_ref,
            chargeId: existing.id,
            attemptId: existing.attempt_id ?? null,
            billingType: "PIX",
            reason: "pix_cancel_unconfirmed",
          });
          return json({ error: "pix_em_aberto" }, 409);
        }
        const cleared = await clearPixProviderRef(
          admin,
          existing.id,
          existing.provider_ref,
        );
        if (!cleared) {
          await loseCard(existing.id, existing.attempt_id ?? null);
          return json({ error: "pix_em_aberto" }, 409);
        }
        attemptId = cleared;
        cardChargeId = existing.id;
      }
      if (decision === "drop_lease" && existing) {
        const dropped = await dropExpiredReservation(asaas, admin, {
          chargeId: existing.id,
          attemptId: existing.attempt_id ?? null,
          billingType: existing.billing_type,
          reference: existing.billing_type === "PIX"
            ? pixExternalReference(groupId, user.id)
            : (existing.idempotency_key ?? ""),
        });
        if (!dropped) {
          await loseCard(existing.id, existing.attempt_id ?? null);
          return json({ error: "pagamento em andamento" }, 409);
        }
        cardChargeId = "";
      }
      if (!attemptId) {
        const reservedCard = await reserveCardCharge(admin, {
          groupId,
          userId: user.id,
          venueId: venue.id as string,
          amountCents,
          idempotencyKey,
          walletId: venue.asaas_wallet_id as string,
          commissionBps,
        });
        cardChargeId = reservedCard.id;
        if (reservedCard.inserted && reservedCard.attempt_id) {
          attemptId = reservedCard.attempt_id;
        } else if (
          !reservedCard.provider_ref && reservedCard.lease_expired &&
          reservedCard.attempt_id
        ) {
          const dropped = await dropExpiredReservation(asaas, admin, {
            chargeId: reservedCard.id,
            attemptId: reservedCard.attempt_id,
            billingType: reservedCard.billing_type,
            reference: reservedCard.billing_type === "PIX"
              ? pixExternalReference(groupId, user.id)
              : (reservedCard.idempotency_key ?? idempotencyKey),
          });
          if (!dropped) {
            await loseCard(reservedCard.id, reservedCard.attempt_id);
            return json({ error: "pagamento em andamento" }, 409);
          }
          const again = await reserveCardCharge(admin, {
            groupId,
            userId: user.id,
            venueId: venue.id as string,
            amountCents,
            idempotencyKey,
            walletId: venue.asaas_wallet_id as string,
            commissionBps,
          });
          if (!again.inserted || !again.attempt_id) {
            await loseCard(again.id || reservedCard.id, again.attempt_id);
            return json({ error: "pagamento em andamento" }, 409);
          }
          attemptId = again.attempt_id;
          cardChargeId = again.id;
        } else {
          await loseCard(
            reservedCard.id,
            reservedCard.attempt_id,
          );
          return json({ error: "pagamento em andamento" }, 409);
        }
      }
      const capturedAlready = lostAttemptCompensation(authorized.status) ===
        "refund";
      status = authorized.status === "AUTHORIZED"
        ? "authorized"
        : capturedAlready
        ? "paid"
        : "pending";
      cardView = savedCardView(owned);
      const stored = await attachPixProvider(
        admin,
        cardChargeId,
        authorized.id,
        attemptId,
      );
      if (!stored || stored !== authorized.id) {
        await compensateLostPayment(asaas, admin, {
          providerRef: authorized.id,
          status: authorized.status,
          chargeId: cardChargeId,
          attemptId,
          billingType: "CREDIT_CARD",
        });
        await releasePixReservation(admin, cardChargeId, attemptId);
        return json({ error: "pagamento em andamento" }, 409);
      }
      if (!capturedAlready && mayCredit && status === "authorized") {
        const held = await applyPaymentTransition(
          admin,
          cardChargeId,
          "authorized",
          false,
        );
        if (held.status !== "authorized") {
          await compensateLostPayment(asaas, admin, {
            providerRef: stored,
            status: "AUTHORIZED",
            chargeId: cardChargeId,
            attemptId,
            billingType: "CREDIT_CARD",
          });
          return json({ error: "pagamento em andamento" }, 409);
        }
        try {
          const captured = await asaas.capture(stored);
          status = captured.status === "CONFIRMED" ||
              captured.status === "RECEIVED"
            ? "paid"
            : "authorized";
        } catch (_captureError) {
          let refunded = false;
          try {
            await asaas.refund(stored);
            refunded = true;
          } catch (_refundError) {
            await recordOrphanPayment(admin, {
              providerRef: stored,
              chargeId: cardChargeId,
              attemptId,
              billingType: "CREDIT_CARD",
              reason: "refund_failed",
            });
            status = "authorized";
          }
          if (refunded) {
            await applyPaymentTransition(
              admin,
              cardChargeId,
              "cancelled",
              false,
            );
            await deleteCompensatedCharge(admin, {
              chargeId: cardChargeId,
              attemptId,
              providerRef: stored,
            });
            return json({ error: "erro" }, 502);
          }
        }
      }
      const transition = await applyPaymentTransition(
        admin,
        cardChargeId,
        status,
        mayCredit && status === "paid",
      );
      status = transition.status;
      providerRef = stored;
      savedId = cardChargeId;
    }

    return json({
      charge_id: savedId,
      status,
      provider_ref: providerRef,
      qr_code: qrCode,
      qr_code_base64: qrImage,
      billing_type: billingType,
      amount_cents: amountCents,
      ...(cardView ?? {}),
    });
  } catch (error) {
    const failure = clientFailure(error, "create-charge");
    return json({
      ...failure.body,
      error: publicError(failure.body.error),
    }, failure.status);
  }
}

if (import.meta.main) {
  Deno.serve((req) => createCharge(req));
}

type ChargeDb = {
  from(...args: unknown[]): any;
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: { code?: string } | null }>;
};

function findOwnedCard(
  admin: ChargeDb,
  userId: string,
  customerId: string,
  cardId: string,
): Promise<SavedCard | null> {
  return loadOwnedCard(admin, userId, customerId, cardId);
}

type ReservedPix = {
  id: string;
  status: string;
  provider_ref: string | null;
  billing_type: string;
  amount_cents: number;
  inserted: boolean;
  lease_expired: boolean;
  attempt_id: string | null;
  idempotency_key: string | null;
};

async function reservePixCharge(
  admin: ChargeDb,
  input: {
    groupId: string;
    userId: string;
    venueId: string;
    amountCents: number;
    idempotencyKey: string;
    walletId: string;
    commissionBps: number;
  },
): Promise<ReservedPix> {
  const { data, error } = await admin.rpc("reserve_pix_charge", {
    p_group_id: input.groupId,
    p_user_id: input.userId,
    p_venue_id: input.venueId,
    p_amount_cents: input.amountCents,
    p_idempotency_key: input.idempotencyKey,
    p_wallet_id: input.walletId,
    p_commission_bps: input.commissionBps,
  });
  if (error || !data || typeof data !== "object") throw new Error("erro");
  return parseReserved(data as Record<string, unknown>);
}

function parseReserved(row: Record<string, unknown>): ReservedPix {
  const id = typeof row.id === "string" ? row.id : "";
  if (!id) throw new Error("erro");
  return {
    id,
    status: typeof row.status === "string" ? row.status : "",
    provider_ref: typeof row.provider_ref === "string"
      ? row.provider_ref
      : null,
    billing_type: typeof row.billing_type === "string" ? row.billing_type : "",
    amount_cents: typeof row.amount_cents === "number" ? row.amount_cents : 0,
    inserted: row.inserted === true,
    lease_expired: row.lease_expired === true,
    attempt_id: typeof row.attempt_id === "string" ? row.attempt_id : null,
    idempotency_key: typeof row.idempotency_key === "string"
      ? row.idempotency_key
      : null,
  };
}

async function reserveCardCharge(
  admin: ChargeDb,
  input: {
    groupId: string;
    userId: string;
    venueId: string;
    amountCents: number;
    idempotencyKey: string;
    walletId: string;
    commissionBps: number;
  },
): Promise<ReservedPix> {
  const { data, error } = await admin.rpc("reserve_card_charge", {
    p_group_id: input.groupId,
    p_user_id: input.userId,
    p_venue_id: input.venueId,
    p_amount_cents: input.amountCents,
    p_idempotency_key: input.idempotencyKey,
    p_wallet_id: input.walletId,
    p_commission_bps: input.commissionBps,
  });
  if (error || !data || typeof data !== "object") throw new Error("erro");
  return parseReserved(data as Record<string, unknown>);
}

async function attachPixProvider(
  admin: ChargeDb,
  chargeId: string,
  providerRef: string,
  attemptId: string | null,
): Promise<string | null> {
  const { data, error } = await admin.rpc("attach_pix_provider", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
    p_attempt_id: attemptId,
  });
  if (error) throw new Error("erro");
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function claimExpiredPixReservation(
  admin: ChargeDb,
  chargeId: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("claim_expired_pix_reservation", {
    p_charge_id: chargeId,
  });
  if (error) throw new Error("erro");
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function releasePixReservation(
  admin: ChargeDb,
  chargeId: string,
  attemptId: string | null,
): Promise<void> {
  const { error } = await admin.rpc("release_pix_reservation", {
    p_charge_id: chargeId,
    p_attempt_id: attemptId,
  });
  if (error) throw new Error("erro");
}

async function releaseExpiredPixReservation(
  admin: ChargeDb,
  chargeId: string,
  attemptId: string | null,
): Promise<boolean> {
  const { data, error } = await admin.rpc("release_expired_pix_reservation", {
    p_charge_id: chargeId,
    p_attempt_id: attemptId,
  });
  if (error) throw new Error("erro");
  return data === true;
}

async function detachGonePix(
  admin: ChargeDb,
  chargeId: string,
  providerRef: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("detach_gone_pix", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
  });
  if (error) throw new Error("erro");
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function clearPixProviderRef(
  admin: ChargeDb,
  chargeId: string,
  providerRef: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("clear_pix_provider_ref", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
  });
  if (error) throw new Error("erro");
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function deleteCompensatedCharge(
  admin: ChargeDb,
  input: { chargeId: string; attemptId: string | null; providerRef: string },
): Promise<void> {
  const { error } = await admin.rpc("delete_compensated_charge", {
    p_charge_id: input.chargeId,
    p_attempt_id: input.attemptId,
    p_provider_ref: input.providerRef,
  });
  if (error) throw new Error("erro");
}

async function recordOrphanPayment(
  admin: ChargeDb,
  input: {
    providerRef: string;
    chargeId: string;
    attemptId: string | null;
    billingType: string;
    reason: string;
  },
): Promise<void> {
  const { error } = await admin.rpc("record_orphan_payment", {
    p_provider_ref: input.providerRef,
    p_charge_id: input.chargeId,
    p_attempt_id: input.attemptId,
    p_billing_type: input.billingType,
    p_reason: input.reason,
  });
  if (error) throw new Error("erro");
}

async function dropExpiredReservation(
  asaas: AsaasProvider,
  admin: ChargeDb,
  input: {
    chargeId: string;
    attemptId: string | null;
    billingType: string;
    reference: string;
  },
): Promise<boolean> {
  if (input.reference) {
    const remote = await asaas.findByExternalReference(input.reference);
    if (remote) {
      if (lostAttemptCompensation(remote.status) === "refund") return false;
      const gone = await asaas.cancelPaymentConfirmed(remote.id);
      if (!gone) {
        await recordOrphanPayment(admin, {
          providerRef: remote.id,
          chargeId: input.chargeId,
          attemptId: input.attemptId,
          billingType: remote.billingType || input.billingType,
          reason: "cancel_failed",
        });
        return false;
      }
    }
  }
  return await releaseExpiredPixReservation(
    admin,
    input.chargeId,
    input.attemptId,
  );
}

async function compensateLostPayment(
  asaas: AsaasProvider,
  admin: ChargeDb,
  input: {
    providerRef: string;
    status: string;
    chargeId: string;
    attemptId: string | null;
    billingType: string;
  },
): Promise<void> {
  const action = lostAttemptCompensation(input.status);
  if (action === "none") return;
  try {
    if (action === "refund") await asaas.refund(input.providerRef);
    else await asaas.cancelAuthorization(input.providerRef);
  } catch (_error) {
    await recordOrphanPayment(admin, {
      providerRef: input.providerRef,
      chargeId: input.chargeId,
      attemptId: input.attemptId,
      billingType: input.billingType,
      reason: action === "refund" ? "refund_failed" : "cancel_failed",
    });
  }
}

async function groupClosedForCredit(
  admin: ChargeDb,
  group: {
    id: string;
    cancelled_at: string | null;
    closed_at: string | null;
    total_spots: number;
    minimum_spots: number;
  },
): Promise<boolean> {
  if (group.cancelled_at) return false;
  const filled = await filledSpots(admin, group.id);
  const closed = Boolean(group.closed_at) || filled >= group.total_spots;
  return closed && filled >= group.minimum_spots;
}

async function filledSpots(
  admin: ChargeDb,
  groupId: string,
): Promise<number> {
  const { count } = await admin
    .from("group_members")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .neq("attendance", "cancelled");
  return count ?? 0;
}
