// Código de posse da casa. O destino é o contato já gravado no perfil.
// O que a pessoa digitou no cadastro não entra aqui.

export type OfficialContacts = {
  email: string | null;
  phone: string | null;
};

export type ClaimDispatch = {
  status: "otp" | "manual" | "rate" | "already_owner" | "already_claimed" | "not_found";
  channels: Array<"email" | "phone">;
  hint: string;
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function officialContacts(
  venue: Record<string, unknown> | null,
): OfficialContacts {
  const email = text(venue?.official_email).toLowerCase();
  const phone = text(venue?.official_phone).replace(/\D/g, "");
  return {
    email: emailPattern.test(email) ? email : null,
    phone: /^[0-9]{10,13}$/.test(phone) ? phone : null,
  };
}

export function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  return `${local.slice(0, 1)}***@${domain}`;
}

export function maskPhone(phone: string): string {
  return `final ${phone.slice(-2)}`;
}

/// A resposta HTTP não leva o código, o e-mail inteiro nem o telefone.
export function publicClaimResult(input: {
  status: string;
  email?: string | null;
  phone?: string | null;
}): ClaimDispatch {
  const channels: Array<"email" | "phone"> = [];
  const hints: string[] = [];
  if (input.status === "otp") {
    if (input.email) {
      channels.push("email");
      hints.push(maskEmail(input.email));
    }
    if (input.phone) {
      channels.push("phone");
      hints.push(maskPhone(input.phone));
    }
  }
  return {
    status: normalizeStatus(input.status),
    channels,
    hint: hints.join(" e "),
  };
}

function normalizeStatus(status: string): ClaimDispatch["status"] {
  if (
    status === "otp" ||
    status === "manual" ||
    status === "rate" ||
    status === "already_owner" ||
    status === "already_claimed" ||
    status === "not_found"
  ) {
    return status;
  }
  return "not_found";
}

export function claimMessage(code: string, venueName: string): string {
  return `Código para reivindicar ${venueName} no EscapeMatch: ${code}. Ele vale por 10 minutos.`;
}

export type MailSender = (input: {
  to: string;
  subject: string;
  text: string;
}) => Promise<"sent" | "unconfigured" | "failed">;

export type SmsSender = (input: {
  to: string;
  text: string;
}) => Promise<"sent" | "unconfigured" | "failed">;

export async function deliverClaimCode(
  input: { code: string; venueName: string; email: string | null; phone: string | null },
  senders: { mail: MailSender; sms: SmsSender },
): Promise<"sent" | "unconfigured"> {
  let sent = false;
  let tried = false;
  if (input.email) {
    tried = true;
    const result = await senders.mail({
      to: input.email,
      subject: "Código para reivindicar sua casa no EscapeMatch",
      text: claimMessage(input.code, input.venueName),
    });
    if (result === "sent") sent = true;
  }
  if (input.phone) {
    tried = true;
    const result = await senders.sms({
      to: input.phone,
      text: claimMessage(input.code, input.venueName),
    });
    if (result === "sent") sent = true;
  }
  if (!tried) return "unconfigured";
  return sent ? "sent" : "unconfigured";
}

export async function sendClaimMail(
  env: { get(name: string): string | undefined },
  fetchFn: typeof fetch,
  input: { to: string; subject: string; text: string },
): Promise<"sent" | "unconfigured" | "failed"> {
  const key = env.get("RESEND_API_KEY") ?? "";
  const from = env.get("CLAIM_MAIL_FROM") ?? env.get("PAYOUT_MAIL_FROM") ?? "";
  if (!key || !from || !input.to.includes("@")) return "unconfigured";
  const response = await fetchFn("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [input.to],
      subject: input.subject,
      text: input.text,
    }),
  });
  return response.ok ? "sent" : "failed";
}

export async function sendClaimSms(
  env: { get(name: string): string | undefined },
  fetchFn: typeof fetch,
  input: { to: string; text: string },
): Promise<"sent" | "unconfigured" | "failed"> {
  const url = env.get("VENUE_CLAIM_SMS_URL") ?? "";
  const token = env.get("VENUE_CLAIM_SMS_TOKEN") ?? "";
  if (!url.startsWith("https://") || !token || !input.to) return "unconfigured";
  const response = await fetchFn(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ to: input.to, text: input.text }),
  });
  return response.ok ? "sent" : "failed";
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}
