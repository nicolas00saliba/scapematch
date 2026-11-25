// Datas reais de cada URL do sitemap, fixas no código para o build
// não depender do histórico do git (o checkout da CI é raso).
// A data é o último commit da página. Quando o texto visível mora num
// arquivo de dados mais novo, vale a data mais nova. A página deste
// guia usa a data da alteração, a mesma do Article.

export const publicadoGuiaSemNinguem = '2026-11-13T00:00:00-03:00';
export const modificadoGuiaSemNinguem = '2026-11-20T00:00:00-03:00';

export const publicadoGuiaComoJogarSozinho = '2026-11-20T00:00:00-03:00';
export const modificadoGuiaComoJogarSozinho = '2026-11-20T00:00:00-03:00';

export const publicadoOQueE = '2026-11-25T00:00:00-03:00';
export const modificadoOQueE = '2026-11-25T00:00:00-03:00';

const ajuda = '2026-11-13T09:32:15-03:00';
const programas = '2026-11-11T15:10:53-03:00';

export const lastmodPorRota = {
  '/': modificadoGuiaComoJogarSozinho,
  '/como-funciona': modificadoGuiaComoJogarSozinho,
  '/como-funciona/pagamento': '2026-11-24T12:00:00-03:00',
  '/experiencias': modificadoGuiaComoJogarSozinho,
  '/experiencias/escape-room': modificadoGuiaComoJogarSozinho,
  '/o-que-e-escape-room': modificadoOQueE,
  '/guia': modificadoGuiaComoJogarSozinho,
  '/guia/como-jogar-escape-room-sozinho': modificadoGuiaComoJogarSozinho,
  '/guia/escape-room-sozinho': modificadoGuiaComoJogarSozinho,
  '/guia/escape-room-sozinho-curitiba': modificadoGuiaComoJogarSozinho,
  '/guia/como-achar-grupo-escape-room': modificadoGuiaComoJogarSozinho,
  '/guia/escape-room-com-desconhecidos': modificadoGuiaComoJogarSozinho,
  '/guia/escape-room-para-2-pessoas': modificadoGuiaComoJogarSozinho,
  '/guia/nao-tenho-amigos-para-escape-room': modificadoGuiaSemNinguem,
  '/guia/escape-room-em-grupo-curitiba': modificadoGuiaComoJogarSozinho,
  '/guia/primeira-vez-em-escape-room': modificadoGuiaComoJogarSozinho,
  '/escape-room-curitiba': modificadoGuiaComoJogarSozinho,
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
  '/ajuda': modificadoGuiaComoJogarSozinho,
  '/ajuda/grupo': ajuda,
  '/ajuda/pagamento': ajuda,
  '/ajuda/cancelamento': '2026-11-24T12:00:00-03:00',
  '/ajuda/conta': ajuda,
  '/ajuda/pontos': ajuda,
  '/ajuda/casas': ajuda,
  '/sobre': modificadoGuiaComoJogarSozinho,
  '/contato': '2026-11-14T08:31:48-03:00',
  '/termos': '2026-11-24T12:00:00-03:00',
  '/termos/parceiro': '2026-11-24T12:00:00-03:00',
  '/privacidade': '2026-11-12T16:10:13-03:00',
  '/cancelamento': '2026-11-24T12:00:00-03:00',
  '/mapa-do-site': '2026-11-11T13:26:32-03:00',
};

export function lastmodDaRota(rota) {
  const iso = lastmodPorRota[rota];
  if (!iso) throw new Error(`sitemap sem lastmod para ${rota}`);
  return new Date(iso);
}
