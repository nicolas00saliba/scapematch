// Tokens de Google Search Console e Bing Webmaster.
// Vazios no repositório. O build só publica o que passar daqui.
//
// GOOGLE_SITE_VERIFICATION
//   conteúdo da meta name="google-site-verification"
// BING_SITE_VERIFICATION
//   conteúdo da meta name="msvalidate.01" e, se válido, de BingSiteAuth.xml
// GOOGLE_SITE_VERIFICATION_FILE
//   nome do arquivo HTML que o Google entrega, por exemplo
//   googleAbcdEfgh12345678.html
//   O build grava na raiz do site a linha
//   google-site-verification: <nome do arquivo>

const BLOQUEADO =
  /(example|exemplo|changeme|placeholder|fake|teste|sample|your[-_]?token)/i;

export function tokenBuscador(valor) {
  if (typeof valor !== 'string') return null;
  const limpo = valor.trim();
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(limpo)) return null;
  if (BLOQUEADO.test(limpo)) return null;
  if (/^(todo|test|x+)$/i.test(limpo)) return null;
  if (/^(.)\1+$/.test(limpo)) return null;
  return limpo;
}

export function arquivoGoogle(valor) {
  if (typeof valor !== 'string') return null;
  const limpo = valor.trim();
  if (!/^google[A-Za-z0-9]{16,}\.html$/.test(limpo)) return null;
  if (/(example|exemplo|placeholder|changeme|fake)/i.test(limpo)) return null;
  return limpo;
}

export function linhaArquivoGoogle(nome) {
  return `google-site-verification: ${nome}\n`;
}

export function xmlBing(token) {
  return `<?xml version="1.0"?>\n<users>\n  <user>${token}</user>\n</users>\n`;
}
