export type Link = {
  rotulo: string;
  href: string;
  externo?: boolean;
};

export type Coluna = {
  titulo: string;
  links: Link[];
};

export const jogarLinks: Link[] = [
  { rotulo: 'Escape room sozinho', href: '/guia/escape-room-sozinho' },
  { rotulo: 'Escape room em Curitiba', href: '/escape-room-curitiba' },
  { rotulo: 'Como funciona', href: '/como-funciona' },
  { rotulo: 'Pagamento e regras', href: '/como-funciona/pagamento' },
  { rotulo: 'Experiências', href: '/experiencias' },
  { rotulo: 'Segurança', href: '/seguranca' },
];

export const vantagensLinks: Link[] = [
  { rotulo: 'Boas-vindas e pontos de volta', href: '/vantagens' },
  { rotulo: 'Indique amigos', href: '/vantagens/indique-amigos' },
  { rotulo: 'Indique uma casa', href: '/vantagens/indique-uma-casa' },
  { rotulo: 'Níveis', href: '/vantagens/niveis' },
  { rotulo: 'Passaporte de salas', href: '/vantagens/passaporte' },
  { rotulo: 'Avalie a sala', href: '/vantagens/avaliacoes' },
  { rotulo: 'Regulamento', href: '/vantagens/regulamento' },
];

export const casaNovaLinks: Link[] = [
  { rotulo: 'Por que entrar', href: '/para-casas' },
  { rotulo: 'Como funciona', href: '/para-casas/como-funciona' },
  { rotulo: 'Preços', href: '/para-casas/precos' },
  { rotulo: 'Cadastro', href: '/para-casas/cadastro' },
];

export const casaParceiraLinks: Link[] = [
  { rotulo: 'Entrar no Parceiro', href: 'https://parceiro.escapematch.com.br/', externo: true },
  { rotulo: 'Indique uma casa', href: '/para-casas/indique-uma-casa' },
  { rotulo: 'Indique jogadores', href: '/para-casas/indique-jogadores' },
  { rotulo: 'Horário vazio', href: '/para-casas/horario-vazio' },
  { rotulo: 'Avaliações e insights', href: '/para-casas/avaliacoes' },
  { rotulo: 'Mimos do passaporte', href: '/para-casas/mimos' },
  { rotulo: 'Passaporte de salas', href: '/para-casas/passaporte' },
];

export const empresaLinks: Link[] = [
  { rotulo: 'Sobre', href: '/sobre' },
  { rotulo: 'Contato', href: '/contato' },
];

export const rodape: Coluna[] = [
  {
    titulo: 'Quero jogar',
    links: [
      { rotulo: 'Escape room sozinho', href: '/guia/escape-room-sozinho' },
      { rotulo: 'Escape room em Curitiba', href: '/escape-room-curitiba' },
      { rotulo: 'Como funciona', href: '/como-funciona' },
      { rotulo: 'Pagamento e regras', href: '/como-funciona/pagamento' },
      { rotulo: 'Experiências', href: '/experiencias' },
      { rotulo: 'Segurança', href: '/seguranca' },
      { rotulo: 'Baixar o app', href: '/app' },
    ],
  },
  {
    titulo: 'Já jogo com a gente',
    links: [
      { rotulo: 'Entrar', href: 'https://app.escapematch.com.br/login', externo: true },
      { rotulo: 'Vantagens', href: '/vantagens' },
      { rotulo: 'Indique amigos', href: '/vantagens/indique-amigos' },
      { rotulo: 'Indique uma casa', href: '/vantagens/indique-uma-casa' },
      { rotulo: 'Níveis', href: '/vantagens/niveis' },
      { rotulo: 'Passaporte de salas', href: '/vantagens/passaporte' },
      { rotulo: 'Avalie a sala', href: '/vantagens/avaliacoes' },
      { rotulo: 'Regulamento dos pontos', href: '/vantagens/regulamento' },
    ],
  },
  {
    titulo: 'Tenho uma casa',
    links: [
      { rotulo: 'Seja parceiro', href: '/para-casas/cadastro' },
      { rotulo: 'Preços', href: '/para-casas/precos' },
      { rotulo: 'Entrar no Parceiro', href: 'https://parceiro.escapematch.com.br/', externo: true },
      { rotulo: 'Indique uma casa', href: '/para-casas/indique-uma-casa' },
      { rotulo: 'Indique jogadores', href: '/para-casas/indique-jogadores' },
      { rotulo: 'Horário vazio', href: '/para-casas/horario-vazio' },
      { rotulo: 'Avaliações e insights', href: '/para-casas/avaliacoes' },
      { rotulo: 'Mimos do passaporte', href: '/para-casas/mimos' },
      { rotulo: 'Passaporte de salas', href: '/para-casas/passaporte' },
    ],
  },
  {
    titulo: 'Ajuda e empresa',
    links: [
      { rotulo: 'Central de ajuda', href: '/ajuda' },
      { rotulo: 'Sobre', href: '/sobre' },
      { rotulo: 'Contato', href: '/contato' },
    ],
  },
  {
    titulo: 'Legal',
    links: [
      { rotulo: 'Termos de uso', href: '/termos' },
      { rotulo: 'Termos do Parceiro', href: '/termos/parceiro' },
      { rotulo: 'Privacidade e LGPD', href: '/privacidade' },
      { rotulo: 'Regras de cancelamento', href: '/cancelamento' },
      { rotulo: 'Mapa do site', href: '/mapa-do-site' },
    ],
  },
];

const nomes: Record<string, string> = {
  '/guia/escape-room-sozinho': 'Escape room sozinho',
  '/escape-room-curitiba': 'Escape room em Curitiba',
  '/como-funciona': 'Como funciona',
  '/como-funciona/pagamento': 'Pagamento e regras',
  '/experiencias': 'Experiências',
  '/experiencias/escape-room': 'Escape room',
  '/cidades/curitiba': 'Curitiba',
  '/seguranca': 'Segurança',
  '/app': 'Baixar o app',
  '/vantagens': 'Vantagens',
  '/vantagens/indique-amigos': 'Indique amigos',
  '/vantagens/indique-uma-casa': 'Indique uma casa',
  '/vantagens/niveis': 'Níveis',
  '/vantagens/passaporte': 'Passaporte de salas',
  '/vantagens/avaliacoes': 'Avalie a sala',
  '/vantagens/regulamento': 'Regulamento dos pontos',
  '/para-casas': 'Para casas',
  '/para-casas/como-funciona': 'Como funciona',
  '/para-casas/precos': 'Preços',
  '/para-casas/cadastro': 'Cadastro',
  '/para-casas/parceiros': 'Área do parceiro',
  '/para-casas/indique-uma-casa': 'Indique uma casa',
  '/para-casas/indique-jogadores': 'Indique jogadores',
  '/para-casas/horario-vazio': 'Horário vazio',
  '/para-casas/avaliacoes': 'Avaliações e insights',
  '/para-casas/mimos': 'Mimos do passaporte',
  '/para-casas/passaporte': 'Passaporte de salas',
  '/ajuda': 'Ajuda',
  '/ajuda/grupo': 'Grupo',
  '/ajuda/pagamento': 'Pagamento',
  '/ajuda/cancelamento': 'Cancelamento',
  '/ajuda/conta': 'Conta',
  '/ajuda/pontos': 'Pontos',
  '/ajuda/casas': 'Casas',
  '/sobre': 'Sobre',
  '/contato': 'Contato',
  '/termos': 'Termos de uso',
  '/termos/parceiro': 'Termos do Parceiro',
  '/privacidade': 'Privacidade e LGPD',
  '/cancelamento': 'Regras de cancelamento',
  '/mapa-do-site': 'Mapa do site',
};

export type Migalha = { nome: string; href: string };

export function trilha(path: string): Migalha[] {
  const limpo = path.replace(/\/$/, '') || '/';
  if (limpo === '/') return [{ nome: 'Início', href: '/' }];
  const partes = limpo.split('/').filter(Boolean);
  const itens: Migalha[] = [{ nome: 'Início', href: '/' }];
  let acc = '';
  for (const parte of partes) {
    acc += `/${parte}`;
    if (nomes[acc]) itens.push({ nome: nomes[acc], href: acc });
  }
  return itens;
}

export function semTrilha(path: string): boolean {
  const limpo = path.replace(/\/$/, '') || '/';
  return limpo === '/' || limpo === '/convite' || limpo === '/404';
}
