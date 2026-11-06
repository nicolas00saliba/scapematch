/// HTTPS em asaas.com (ou subdomínio). O PDF de teste do sandbox não redireciona.
export function isRemoteAsaasFile(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  if (parsed.protocol !== "https:") return false;
  const host = parsed.hostname;
  if (host !== "asaas.com" && !host.endsWith(".asaas.com")) return false;
  return !parsed.pathname.includes("/notas/teste/");
}
