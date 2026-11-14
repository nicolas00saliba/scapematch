// sameAs publica o Instagram oficial e o Meetup de quem não tem
// equipe para jogar escape room em Curitiba. TikTok e LinkedIn
// continuam de fora: o repositório não tem esses perfis.
// A nota de casa e de sala sai por aggregateRatingLd, e só com o mínimo.
// O app não leva aggregateRating nem review: não há avaliação publicada.
// O aplicativo é um PWA (navegador, Chrome no Android, Safari no iPhone).
// Não há ficha de loja neste repositório, então o tipo é WebApplication,
// subtipo de SoftwareApplication. MobileApplication não entra.

export { aggregateRatingLd } from './avaliacoes.ts';
export type { NotaPublica } from './avaliacoes.ts';

export const origem = 'https://escapematch.com.br';

export const idOrganizacao = `${origem}/#organization`;
export const idWebsite = `${origem}/#website`;
export const idAplicativo = 'https://app.escapematch.com.br/#app';

export const definicaoCurta =
  'EscapeMatch é um app de escape room em Curitiba que forma grupos para jogar com pessoas desconhecidas.';

export const definicao =
  `${definicaoCurta} Você chega sozinho, entra num grupo e paga só a sua vaga. Não é um modo de jogo de tiro nem um jogo de celular.`;

export const descricaoMarca =
  'App que forma grupos para jogar escape room em Curitiba com pessoas desconhecidas.';

export const tituloHome = 'EscapeMatch — app de escape room em Curitiba';

export const descricaoHome =
  'EscapeMatch — app de escape room em Curitiba que forma grupos para jogar com pessoas desconhecidas. Você chega sozinho e paga só a sua vaga.';

export const tituloSobre = 'Sobre a EscapeMatch — app de escape room em Curitiba';

export const descricaoSobre =
  'EscapeMatch — app de escape room em Curitiba que forma grupos para jogar com pessoas desconhecidas. Não é um modo de jogo de tiro.';

export const emailContato = 'contato@escapematch.com.br';

export const instagram = 'https://www.instagram.com/escapematch/';

export const meetup = 'https://www.meetup.com/pt-br/escaperoomcuritiba/';

export const nomesAlternativos = ['Escape Match', 'escapematch', 'ScapeMatch', 'Scape Match'];

function enderecoCuritiba() {
  return {
    '@type': 'PostalAddress',
    addressLocality: 'Curitiba',
    addressRegion: 'PR',
    addressCountry: 'BR',
  };
}

export const organizacao = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  '@id': idOrganizacao,
  name: 'EscapeMatch',
  legalName: 'ESCAPEMATCH TECNOLOGIA LTDA',
  taxID: '70.100.608/0001-73',
  alternateName: nomesAlternativos,
  url: `${origem}/`,
  // PNG quadrado de 512 px. O Google pede, no logo da Organization,
  // pelo menos 112 px, em formato que o Google Imagens rastreia, e
  // que continue legível em fundo branco. O SVG do símbolo fica no
  // cabeçalho; não entra neste campo.
  logo: `${origem}/assets/logo-512.png`,
  description: definicaoCurta,
  disambiguatingDescription:
    `${descricaoMarca} Não é um modo de jogo de tiro com nome parecido.`,
  email: emailContato,
  sameAs: [instagram, meetup],
  address: enderecoCuritiba(),
  foundingLocation: {
    '@type': 'Place',
    name: 'Curitiba',
    address: enderecoCuritiba(),
  },
  areaServed: {
    '@type': 'City',
    name: 'Curitiba',
    address: enderecoCuritiba(),
  },
};

export const website = {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  '@id': idWebsite,
  name: 'EscapeMatch',
  alternateName: nomesAlternativos,
  url: `${origem}/`,
  inLanguage: 'pt-BR',
  description: definicaoCurta,
  publisher: { '@id': idOrganizacao },
};

export const aplicativo = {
  '@context': 'https://schema.org',
  '@type': 'WebApplication',
  '@id': idAplicativo,
  name: 'EscapeMatch',
  alternateName: nomesAlternativos,
  url: 'https://app.escapematch.com.br/',
  applicationCategory: 'SocialNetworkingApplication',
  operatingSystem: 'Web, Android, iOS',
  inLanguage: 'pt-BR',
  description: definicao,
  offers: {
    '@type': 'Offer',
    price: 0,
    priceCurrency: 'BRL',
  },
  provider: { '@id': idOrganizacao },
  author: { '@id': idOrganizacao },
  publisher: { '@id': idOrganizacao },
};

export function idPagina(path: string): string {
  const canonical = path === '/' ? `${origem}/` : `${origem}${path}`;
  return `${canonical}#webpage`;
}

export function paginaLd(path: string, title: string, description: string) {
  const canonical = path === '/' ? `${origem}/` : `${origem}${path}`;
  const tipo = path === '/sobre' ? 'AboutPage' : path.startsWith('/guia/') ? 'Article' : 'WebPage';
  const no: Record<string, unknown> = {
    '@context': 'https://schema.org',
    '@type': tipo,
    '@id': idPagina(path),
    url: canonical,
    name: title,
    description,
    inLanguage: 'pt-BR',
    isPartOf: { '@id': idWebsite },
    about: { '@id': idOrganizacao },
    publisher: { '@id': idOrganizacao },
    author: { '@id': idOrganizacao },
  };
  if (tipo === 'Article' || tipo === 'AboutPage') {
    no.headline = title;
    no.mainEntityOfPage = canonical;
  }
  return no;
}

export function grafoDaPagina(entrada: {
  path: string;
  title: string;
  description: string;
  extra?: Record<string, unknown> | Record<string, unknown>[];
}) {
  const extra = entrada.extra
    ? (Array.isArray(entrada.extra) ? entrada.extra : [entrada.extra])
    : [];
  return [
    organizacao,
    website,
    aplicativo,
    paginaLd(entrada.path, entrada.title, entrada.description),
    ...extra,
  ];
}

export function faqPage(itens: { pergunta: string; resposta: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    author: { '@id': idOrganizacao },
    publisher: { '@id': idOrganizacao },
    mainEntity: itens.map((item) => ({
      '@type': 'Question',
      name: item.pergunta,
      acceptedAnswer: {
        '@type': 'Answer',
        text: item.resposta,
      },
    })),
  };
}
