/// HTTPS em pagbank.com (ou subdomínio). O PDF de teste do sandbox não redireciona.
export function isRemoteInvoiceFile(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== "https:") return false;
  const host = parsed.hostname;
  const pagbank = host === "pagbank.com" || host.endsWith(".pagbank.com");
  const pagseguro = host === "pagseguro.com" || host.endsWith(".pagseguro.com");
  if (!pagbank && !pagseguro) return false;
  return !parsed.pathname.includes("/notas/teste/");
}
