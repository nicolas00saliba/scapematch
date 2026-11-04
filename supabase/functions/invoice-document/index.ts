import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { corsHeaders, json } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") return json({ error: "method" }, 405);
  const authHeader = req.headers.get("Authorization") ?? "";
  const url = new URL(req.url);
  const id = url.searchParams.get("id") ?? "";
  const format = url.searchParams.get("format") === "xml" ? "xml" : "pdf";
  if (!id) return json({ error: "id obrigatório" }, 400);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const userClient = createClient(supabaseUrl, anon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await userClient.auth.getUser();
  if (!userData.user) return json({ error: "not authenticated" }, 401);

  const { data } = await userClient
    .from("fiscal_invoices")
    .select("id, status, number, pdf_url, xml_url, description, value_cents, kind")
    .eq("id", id)
    .maybeSingle();
  if (!data) return json({ error: "not found" }, 404);

  const stored = format === "xml" ? data.xml_url as string | null : data.pdf_url as string | null;
  if (stored && isRemoteAsaasFile(stored)) {
    return Response.redirect(stored, 302);
  }

  const number = (data.number as string | null) ?? data.id as string;
  const value = ((data.value_cents as number) / 100).toFixed(2);
  if (format === "xml") {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<nfse>
  <id>${escapeXml(data.id as string)}</id>
  <status>${escapeXml(data.status as string)}</status>
  <numero>${escapeXml(number)}</numero>
  <tipo>${escapeXml(data.kind as string)}</tipo>
  <valor>${value}</valor>
  <descricao>${escapeXml((data.description as string) ?? "")}</descricao>
</nfse>
`;
    return new Response(xml, {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/xml; charset=utf-8",
        "Content-Disposition": `attachment; filename="${number}.xml"`,
      },
    });
  }
  const pdf = simplePdf(`NFSe ${number} R$ ${value} ${data.status}`);
  return new Response(pdf, {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="${number}.pdf"`,
    },
  });
});

function isRemoteAsaasFile(url: string): boolean {
  if (!url.startsWith("https://")) return false;
  if (url.includes("/notas/teste/")) return false;
  return url.includes("asaas.com");
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function simplePdf(text: string): string {
  const safe = text.replace(/[^\x20-\x7E]/g, " ").replace(/[()\\]/g, " ");
  const stream = `BT /F1 12 Tf 48 740 Td (${safe}) Tj ET`;
  const objects = [
    "1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n",
    "2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n",
    "3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj\n",
    `4 0 obj<< /Length ${stream.length} >>stream\n${stream}\nendstream\nendobj\n`,
    "5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n",
  ];
  let body = "%PDF-1.4\n";
  const offsets = [0];
  for (const object of objects) {
    offsets.push(body.length);
    body += object;
  }
  const xref = body.length;
  body += `xref\n0 ${objects.length + 1}\n`;
  body += "0000000000 65535 f \n";
  for (let i = 1; i < offsets.length; i++) {
    body += `${String(offsets[i]).padStart(10, "0")} 00000 n \n`;
  }
  body += `trailer<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  body += `startxref\n${xref}\n%%EOF`;
  return body;
}
