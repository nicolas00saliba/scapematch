// Datas reais de cada URL do sitemap, fixas no código para o build
// não depender do histórico do git (o checkout da CI é raso).
// A data é o último commit da página. Quando o texto visível mora num
// arquivo de dados mais novo, vale a data mais nova. A página deste
// guia usa a data da alteração, a mesma do Article.

export const publicadoGuiaSemNinguem = '2026-11-13T00:00:00-03:00';
export const modificadoGuiaSemNinguem = '2026-11-15T00:00:00-03:00';

const ajuda = '2026-11-13T09:32:15-03:00';
const programas = '2026-11-11T15:10:53-03:00';

export const lastmodPorRota = {
  '/': '2026-11-15T08:29:50-03:00',
  '/como-funciona': '2026-11-14T08:31:48-03:00',
  '/como-funciona/pagamento': '2026-11-11T13:26:32-03:00',
  '/experiencias': '2026-11-13T12:25:02-03:00',
  '/experiencias/escape-room': '2026-11-13T12:25:02-03:00',
  '/guia': '2026-11-15T08:29:50-03:00',
  '/guia/escape-room-sozinho': '2026-11-15T08:29:50-03:00',
  '/guia/escape-room-sozinho-curitiba': '2026-11-13T14:55:48-03:00',
  '/guia/como-achar-grupo-escape-room': '2026-11-15T08:29:50-03:00',
  '/guia/escape-room-com-desconhecidos': '2026-11-13T14:55:48-03:00',
  '/guia/escape-room-para-2-pessoas': '2026-11-13T14:55:48-03:00',
  '/guia/nao-tenho-amigos-para-escape-room': modificadoGuiaSemNinguem,
  '/guia/escape-room-em-grupo-curitiba': '2026-11-13T14:55:48-03:00',
  '/guia/primeira-vez-em-escape-room': '2026-11-13T14:55:48-03:00',
  '/escape-room-curitiba': '2026-11-14T08:31:48-03:00',
  '/seguranca': '2026-11-11T13:26:32-03:00',
  '/app': '2026-11-14T08:31:48-03:00',
  '/vantagens': programas,
  '/vantagens/indique-amigos': '2026-11-11T13:26:32-03:00',
  '/vantagens/indique-uma-casa': '2026-11-11T13:26:32-03:00',
  '/vantagens/niveis': programas,
  '/vantagens/regulamento': programas,
  '/para-casas': programas,
  '/para-casas/como-funciona': '2026-11-11T13:26:32-03:00',
  '/para-casas/precos': programas,
  '/para-casas/cadastro': '2026-11-11T13:26:32-03:00',
  '/para-casas/parceiros': programas,
  '/para-casas/indique-uma-casa': '2026-11-11T13:26:32-03:00',
  '/para-casas/indique-jogadores': '2026-11-11T13:26:32-03:00',
  '/para-casas/horario-vazio': '2026-11-11T13:26:32-03:00',
  '/ajuda': '2026-11-15T08:29:50-03:00',
  '/ajuda/grupo': ajuda,
  '/ajuda/pagamento': ajuda,
  '/ajuda/cancelamento': ajuda,
  '/ajuda/conta': ajuda,
  '/ajuda/pontos': ajuda,
  '/ajuda/casas': ajuda,
  '/sobre': '2026-11-15T08:29:50-03:00',
  '/contato': '2026-11-14T08:31:48-03:00',
  '/termos': '2026-11-11T13:26:32-03:00',
  '/termos/parceiro': '2026-11-11T13:26:32-03:00',
  '/privacidade': '2026-11-12T16:10:13-03:00',
  '/cancelamento': '2026-11-11T13:26:32-03:00',
  '/mapa-do-site': '2026-11-11T13:26:32-03:00',
};

export function lastmodDaRota(rota) {
  const iso = lastmodPorRota[rota];
  if (!iso) throw new Error(`sitemap sem lastmod para ${rota}`);
  return new Date(iso);
}
