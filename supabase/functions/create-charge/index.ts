import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/asaas_client_error.ts";
import {
  AsaasProvider,
  houseSplitPercent,
  PixReservationLost,
  PixReuseRejected,
} from "../_shared/asaas_provider.ts";
import { confirmedChargeStatus } from "../_shared/charge_patch.ts";
import { applyPaymentTransition } from "../_shared/ledger.ts";
import {
  cardSwitchDecision,
  localChargeStatus,
  pixExternalReference,
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

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth
      .getUser();
    const user = userData.user;
    if (userError || !user) return json({ error: "not authenticated" }, 401);

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

    const admin = createClient(url, service);
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
        "id, status, qr_code, qr_code_base64, provider_ref, billing_type, amount_cents",
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

    const asaas = AsaasProvider.fromEnv(Deno.env);
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
          const stored = await attachPixProvider(admin, reserved.id, found.id);
          if (!stored) return json({ error: "pagamento em andamento" }, 409);
          const confirmed = confirmedChargeStatus(String(full.status ?? ""));
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
          createPix = true;
        }
      }
      if (action === "reuse" && reserved.provider_ref) {
        const full = await asaas.readPayment(reserved.provider_ref);
        if (!pixMatchesCharge(full, expected)) {
          return json({ error: "pix_reuse_mismatch" }, 409);
        }
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
      } else if (createPix) {
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
              );
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
          });
          providerRef = pix.id;
          status = localChargeStatus(pix.status);
          qrCode = pix.payload || null;
          qrImage = pix.encodedImage || null;
          const qrSaved = await admin.from("payment_charges").update({
            qr_code: qrCode,
            qr_code_base64: qrImage,
          }).eq("id", savedId);
          if (qrSaved.error) return json({ error: publicError("erro") }, 400);
        } catch (error) {
          if (releaseReservationOnError(error)) {
            await releasePixReservation(admin, reserved.id);
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
      let cardChargeId = existing?.id ?? "";
      // drop_lease pede o DELETE só da reserva vencida. A função SQL
      // recusa a linha fresca, então o cartão não apaga um Pix em criação.
      const decision = cardSwitchDecision(
        existing
          ? {
            billingType: existing.billing_type,
            status: existing.status,
            providerRef: existing.provider_ref,
            leaseExpired: true,
          }
          : null,
      );
      if (decision === "refuse") {
        return json({ error: "pix_em_aberto" }, 409);
      }
      if (decision === "cancel_pix" && existing?.provider_ref) {
        const gone = await asaas.cancelPaymentConfirmed(existing.provider_ref);
        if (!gone) return json({ error: "pix_em_aberto" }, 409);
        const cleared = await clearPixProviderRef(
          admin,
          existing.id,
          existing.provider_ref,
        );
        if (!cleared) return json({ error: "pix_em_aberto" }, 409);
      }
      if (decision === "drop_lease" && existing) {
        const dropped = await releaseExpiredPixReservation(admin, existing.id);
        if (!dropped) return json({ error: "pagamento em andamento" }, 409);
        cardChargeId = "";
      }
      const remoteIp = clientIp(req) ?? undefined;
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
      const authorized = await asaas.authorizeCard({
        customer: customerId,
        value: amountCents / 100,
        dueDate,
        description,
        externalReference: idempotencyKey,
        split,
        remoteIp,
        creditCardToken: owned.creditCardToken,
      });
      providerRef = authorized.id;
      status = authorized.status === "AUTHORIZED" ? "authorized" : "pending";
      cardView = savedCardView(owned);
      const filled = await filledSpots(admin, groupId);
      const closed = Boolean(group.closed_at) || filled >= group.total_spots;
      if (closed && filled >= group.minimum_spots && status === "authorized") {
        const captured = await asaas.capture(providerRef);
        status =
          captured.status === "CONFIRMED" || captured.status === "RECEIVED"
            ? "paid"
            : "authorized";
      }
      if (!cardChargeId) {
        const inserted = await admin.from("payment_charges").insert({
          group_id: groupId,
          user_id: user.id,
          venue_id: venue.id,
          amount_cents: amountCents,
          billing_type: "CREDIT_CARD",
          status: "creating",
          provider: "asaas",
          provider_ref: null,
          idempotency_key: idempotencyKey,
          wallet_id: venue.asaas_wallet_id,
          commission_bps: commissionBps,
        }).select("id").single();
        if (inserted.error || !inserted.data?.id) {
          await asaas.cancelAuthorization(providerRef).catch(() => undefined);
          return json({ error: publicError("erro") }, 400);
        }
        cardChargeId = inserted.data.id as string;
      }
      const stored = await attachPixProvider(admin, cardChargeId, providerRef);
      if (!stored || stored !== providerRef) {
        await asaas.cancelAuthorization(providerRef).catch(() => undefined);
        return json({ error: "pix_em_aberto" }, 409);
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
});

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
  const row = data as Record<string, unknown>;
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
  };
}

async function attachPixProvider(
  admin: ChargeDb,
  chargeId: string,
  providerRef: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("attach_pix_provider", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
  });
  if (error) throw new Error("erro");
  return typeof data === "string" && data.length > 0 ? data : null;
}

async function claimExpiredPixReservation(
  admin: ChargeDb,
  chargeId: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("claim_expired_pix_reservation", {
    p_charge_id: chargeId,
  });
  if (error) throw new Error("erro");
  return data === true;
}

async function releasePixReservation(
  admin: ChargeDb,
  chargeId: string,
): Promise<void> {
  const { error } = await admin.rpc("release_pix_reservation", {
    p_charge_id: chargeId,
  });
  if (error) throw new Error("erro");
}

async function releaseExpiredPixReservation(
  admin: ChargeDb,
  chargeId: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("release_expired_pix_reservation", {
    p_charge_id: chargeId,
  });
  if (error) throw new Error("erro");
  return data === true;
}

async function clearPixProviderRef(
  admin: ChargeDb,
  chargeId: string,
  providerRef: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("clear_pix_provider_ref", {
    p_charge_id: chargeId,
    p_provider_ref: providerRef,
  });
  if (error) throw new Error("erro");
  return data === true;
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
