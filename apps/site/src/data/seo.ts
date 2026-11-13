// sameAs fica de fora: o repositório não publica Instagram, TikTok,
// LinkedIn nem outro perfil oficial.
// A nota de casa e de sala sai por aggregateRatingLd, e só com o mínimo.

export { aggregateRatingLd } from './avaliacoes';
export type { NotaPublica } from './avaliacoes';

export const origem = 'https://escapematch.com.br';

export const organizacao = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: 'EscapeMatch',
  url: `${origem}/`,
  // PNG quadrado de 512 px. O Google pede, no logo da Organization,
  // pelo menos 112 px, em formato que o Google Imagens rastreia, e
  // que continue legível em fundo branco. O SVG do símbolo fica no
  // cabeçalho; não entra neste campo.
  logo: `${origem}/assets/logo-512.png`,
  description:
    'Plataforma brasileira criada para quem quer jogar e não tem grupo. O lançamento começa em Curitiba, com escape room.',
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
