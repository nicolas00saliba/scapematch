// Marcação AggregateRating para as páginas de casa e de sala.
// Só sai quando a quantidade chega ao mínimo configurado no Admin.
// Sem esse piso o site não inventa nota.

export type NotaPublica = {
  nome: string;
  tipo: 'casa' | 'sala';
  url: string;
  media: number;
  quantidade: number;
  minimo: number;
};

export function aggregateRatingLd(
  nota: NotaPublica,
): Record<string, unknown> | null {
  if (!Number.isInteger(nota.quantidade) || !Number.isInteger(nota.minimo)) {
    return null;
  }
  if (nota.minimo < 1 || nota.quantidade < nota.minimo) return null;
  if (!Number.isFinite(nota.media) || nota.media < 1 || nota.media > 5) {
    return null;
  }
  if (nota.nome.trim() === '' || nota.url.trim() === '') return null;

  return {
    '@context': 'https://schema.org',
    '@type': nota.tipo === 'casa' ? 'LocalBusiness' : 'Product',
    name: nota.nome,
    url: nota.url,
    aggregateRating: {
      '@type': 'AggregateRating',
      ratingValue: Number(nota.media.toFixed(2)),
      reviewCount: nota.quantidade,
      bestRating: 5,
      worstRating: 1,
    },
  };
}
