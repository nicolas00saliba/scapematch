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
  'EscapeMatch é o app para achar grupo e jogar escape room sozinho no Brasil.';

export const primeirasCasas =
  'O app está começando com as primeiras casas e vai crescer.';

export const definicao =
  `${definicaoCurta} Você chega sozinho, entra num grupo e paga só a sua vaga. Não é um modo de jogo de tiro nem um jogo de celular.`;

export const jogosParecidos =
  'Room Escape Match 6, Escape Match Room Tiles e Bubble Escape Match 3D';

// Frase que separa a marca dos jogos de celular da Google Play com nome
// parecido. A visão geral do Google misturava os dois em 16/11/2026.
export const frasePlayStore =
  `Jogos de celular da Google Play com nome parecido, como ${jogosParecidos}, são de outras empresas e não têm relação com a EscapeMatch.`;

export const descricaoMarca =
  'App para achar grupo e jogar escape room sozinho no Brasil.';

export const tituloHome = 'EscapeMatch — app para jogar escape room sozinho no Brasil';

export const descricaoHome =
  'EscapeMatch — app para jogar escape room sozinho no Brasil. Você chega sozinho, entra num grupo e paga só a sua vaga.';

export const tituloSobre = 'Sobre a EscapeMatch — escape room no Brasil';

export const descricaoSobre =
  'EscapeMatch — app para jogar escape room sozinho no Brasil. Não é jogo de celular nem modo de jogo de tiro.';

export const emailContato = 'contato@escapematch.com.br';

export const instagram = 'https://www.instagram.com/escapematch/';

export const meetup = 'https://www.meetup.com/pt-br/escaperoomcuritiba/';

export const nomeFundador = 'Nícolas R. Saliba';

export const fraseFundador =
  `A EscapeMatch foi fundada por ${nomeFundador}, organizador do Meetup Escape Room Curitiba.`;

export const nomesAlternativos = ['Escape Match', 'escapematch'];

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
    `${descricaoMarca} A sessão é presencial, numa casa de escape room. Não é um jogo de celular de quebra-cabeça ou match-3 nem um modo de jogo de tiro com nome parecido. ${frasePlayStore}`,
  slogan: 'Ninguém pra jogar? Agora tem.',
  knowsAbout: [
    'escape room',
    'escape room sozinho',
    'jogar escape room sozinho no Brasil',
    'jogos presenciais em grupo',
  ],
  email: emailContato,
  sameAs: [instagram, meetup],
  founder: {
    '@type': 'Person',
    '@id': `${origem}/#fundador`,
    name: nomeFundador,
    description: 'Fundador da EscapeMatch e organizador do Meetup Escape Room Curitiba.',
    url: meetup,
  },
  address: enderecoCuritiba(),
  foundingLocation: {
    '@type': 'Place',
    name: 'Curitiba',
    address: enderecoCuritiba(),
  },
  areaServed: {
    '@type': 'Country',
    name: 'Brasil',
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
  disambiguatingDescription: frasePlayStore,
  areaServed: {
    '@type': 'Country',
    name: 'Brasil',
  },
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

export type ArtigoLd = {
  headline?: string;
  datePublished?: string;
  dateModified?: string;
};

// A data visível usa o dia escrito no ISO com fuso, sem passar pelo UTC.
export function textoAtualizado(iso: string): string {
  const data = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!data) throw new Error('data de artigo inválida');
  return `Atualizado em ${data[3]}/${data[2]}/${data[1]}`;
}

export function paginaLd(
  path: string,
  title: string,
  description: string,
  artigo?: ArtigoLd,
) {
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
    no.headline = artigo?.headline ?? title;
    no.mainEntityOfPage = canonical;
    if (artigo?.datePublished) no.datePublished = artigo.datePublished;
    if (artigo?.dateModified) no.dateModified = artigo.dateModified;
  }
  return no;
}

export function grafoDaPagina(entrada: {
  path: string;
  title: string;
  description: string;
  extra?: Record<string, unknown> | Record<string, unknown>[];
  artigo?: ArtigoLd;
}) {
  const extra = entrada.extra
    ? (Array.isArray(entrada.extra) ? entrada.extra : [entrada.extra])
    : [];
  return [
    organizacao,
    website,
    aplicativo,
    paginaLd(entrada.path, entrada.title, entrada.description, entrada.artigo),
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
