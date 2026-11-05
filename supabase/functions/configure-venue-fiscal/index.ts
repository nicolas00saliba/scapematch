import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { AsaasProvider } from "../_shared/asaas_provider.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";

type Body = {
  venue_id?: string;
  municipal_inscription?: string;
  service_code?: string;
  service_name?: string;
  iss_rate?: number;
  simples_nacional?: boolean;
  mei?: boolean;
  cnae?: string;
  rps_serie?: string;
  rps_number?: number;
  municipal_username?: string;
  municipal_password?: string;
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
    const { data: userData } = await userClient.auth.getUser();
    if (!userData.user) return json({ error: "not authenticated" }, 401);

    const body = await req.json().catch(() => ({})) as Body;
    const venueId = body.venue_id ?? "";
    if (!venueId) return json({ error: "venue_id obrigatório" }, 400);

    const admin = createClient(url, service);
    const { data: adminRow } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    const { data: venue } = await admin
      .from("venues")
      .select("id, owner_id, name, document_kind")
      .eq("id", venueId)
      .maybeSingle();
    if (!venue) return json({ error: "casa não encontrada" }, 404);
    if (venue.owner_id !== userData.user.id && !adminRow) {
      return json({ error: "not owner" }, 403);
    }

    const owner = await admin.auth.admin.getUserById(venue.owner_id as string);
    const email = owner.data.user?.email ?? "";
    const inscription = (body.municipal_inscription ?? "").trim();
    const serviceCode = (body.service_code ?? "").trim();
    const serviceName = (body.service_name ?? "").trim();
    const iss = Number(body.iss_rate ?? 0);
    const mei = Boolean(body.mei);
    const simples = Boolean(body.simples_nacional) || mei;

    if (venue.document_kind === "cpf") {
      const { error } = await admin.from("venue_fiscal").upsert({
        venue_id: venueId,
        municipal_inscription: "",
        service_code: "",
        service_name: "",
        iss_rate: 0,
        simples_nacional: false,
        mei: false,
        cnae: "",
        emission: "sem_emissao",
        skip_reason: "cpf",
        updated_at: new Date().toISOString(),
      });
      if (error) return json({ error: error.message }, 400);
      return json({
        venue_id: venueId,
        emission: "sem_emissao",
        reason: "cpf",
        asaas: "nao_aplicavel",
      });
    }

    if (!inscription || !serviceCode || !(iss > 0) || iss > 100) {
      return json({
        error: "Informe inscrição municipal, código de serviço e alíquota de ISS.",
      }, 422);
    }

    const { error: saveError } = await admin.from("venue_fiscal").upsert({
      venue_id: venueId,
      municipal_inscription: inscription,
      service_code: serviceCode,
      service_name: serviceName,
      iss_rate: iss,
      simples_nacional: simples,
      mei,
      cnae: (body.cnae ?? "").trim(),
      emission: "habilitada",
      skip_reason: null,
      updated_at: new Date().toISOString(),
    });
    if (saveError) return json({ error: saveError.message }, 400);

    const { data: key } = await admin
      .from("venue_asaas_keys")
      .select("api_key")
      .eq("venue_id", venueId)
      .maybeSingle();
    if (!key?.api_key) {
      return json({
        venue_id: venueId,
        emission: "habilitada",
        asaas: "sem_chave",
      });
    }

    try {
      const asaas = AsaasProvider.fromEnv(Deno.env).withKey(key.api_key as string);
      await asaas.configureFiscalInfo({
        email,
        municipalInscription: inscription,
        simplesNacional: simples,
        cnae: (body.cnae ?? "").trim() || undefined,
        rpsSerie: body.rps_serie,
        rpsNumber: body.rps_number,
        serviceListItem: serviceCode,
        username: body.municipal_username,
        password: body.municipal_password,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "erro";
      return json({
        venue_id: venueId,
        emission: "habilitada",
        asaas: "erro",
        error: message,
      }, 502);
    }

    return json({
      venue_id: venueId,
      emission: "habilitada",
      asaas: "configured",
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "erro" }, 500);
  }
});
