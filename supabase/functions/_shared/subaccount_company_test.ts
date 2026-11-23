import { assert, assertEquals } from "jsr:@std/assert@1";
import { companyTypeForSubaccount } from "./subaccount_company.ts";

Deno.test("subconta manda o tipo da casa e omite companyType no CPF", () => {
  assertEquals(companyTypeForSubaccount("cnpj", "MEI"), "MEI");
  assertEquals(companyTypeForSubaccount("cnpj", "limited"), "LIMITED");
  assertEquals(companyTypeForSubaccount("cnpj", "INDIVIDUAL"), "INDIVIDUAL");
  assertEquals(companyTypeForSubaccount("cnpj", "ASSOCIATION"), "ASSOCIATION");
  assertEquals(companyTypeForSubaccount("cnpj", null), "LIMITED");
  assertEquals(companyTypeForSubaccount("cnpj", "LTDA"), "LIMITED");
  assertEquals(companyTypeForSubaccount("cpf", "MEI"), undefined);
  assertEquals(companyTypeForSubaccount("cpf", "LIMITED"), undefined);

  const cnpj = {
    name: "Casa",
    companyType: companyTypeForSubaccount("cnpj", "MEI"),
  };
  const cpf = {
    name: "Casa",
    companyType: companyTypeForSubaccount("cpf", "LIMITED"),
  };
  assertEquals(JSON.parse(JSON.stringify(cnpj)).companyType, "MEI");
  assertEquals(JSON.stringify(cpf).includes("companyType"), false);
});

Deno.test("provision-venue-wallet deriva o tipo e não fixa LIMITED", async () => {
  const source = await Deno.readTextFile(
    new URL("../provision-venue-wallet/index.ts", import.meta.url),
  );
  assert(source.includes("companyTypeForSubaccount"));
  assert(source.includes("company_type"));
  assertEquals(source.includes('"LIMITED" as const'), false);
  assertEquals(source.includes("console."), false);
});
