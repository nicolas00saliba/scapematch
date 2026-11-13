import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  deliverClaimCode,
  maskEmail,
  maskPhone,
  officialContacts,
  publicClaimResult,
  sendClaimMail,
  sendClaimSms,
} from "./venue_claim.ts";

Deno.test("o contato oficial não é o que a pessoa digitou", () => {
  const contacts = officialContacts({
    official_email: "Casa@Ninja.example",
    official_phone: "(41) 91000-1992",
    email: "pessoa@digitou.example",
    phone: "41999990000",
  });
  assertEquals(contacts.email, "casa@ninja.example");
  assertEquals(contacts.phone, "41910001992");
});

Deno.test("sem contato oficial não há destino", () => {
  assertEquals(officialContacts({ phone: "41999990000" }), {
    email: null,
    phone: null,
  });
  assertEquals(officialContacts(null), { email: null, phone: null });
});

Deno.test("a resposta esconde o código e o contato inteiro", () => {
  const result = publicClaimResult({
    status: "otp",
    email: "oficial@ninja.example",
    phone: "41910001992",
  });
  assertEquals(result.status, "otp");
  assertEquals(result.channels, ["email", "phone"]);
  assertEquals(result.hint, "o***@ninja.example e final 92");
  assertEquals(maskEmail("oficial@ninja.example"), "o***@ninja.example");
  assertEquals(maskPhone("41910001992"), "final 92");
  assertEquals(JSON.stringify(result).includes("123456"), false);
  assertEquals(JSON.stringify(result).includes("oficial@"), false);
});

Deno.test("o envio usa o e-mail e o telefone do perfil", async () => {
  const mails: string[] = [];
  const phones: string[] = [];
  const sent = await deliverClaimCode(
    {
      code: "123456",
      venueName: "Ninja Escape Room",
      email: "oficial@ninja.example",
      phone: "41910001992",
    },
    {
      mail: (input) => {
        mails.push(input.to);
        assert(input.text.includes("123456"));
        assert(input.text.includes("Ninja Escape Room"));
        return Promise.resolve("sent");
      },
      sms: (input) => {
        phones.push(input.to);
        return Promise.resolve("sent");
      },
    },
  );
  assertEquals(sent, "sent");
  assertEquals(mails, ["oficial@ninja.example"]);
  assertEquals(phones, ["41910001992"]);
});

Deno.test("sem provedor o código não conta como enviado", async () => {
  const sent = await deliverClaimCode(
    {
      code: "123456",
      venueName: "Ninja Escape Room",
      email: "oficial@ninja.example",
      phone: null,
    },
    {
      mail: () => Promise.resolve("unconfigured"),
      sms: () => Promise.resolve("sent"),
    },
  );
  assertEquals(sent, "unconfigured");
});

Deno.test("o e-mail só sai com a chave e o remetente", async () => {
  const calls: string[] = [];
  const idle = await sendClaimMail(
    { get: () => undefined },
    () => {
      throw new Error("não devia chamar");
    },
    { to: "oficial@ninja.example", subject: "s", text: "t" },
  );
  assertEquals(idle, "unconfigured");
  const sent = await sendClaimMail(
    {
      get: (name) =>
        name === "RESEND_API_KEY"
          ? "re_test"
          : name === "PAYOUT_MAIL_FROM"
          ? "EscapeMatch <oi@escapematch.com.br>"
          : undefined,
    },
    (url) => {
      calls.push(String(url));
      return Promise.resolve(new Response("ok", { status: 202 }));
    },
    { to: "oficial@ninja.example", subject: "s", text: "código" },
  );
  assertEquals(sent, "sent");
  assertEquals(calls, ["https://api.resend.com/emails"]);
});

Deno.test("o SMS só sai para um https configurado", async () => {
  const idle = await sendClaimSms(
    { get: () => undefined },
    () => {
      throw new Error("não devia chamar");
    },
    { to: "41910001992", text: "código" },
  );
  assertEquals(idle, "unconfigured");
  const http = await sendClaimSms(
    {
      get: (name) =>
        name === "VENUE_CLAIM_SMS_URL"
          ? "http://sms.example/send"
          : "token",
    },
    () => {
      throw new Error("http não entra");
    },
    { to: "41910001992", text: "código" },
  );
  assertEquals(http, "unconfigured");
});

Deno.test("a função exige JWT e não devolve o código", async () => {
  const source = await Deno.readTextFile(
    new URL("../venue-claim/index.ts", import.meta.url),
  );
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  const block = config.split("[functions.venue-claim]")[1]?.split("\n[")[0] ??
    "";
  assert(block.includes("verify_jwt = true"));
  assert(source.includes("publicClaimResult"));
  assert(source.includes("getUser"));
  assertEquals(source.includes("body.email"), false);
  assertEquals(source.includes("body.phone"), false);
  assertEquals(source.includes("AsaasProvider"), false);
  assertEquals(source.includes("ASAAS_"), false);
  assertEquals(source.includes("asaas_provider"), false);
});
