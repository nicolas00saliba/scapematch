import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure } from "../_shared/asaas_client_error.ts";
import { AsaasProvider, houseSplitPercent } from "../_shared/asaas_provider.ts";
import { pixExternalReference, pixNeedsQr } from "../_shared/pix_charge.ts";
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
    const refreshQr = Boolean(
      existing && pixNeedsQr({
        status: existing.status,
        billing_type: existing.billing_type,
        provider_ref: existing.provider_ref,
        qr_code: existing.qr_code,
      }),
    );
    if (
      existing &&
      !refreshQr &&
      !["failed", "cancelled", "refunded"].includes(existing.status) &&
      (existing.provider_ref || existing.qr_code ||
        existing.billing_type !== "PIX")
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
    if (refreshQr && existing?.provider_ref) {
      const qr = await asaas.getPixQrCode(existing.provider_ref);
      const { error: qrError } = await admin.from("payment_charges").update({
        qr_code: qr.payload,
        qr_code_base64: qr.encodedImage,
      }).eq("id", existing.id);
      if (qrError) return json({ error: publicError("erro") }, 400);
      if (existing.status === "pending") {
        await admin.from("group_members").update({ payment_status: "pending" })
          .eq("id", member.id);
      }
      return json({
        charge_id: existing.id,
        status: existing.status,
        provider_ref: existing.provider_ref,
        qr_code: qr.payload,
        qr_code_base64: qr.encodedImage,
        billing_type: existing.billing_type,
        amount_cents: existing.amount_cents,
      });
    }

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

    if (billingType === "PIX") {
      const pix = await asaas.createPix({
        customer: customerId,
        value: amountCents / 100,
        dueDate,
        description,
        externalReference: pixExternalReference(groupId, user.id),
        split,
        onCreated: async (payment) => {
          providerRef = payment.id;
          savedId = await persistPixCharge(admin, {
            existingId: existing?.id,
            groupId,
            userId: user.id,
            venueId: venue.id as string,
            amountCents,
            providerRef: payment.id,
            idempotencyKey,
            walletId: venue.asaas_wallet_id as string,
            commissionBps,
          });
        },
      });
      providerRef = pix.id;
      status = "pending";
      qrCode = pix.payload;
      qrImage = pix.encodedImage;
      if (!savedId) throw new Error("erro");
      const qrSaved = await admin.from("payment_charges").update({
        qr_code: qrCode,
        qr_code_base64: qrImage,
        provider_ref: providerRef,
        status,
      }).eq("id", savedId);
      if (qrSaved.error) return json({ error: publicError("erro") }, 400);
    } else {
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
    }

    if (billingType !== "PIX") {
      const row = {
        group_id: groupId,
        user_id: user.id,
        venue_id: venue.id,
        amount_cents: amountCents,
        billing_type: billingType,
        status,
        provider: "asaas",
        provider_ref: providerRef,
        qr_code: qrCode,
        qr_code_base64: qrImage,
        idempotency_key: idempotencyKey,
        wallet_id: venue.asaas_wallet_id,
        commission_bps: commissionBps,
        paid_at: status === "paid" ? new Date().toISOString() : null,
      };
      const saved = existing
        ? await admin.from("payment_charges").update(row).eq("id", existing.id)
          .select("id").single()
        : await admin.from("payment_charges").insert(row).select("id").single();
      if (saved.error || !saved.data?.id) {
        return json({ error: publicError("erro") }, 400);
      }
      savedId = saved.data.id as string;
    }

    const memberStatus = status === "paid"
      ? "paid"
      : status === "authorized"
      ? "reserved"
      : "pending";
    await admin.from("group_members").update({ payment_status: memberStatus })
      .eq("id", member.id);

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
  ): PromiseLike<{ data: unknown; error: unknown }>;
};

function findOwnedCard(
  admin: ChargeDb,
  userId: string,
  customerId: string,
  cardId: string,
): Promise<SavedCard | null> {
  return loadOwnedCard(admin, userId, customerId, cardId);
}

async function persistPixCharge(
  admin: ChargeDb,
  input: {
    existingId?: string;
    groupId: string;
    userId: string;
    venueId: string;
    amountCents: number;
    providerRef: string;
    idempotencyKey: string;
    walletId: string;
    commissionBps: number;
  },
): Promise<string> {
  const row = {
    group_id: input.groupId,
    user_id: input.userId,
    venue_id: input.venueId,
    amount_cents: input.amountCents,
    billing_type: "PIX",
    status: "pending",
    provider: "asaas",
    provider_ref: input.providerRef,
    qr_code: null,
    qr_code_base64: null,
    idempotency_key: input.idempotencyKey,
    wallet_id: input.walletId,
    commission_bps: input.commissionBps,
    paid_at: null,
    refunded_at: null,
  };
  if (input.existingId) {
    const updated = await admin.from("payment_charges").update(row).eq(
      "id",
      input.existingId,
    );
    if (updated.error) throw new Error("erro");
    return input.existingId;
  }
  const inserted = await admin.from("payment_charges").insert(row).select("id")
    .single();
  if (!inserted.error && inserted.data?.id) return inserted.data.id as string;
  if (inserted.error?.code !== "23505") throw new Error("erro");
  const found = await admin.from("payment_charges").select("id").eq(
    "group_id",
    input.groupId,
  ).eq("user_id", input.userId).maybeSingle();
  if (!found.data?.id) throw new Error("erro");
  const id = found.data.id as string;
  const updated = await admin.from("payment_charges").update({
    provider_ref: input.providerRef,
    status: "pending",
    billing_type: "PIX",
    provider: "asaas",
    qr_code: null,
    qr_code_base64: null,
    refunded_at: null,
  }).eq("id", id);
  if (updated.error) throw new Error("erro");
  return id;
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
