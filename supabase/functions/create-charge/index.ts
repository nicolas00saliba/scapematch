import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider, houseSplitPercent } from "../_shared/asaas_provider.ts";
import { clientIp } from "../_shared/client_ip.ts";
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
      existing && !["failed", "cancelled", "refunded"].includes(existing.status)
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

    const { data: settings } = await admin
      .from("platform_settings")
      .select("commission_bps")
      .eq("id", 1)
      .single();
    const commissionBps = settings?.commission_bps ?? 1000;
    const split = {
      walletId: venue.asaas_wallet_id as string,
      percentualValue: houseSplitPercent(commissionBps),
    };

    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, asaas_customer_id")
      .eq("id", user.id)
      .maybeSingle();
    const asaas = AsaasProvider.fromEnv(Deno.env);
    let customerId = profile?.asaas_customer_id as string | null;
    if (!customerId) {
      const created = await asaas.createCustomer({
        name: profile?.display_name ?? "Jogador",
        email: user.email ?? "",
        externalReference: user.id,
      });
      customerId = created.id;
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

    if (billingType === "PIX") {
      const pix = await asaas.createPix({
        customer: customerId,
        value: amountCents / 100,
        dueDate,
        description,
        externalReference: idempotencyKey,
        split,
      });
      providerRef = pix.id;
      status = "pending";
      qrCode = pix.payload;
      qrImage = pix.encodedImage;
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
    if (saved.error) {
      return json({ error: publicError(saved.error.message) }, 400);
    }

    const memberStatus = status === "paid"
      ? "paid"
      : status === "authorized"
      ? "reserved"
      : "pending";
    await admin.from("group_members").update({ payment_status: memberStatus })
      .eq("id", member.id);

    return json({
      charge_id: saved.data.id,
      status,
      provider_ref: providerRef,
      qr_code: qrCode,
      qr_code_base64: qrImage,
      billing_type: billingType,
      amount_cents: amountCents,
      ...(cardView ?? {}),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "erro";
    const status = message === "cartão não encontrado" ? 403 : 500;
    return json({ error: publicError(message) }, status);
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
