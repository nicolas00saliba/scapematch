// Desconecta a conta PagBank da casa. É o único caminho para trocar de conta:
// desconectar e conectar de novo. A conta e o token ficam no servidor, presos
// à casa. Dono (com confirmação na tela) ou Admin com MFA; recusa com 409 se
// houver dinheiro a caminho. A resposta leva só os 4 últimos caracteres.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { clientFailure, logCaught } from "../_shared/pagbank_client_error.ts";
import { bindJson, corsHeadersFor } from "../_shared/http.ts";
import { adminWithMfa } from "../_shared/admin_session.ts";
import { PagBankProvider } from "../_shared/pagbank_provider.ts";
import { revokeConnectTokens } from "../_shared/pagbank_revoke.ts";
import {
  conflictBody,
  conflictFromRpc,
  ownerMayDisconnect,
  shouldRevokeAfterDisconnect,
} from "../_shared/pagbank_binding.ts";

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
    const admin = createClient(url, service);
    const { data: adminLookup } = await admin
      .from("admins")
      .select("user_id")
      .eq("user_id", userData.user.id)
      .maybeSingle();
    const isAdmin = adminWithMfa(Boolean(adminLookup), authHeader);
    const body = await req.json().catch(() => ({})) as { venue_id?: string };
    const venueId = (body.venue_id ?? "").trim();
    if (!venueId) return json({ error: "venue_id" }, 400);
    if (!isAdmin && !ownerMayDisconnect) {
      return json({ error: "not admin" }, 403);
    }
    // Lê o token antes de a casa soltar a conta, só para revogar no PagBank
    // depois. Quem não é dono nem Admin não chega aqui com token na mão.
    let tokens: { accessToken: string; refreshToken: string } | null = null;
    try {
      let allowed = Boolean(isAdmin);
      if (!allowed) {
        const { data: venue } = await admin
          .from("venues")
          .select("owner_id")
          .eq("id", venueId)
          .maybeSingle();
        allowed = venue?.owner_id === userData.user.id;
      }
      if (allowed) {
        const { data: read } = await admin.rpc("read_venue_pagbank_tokens", {
          p_venue_id: venueId,
        });
        const row = (Array.isArray(read) ? read[0] : read) as
          | { access_token?: string; refresh_token?: string }
          | null
          | undefined;
        const accessToken = (row?.access_token ?? "").trim();
        if (accessToken) {
          tokens = {
            accessToken,
            refreshToken: (row?.refresh_token ?? "").trim(),
          };
        }
      }
    } catch (_readError) {
      tokens = null;
    }
    const { data, error } = await admin.rpc("disconnect_venue_pagbank", {
      p_venue_id: venueId,
      p_actor: userData.user.id,
      p_admin: Boolean(isAdmin),
    });
    if (error) {
      const conflict = conflictFromRpc(error);
      if (conflict) return json(conflictBody(conflict), 409);
      if ((error.message ?? "").includes("not owner")) {
        return json({ error: "not owner" }, 403);
      }
      throw new Error("erro");
    }
    const row = (data ?? {}) as { disconnected?: boolean; shared?: boolean };
    // Cidade que usava a conta de outra: o token é da outra cidade e continua
    // valendo lá. Revogar derrubaria o recebimento da outra.
    if (shouldRevokeAfterDisconnect(row) && tokens) {
      await revokeAtPagbank(tokens);
    }
    return json({ disconnected: row.disconnected === true });
  } catch (error) {
    logCaught("pagbank-disconnect", error);
    const failure = clientFailure(error, "pagbank-disconnect");
    return json(failure.body, failure.status);
  }
});

/// Melhor esforço: a casa já está desconectada no servidor. Se o PagBank
/// recusar ou cair, só registra o código; o dono ainda pode revogar o acesso
/// no app do PagBank.
async function revokeAtPagbank(
  tokens: { accessToken: string; refreshToken: string },
): Promise<void> {
  try {
    const clientId = (Deno.env.get("PAGBANK_CONNECT_CLIENT_ID") ?? "").trim();
    const clientSecret = (Deno.env.get("PAGBANK_CONNECT_CLIENT_SECRET") ?? "")
      .trim();
    if (!clientId || !clientSecret) return;
    const provider = PagBankProvider.fromEnv(Deno.env);
    const result = await revokeConnectTokens(
      (call) =>
        provider.revokeConnectToken({ clientId, clientSecret, ...call }),
      tokens,
    );
    if (result.failed > 0) {
      console.warn(
        `pagbank-disconnect: revogacao falhou em ${result.failed} de ${result.attempted}`,
      );
    }
  } catch (_error) {
    console.warn("pagbank-disconnect: revogacao indisponivel");
  }
}
