// sameAs fica de fora: o repositório não publica Instagram, TikTok,
// LinkedIn nem outro perfil oficial.
// O campo logo continua no símbolo atual. Outro PR troca o arquivo.
// A nota de casa e de sala sai por aggregateRatingLd, e só com o mínimo.
// O app não leva aggregateRating nem review: não há avaliação publicada.

export { aggregateRatingLd } from './avaliacoes';
export type { NotaPublica } from './avaliacoes';

export const origem = 'https://escapematch.com.br';

export const definicao =
  'O EscapeMatch é o aplicativo brasileiro que conecta pessoas para jogar escape room e, em breve, outros jogos em grupo. Você chega sozinho, entra num grupo e paga só a sua vaga. Lançamento em Curitiba. Não é um jogo de celular.';

export const emailContato = 'contato@escapematch.com.br';

export const organizacao = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: 'EscapeMatch',
  legalName: 'ESCAPEMATCH TECNOLOGIA LTDA',
  taxID: '70.100.608/0001-73',
  alternateName: ['Escape Match'],
  url: `${origem}/`,
  logo: `${origem}/assets/logo-simbolo.svg`,
  description: definicao,
  email: emailContato,
  address: {
    '@type': 'PostalAddress',
    addressLocality: 'Curitiba',
    addressRegion: 'PR',
    addressCountry: 'BR',
  },
  areaServed: {
    '@type': 'City',
    name: 'Curitiba',
  },
};

export const website = {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  name: 'EscapeMatch',
  url: `${origem}/`,
  inLanguage: 'pt-BR',
  description: organizacao.description,
  publisher: {
    '@type': 'Organization',
    name: 'EscapeMatch',
    url: `${origem}/`,
  },
};

export const aplicativo = {
  '@context': 'https://schema.org',
  '@type': 'WebApplication',
  name: 'EscapeMatch',
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
};

export function faqPage(itens: { pergunta: string; resposta: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
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
