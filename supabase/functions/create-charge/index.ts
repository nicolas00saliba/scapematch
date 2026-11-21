import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { createAlternateCharge } from "../_shared/alternate_charge.ts";
import { clientFailure } from "../_shared/client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import type { EnvLike } from "../_shared/http.ts";
import type { MercadoPagoProvider } from "../_shared/mercadopago_provider.ts";
import {
  denoEnv,
  groupUnconfirmedNotice,
  isHistoricalAsaas,
} from "../_shared/payment_provider.ts";
import { hasRawCardData } from "../_shared/raw_card.ts";
import type { WooviProvider } from "../_shared/woovi_provider.ts";

type ChargeBody = {
  group_id?: string;
  billing_type?: string;
  idempotency_key?: string;
  saved_card_id?: string;
  card_token?: string;
  payment_method_id?: string;
  points?: number;
};

type ChargeUser = { id: string; email?: string | null };

type ChargeRow = {
  id: string;
  status: string;
  provider: string | null;
  provider_ref: string | null;
  qr_code: string | null;
  qr_code_base64: string | null;
  billing_type: string;
  amount_cents: number;
};

type ChargeDb = {
  // O cliente do Supabase e o dublê dos testes.
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
};

export type ChargeRuntime = {
  user: ChargeUser;
  admin: ChargeDb;
  woovi?: WooviProvider;
  mercadoPago?: MercadoPagoProvider;
  now?: Date;
  env?: EnvLike;
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
      admin = createClient(url, service) as unknown as ChargeDb;
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
        "id, venue_id, price_cents, cancelled_at, confirmed_at, closed_at, closes_at, starts_at, total_spots, minimum_spots",
      )
      .eq("id", groupId)
      .maybeSingle();
    const groupRow = group as Record<string, unknown> | null;
    if (!groupRow || groupRow.cancelled_at) {
      return json({ error: "group not found" }, 404);
    }
    if (new Date(String(groupRow.starts_at)).getTime() <= Date.now()) {
      return json({ error: "session started" }, 409);
    }

    const { data: member } = await admin
      .from("group_members")
      .select("id, attendance")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    const memberRow = member as { attendance?: string } | null;
    if (!memberRow || memberRow.attendance === "cancelled") {
      return json({ error: "not member" }, 403);
    }

    const { data: existing } = await admin
      .from("payment_charges")
      .select(
        "id, status, provider, qr_code, qr_code_base64, provider_ref, billing_type, amount_cents",
      )
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    const charge = existing as ChargeRow | null;
    if (charge?.provider === "points" && charge.status === "paid") {
      return json({
        charge_id: charge.id,
        status: "paid",
        provider: "points",
        provider_ref: null,
        qr_code: "",
        qr_code_base64: null,
        billing_type: charge.billing_type,
        amount_cents: 0,
        points_only: true,
      });
    }
    if (charge && isHistoricalAsaas(charge.provider)) {
      return json({
        charge_id: charge.id,
        status: charge.status,
        provider: "asaas",
        provider_ref: charge.provider_ref,
        qr_code: charge.qr_code ?? "",
        qr_code_base64: charge.qr_code_base64,
        billing_type: charge.billing_type,
        amount_cents: charge.amount_cents,
        read_only: true,
        notice: groupUnconfirmedNotice,
      });
    }

    return await createAlternateCharge({
      json,
      admin: admin as never,
      user,
      group: groupRow,
      existing: (charge as unknown as Record<string, unknown> | null) ?? null,
      body: body as Record<string, unknown>,
      groupId,
      billingType,
      idempotencyKey,
      woovi: deps?.woovi,
      mercadoPago: deps?.mercadoPago,
      now: deps?.now,
      env: deps?.env ?? denoEnv(),
    });
  } catch (error) {
    const failure = clientFailure(error, "create-charge");
    return json(failure.body, failure.status);
  }
}

if (import.meta.main) {
  Deno.serve((req) => createCharge(req));
}
