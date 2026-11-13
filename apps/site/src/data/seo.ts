// sameAs publica só o Instagram oficial. TikTok, LinkedIn e outras
// redes continuam de fora: o repositório não tem esses perfis.
// A nota de casa e de sala sai por aggregateRatingLd, e só com o mínimo.
// O app não leva aggregateRating nem review: não há avaliação publicada.

export { aggregateRatingLd } from './avaliacoes';
export type { NotaPublica } from './avaliacoes';

export const origem = 'https://escapematch.com.br';

export const definicao =
  'O EscapeMatch é o aplicativo brasileiro que conecta pessoas para jogar escape room e, em breve, outros jogos em grupo. Você chega sozinho, entra num grupo e paga só a sua vaga. Lançamento em Curitiba. Não é um jogo de celular.';

export const emailContato = 'contato@escapematch.com.br';

export const nomesAlternativos = ['ScapeMatch', 'Scape Match', 'Escape Match'];

export const organizacao = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
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
  description: definicao,
  email: emailContato,
  sameAs: ['https://www.instagram.com/escapematch/'],
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
