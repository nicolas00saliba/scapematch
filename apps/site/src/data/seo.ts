// sameAs fica de fora: o repositório não publica Instagram, TikTok,
// LinkedIn nem outro perfil oficial.

export const origem = 'https://escapematch.com.br';

export const organizacao = {
  '@context': 'https://schema.org',
  '@type': 'Organization',
  name: 'EscapeMatch',
  url: `${origem}/`,
  logo: `${origem}/assets/logo-simbolo.svg`,
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
