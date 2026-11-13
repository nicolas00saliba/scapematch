import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import {
  deliverClaimCode,
  publicClaimResult,
  sendClaimMail,
  sendClaimSms,
} from "../_shared/venue_claim.ts";

type Issued = {
  status?: string;
  code_id?: string;
  code?: string;
  email?: string | null;
  phone?: string | null;
  venue_id?: string;
  venue_name?: string;
  claim_id?: string;
};

Deno.serve(async (req) => {
  const json = bindJson(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req, Deno.env) });
  }
  if (req.method !== "POST") return json({ error: "method" }, 405);
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
    if (userError || !userData.user) {
      return json({ error: "not authenticated" }, 401);
    }

    const body = await req.json().catch(() => ({})) as {
      action?: string;
      venue_id?: string;
      code?: string;
    };
    const venueId = (body.venue_id ?? "").trim();
    if (!/^[0-9a-f-]{36}$/i.test(venueId)) {
      return json({ error: "valor" }, 400);
    }
    const admin = createClient(url, service);
    const claimant = userData.user.id;

    if (body.action === "send") {
      const { data, error } = await admin.rpc("issue_venue_claim_code", {
        p_venue_id: venueId,
        p_claimant: claimant,
      });
      if (error) return json({ error: "erro" }, 400);
      const issued = (data ?? {}) as Issued;
      if (issued.status === "otp" && issued.code && issued.code_id) {
        const delivery = await deliverClaimCode(
          {
            code: issued.code,
            venueName: issued.venue_name ?? "sua casa",
            email: issued.email ?? null,
            phone: issued.phone ?? null,
          },
          {
            mail: (input) => sendClaimMail(Deno.env, fetch, input),
            sms: (input) => sendClaimSms(Deno.env, fetch, input),
          },
        );
        if (delivery !== "sent") {
          const aborted = await admin.rpc("abort_venue_claim_code", {
            p_code_id: issued.code_id,
            p_claimant: claimant,
          });
          if (aborted.error) return json({ error: "erro" }, 400);
          return json(publicClaimResult({ status: "manual" }));
        }
      }
      return json(publicClaimResult({
        status: issued.status ?? "not_found",
        email: issued.email,
        phone: issued.phone,
      }));
    }

    if (body.action === "confirm") {
      const code = (body.code ?? "").trim();
      if (!/^[0-9]{6}$/.test(code)) return json({ error: "valor" }, 400);
      const { data, error } = await admin.rpc("confirm_venue_claim_code", {
        p_venue_id: venueId,
        p_claimant: claimant,
        p_code: code,
      });
      if (error) return json({ error: "erro" }, 400);
      const status = (data as { status?: string } | null)?.status ?? "fail";
      if (status !== "confirmed") return json({ status }, 400);
      return json({ status: "confirmed", venue_id: venueId });
    }

    return json({ error: "valor" }, 400);
  } catch (_error) {
    return json({ error: "erro" }, 400);
  }
});
