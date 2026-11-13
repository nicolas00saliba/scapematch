import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import {
  clientFailure,
  logAsaasFailure,
  logCaught,
} from "../_shared/asaas_client_error.ts";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { companyTypeForSubaccount } from "../_shared/subaccount_company.ts";
import { isPointsReserve } from "../_shared/asaas_transfers.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import {
  nextSubaccountEmail,
  subaccountEmailPlan,
} from "../_shared/subaccount_email.ts";
import {
  ensureTransferWebhook,
  transferClient,
} from "../_shared/venue_payouts.ts";

type VenueRow = {
  id: string;
  owner_id: string;
  name: string;
  document_kind: string;
  document_number: string;
  company_type: string | null;
  phone: string;
  street_address: string;
  address_number: string;
  neighborhood: string;
  postal_code: string;
  income_value: number;
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
    if (userError || !userData.user) {
      return json({ error: "not authenticated" }, 401);
    }

    const admin = createClient(url, service);
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();

    const body = await req.json().catch(() => ({})) as { venue_id?: string };
    const venueId = (body.venue_id ?? "").trim();
    if (!adminRow && !venueId) return json({ error: "not admin" }, 403);
    let query = admin
      .from("venues")
      .select(
        "id, owner_id, name, document_kind, document_number, company_type, phone, street_address, address_number, neighborhood, postal_code, income_value",
      )
      .eq("status", "approved")
      .is("asaas_wallet_id", null);
    if (venueId) query = query.eq("id", venueId);
    if (!adminRow) query = query.eq("owner_id", userData.user.id);
    const { data: venues, error } = await query;
    if (error) return json({ error: "erro" }, 400);

    const asaas = AsaasProvider.fromEnv(Deno.env);
    const provisioned: { venue_id: string }[] = [];
    for (const venue of (venues ?? []) as VenueRow[]) {
      const { data: profile } = await admin
        .from("profiles")
        .select("birth_date")
        .eq("id", venue.owner_id)
        .maybeSingle();
      const plan = subaccountEmailPlan(venue, Deno.env);
      const birthDate = venue.document_kind === "cpf"
        ? profile?.birth_date ?? undefined
        : undefined;
      const created = await openSubaccount(asaas, venue, plan, birthDate);
      const { error: updateError } = await admin
        .from("venues")
        .update({ asaas_wallet_id: created.walletId })
        .eq("id", venue.id);
      if (updateError) return json({ error: "erro" }, 400);
      const { error: keyError } = await admin.rpc("store_venue_asaas_key", {
        p_venue_id: venue.id,
        p_api_key: created.apiKey,
      });
      if (keyError) return json({ error: "erro" }, 400);
      if (!isPointsReserve(Deno.env, created.walletId, created.apiKey)) {
        try {
          await ensureTransferWebhook(
            transferClient(asaas.withKey(created.apiKey)),
            Deno.env,
          );
        } catch (error) {
          logCaught("provision-venue-wallet", error);
        }
      }
      provisioned.push({ venue_id: venue.id });
    }
    return json({ provisioned });
  } catch (error) {
    const failure = clientFailure(error, "provision-venue-wallet");
    return json(failure.body, failure.status);
  }
});

function subaccountBody(
  venue: VenueRow,
  email: string,
  birthDate: string | undefined,
) {
  return {
    name: venue.name,
    email,
    cpfCnpj: venue.document_number,
    companyType: companyTypeForSubaccount(
      venue.document_kind,
      venue.company_type,
    ),
    birthDate,
    phone: venue.phone,
    mobilePhone: venue.phone,
    incomeValue: Number(venue.income_value),
    address: venue.street_address,
    addressNumber: venue.address_number,
    province: venue.neighborhood,
    postalCode: venue.postal_code,
  };
}

async function openSubaccount(
  asaas: AsaasProvider,
  venue: VenueRow,
  plan: { primary: string; alias: string },
  birthDate: string | undefined,
) {
  try {
    return await asaas.createSubaccount(
      subaccountBody(venue, plan.primary, birthDate),
    );
  } catch (error) {
    const alias = nextSubaccountEmail(plan.primary, plan.alias, error);
    if (!alias) throw error;
    logAsaasFailure("provision-venue-wallet", error);
    return await asaas.createSubaccount(
      subaccountBody(venue, alias, birthDate),
    );
  }
}
