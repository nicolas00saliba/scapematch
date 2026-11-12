import assert from 'node:assert/strict';
import test from 'node:test';
import { aggregateRatingLd } from './avaliacoes.ts';

const base = {
  nome: 'O Cofre',
  tipo: 'sala' as const,
  url: 'https://escapematch.com.br/salas/o-cofre',
  media: 4.5,
  quantidade: 10,
  minimo: 10,
};

test('emite AggregateRating no mínimo', () => {
  const bloco = aggregateRatingLd(base);
  assert.equal(bloco?.['@type'], 'Product');
  const nota = bloco?.aggregateRating as Record<string, unknown>;
  assert.equal(nota.ratingValue, 4.5);
  assert.equal(nota.reviewCount, 10);
  assert.equal(nota.bestRating, 5);
  assert.equal(nota.worstRating, 1);
});

test('casa vira LocalBusiness', () => {
  const bloco = aggregateRatingLd({
    ...base,
    nome: 'Ninja Escape',
    tipo: 'casa',
    url: 'https://escapematch.com.br/casas/ninja',
  });
  assert.equal(bloco?.['@type'], 'LocalBusiness');
});

test('abaixo do mínimo não publica nota', () => {
  assert.equal(aggregateRatingLd({ ...base, quantidade: 9 }), null);
  assert.equal(aggregateRatingLd({ ...base, quantidade: 0, minimo: 10 }), null);
  assert.equal(aggregateRatingLd({ ...base, media: 0 }), null);
  assert.equal(aggregateRatingLd({ ...base, minimo: 0 }), null);
});
