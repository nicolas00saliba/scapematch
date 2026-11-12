// Adaptador do service role. Os testes não importam este arquivo.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import type { PayoutStore } from "./venue_payouts.ts";

export function payoutStore(
  env: { get(name: string): string | undefined },
): PayoutStore {
  const url = env.get("SUPABASE_URL") ?? "";
  const anon = env.get("SUPABASE_ANON_KEY") ?? "";
  const service = env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service);
  return {
    async actor(jwt) {
      if (!jwt) return null;
      const userClient = createClient(url, anon, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      const { data, error } = await userClient.auth.getUser();
      if (error || !data.user) return null;
      return { id: data.user.id, email: data.user.email ?? "" };
    },
    async verifiedTotp(userId) {
      const response = await fetch(
        `${url}/auth/v1/admin/users/${userId}/factors`,
        {
          headers: {
            apikey: service,
            authorization: `Bearer ${service}`,
          },
        },
      );
      if (!response.ok) return false;
      const body = await response.json().catch(() => null) as
        | { factors?: { factor_type?: string; status?: string }[] }
        | { factor_type?: string; status?: string }[]
        | null;
      const factors = Array.isArray(body)
        ? body
        : Array.isArray(body?.factors)
        ? body.factors
        : [];
      return factors.some((item) =>
        item.factor_type === "totp" && item.status === "verified"
      );
    },
    async isAdmin(userId) {
      const { data } = await admin
        .from("admins")
        .select("user_id")
        .eq("user_id", userId)
        .maybeSingle();
      return Boolean(data);
    },
    async rpc(fn, args) {
      const { data, error } = await admin.rpc(fn, args);
      if (error) throw new Error(error.message);
      return data;
    },
    async ownerEmail(userId) {
      const { data, error } = await admin.auth.admin.getUserById(userId);
      if (error || !data.user?.email) return "";
      return data.user.email;
    },
  };
}
