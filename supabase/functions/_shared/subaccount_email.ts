import {
  asaasStatus,
  isDuplicateSubaccountEmail,
} from "./asaas_client_error.ts";

/// Domínio do alias quando `ASAAS_SUBACCOUNT_EMAIL_DOMAIN` não está definida
/// ou não é um domínio. É um domínio nosso. O fallback avisa no log.
export const fallbackSubaccountDomain = "escapematch.com.br";

const domainPattern =
  /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

/// `venues` e `venue_fiscal` não têm e-mail hoje. Se a linha trouxer uma
/// destas colunas, ela é o e-mail da subconta.
const venueEmailKeys = ["contact_email", "fiscal_email", "email"] as const;

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export type SubaccountEmailPlan = {
  primary: string;
  alias: string;
};

function warnEmailDomainFallback(
  code: "missing_email_domain" | "invalid_email_domain",
): void {
  console.warn(
    JSON.stringify({
      scope: "subaccount_email",
      code,
      fallback: fallbackSubaccountDomain,
    }),
  );
}

export function subaccountEmailDomain(
  env: { get(name: string): string | undefined },
): string {
  const raw = (env.get("ASAAS_SUBACCOUNT_EMAIL_DOMAIN") ?? "").trim()
    .toLowerCase();
  if (!raw) {
    warnEmailDomainFallback("missing_email_domain");
    return fallbackSubaccountDomain;
  }
  if (!domainPattern.test(raw)) {
    warnEmailDomainFallback("invalid_email_domain");
    return fallbackSubaccountDomain;
  }
  return raw;
}

/// `parceiros+<venue_id>@domínio`. O id entra inteiro: um prefixo curto colide.
export function venueAliasEmail(venueId: string, domain: string): string {
  const id = venueId.trim().toLowerCase().replace(/[^a-z0-9-]/g, "");
  if (!id) throw new Error("venue id ausente");
  return `parceiros+${id}@${domain}`;
}

export function venueContactEmail(
  venue: Record<string, unknown>,
): string | null {
  for (const key of venueEmailKeys) {
    const value = venue[key];
    if (typeof value !== "string") continue;
    const email = value.trim().toLowerCase();
    if (emailPattern.test(email)) return email;
  }
  return null;
}

/// E-mail da casa, se existir. Sem isso, o alias determinístico — não o login.
export type VenueEmailSource = {
  id: string;
  contact_email?: unknown;
  fiscal_email?: unknown;
  email?: unknown;
};

export function subaccountEmailPlan(
  venue: VenueEmailSource,
  env: { get(name: string): string | undefined },
): SubaccountEmailPlan {
  const domain = subaccountEmailDomain(env);
  const alias = venueAliasEmail(venue.id, domain);
  const own = venueContactEmail(venue as Record<string, unknown>);
  return { primary: own ?? alias, alias };
}

/// Segunda tentativa só quando o Asaas recusa o e-mail por já existir.
export function nextSubaccountEmail(
  current: string,
  alias: string,
  error: unknown,
): string | null {
  if (current === alias) return null;
  if (asaasStatus(error) !== 400) return null;
  if (!isDuplicateSubaccountEmail(error)) return null;
  return alias;
}
