import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { corsHeaders, json } from "../_shared/http.ts";

type VenueRow = {
  id: string;
  owner_id: string;
  name: string;
  document_kind: string;
  document_number: string;
  phone: string;
  street_address: string;
  address_number: string;
  neighborhood: string;
  postal_code: string;
  income_value: number;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "not authenticated" }, 401);

    const admin = createClient(url, service);
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    if (!adminRow) return json({ error: "not admin" }, 403);

    const body = await req.json().catch(() => ({})) as { venue_id?: string };
    let query = admin
      .from("venues")
      .select(
        "id, owner_id, name, document_kind, document_number, phone, street_address, address_number, neighborhood, postal_code, income_value",
      )
      .eq("status", "approved")
      .is("asaas_wallet_id", null);
    if (body.venue_id) query = query.eq("id", body.venue_id);
    const { data: venues, error } = await query;
    if (error) return json({ error: error.message }, 400);

    const asaas = AsaasProvider.fromEnv(Deno.env);
    const provisioned: { venue_id: string; wallet_id: string }[] = [];
    for (const venue of (venues ?? []) as VenueRow[]) {
      const owner = await admin.auth.admin.getUserById(venue.owner_id);
      const email = owner.data.user?.email;
      if (!email) {
        return json({ error: `Sem e-mail do dono da casa ${venue.id}` }, 422);
      }
      const { data: profile } = await admin
        .from("profiles")
        .select("birth_date")
        .eq("id", venue.owner_id)
        .maybeSingle();
      const created = await asaas.createSubaccount({
        name: venue.name,
        email,
        cpfCnpj: venue.document_number,
        companyType: venue.document_kind === "cnpj" ? "LIMITED" : undefined,
        birthDate: venue.document_kind === "cpf"
          ? profile?.birth_date ?? undefined
          : undefined,
        phone: venue.phone,
        mobilePhone: venue.phone,
        incomeValue: Number(venue.income_value),
        address: venue.street_address,
        addressNumber: venue.address_number,
        province: venue.neighborhood,
        postalCode: venue.postal_code,
      });
      const { error: updateError } = await admin
        .from("venues")
        .update({ asaas_wallet_id: created.walletId })
        .eq("id", venue.id);
      if (updateError) return json({ error: updateError.message }, 400);
      const { error: keyError } = await admin.from("venue_asaas_keys").upsert({
        venue_id: venue.id,
        api_key: created.apiKey,
      });
      if (keyError) return json({ error: keyError.message }, 400);
      provisioned.push({ venue_id: venue.id, wallet_id: created.walletId });
    }
    return json({ provisioned });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "erro" }, 500);
  }
});
