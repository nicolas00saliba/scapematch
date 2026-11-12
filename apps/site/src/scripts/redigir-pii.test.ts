import assert from 'node:assert/strict';
import test from 'node:test';

import {
  redigirBreadcrumb,
  redigirEvento,
  redigirTexto,
  redigirValor,
} from './redigir-pii.ts';
import { taxaAmostragemErros, taxaAmostragemTraces } from './sentry-taxas.ts';

test('redige e-mail, CPF e telefone', () => {
  const saida = redigirTexto(
    'ana.silva@escapematch.com.br 123.456.789-09 (41) 98888-7777 pedido 42',
  );
  assert.equal(saida.includes('ana.silva'), false);
  assert.equal(saida.includes('123.456.789-09'), false);
  assert.equal(saida.includes('98888-7777'), false);
  assert.match(saida, /\[email\]/);
  assert.match(saida, /\[cpf\]/);
  assert.match(saida, /\[telefone\]/);
  assert.match(saida, /pedido 42/);
});

test('redige tokens na URL, no request e nos breadcrumbs', () => {
  assert.equal(
    redigirTexto(
      'https://escapematch.com.br/auth?code=pkce&token=xyz#access_token=aaa&refresh_token=bbb&type=recovery&provider_token=ccc&id_token=ddd&token_type=bearer',
    ),
    'https://escapematch.com.br/auth?code=[redigido]&token=[redigido]#access_token=[redigido]&refresh_token=[redigido]&type=[redigido]&provider_token=[redigido]&id_token=[redigido]&token_type=[redigido]',
  );
  assert.equal(
    redigirTexto('https://escapematch.com.br/ajuda?tema=pagamento'),
    'https://escapematch.com.br/ajuda?tema=pagamento',
  );

  const evento = redigirEvento({
    request: {
      url: 'https://escapematch.com.br/auth?code=abc#access_token=zzz',
      query_string: 'code=abc&type=signup',
      fragment: 'access_token=zzz&refresh_token=yyy&provider_refresh_token=qqq',
    },
  });
  assert.deepEqual(evento, {
    request: {
      url: 'https://escapematch.com.br/auth?code=[redigido]#access_token=[redigido]',
      query_string: 'code=[redigido]&type=[redigido]',
      fragment:
        'access_token=[redigido]&refresh_token=[redigido]&provider_refresh_token=[redigido]',
    },
  });

  assert.deepEqual(
    redigirBreadcrumb({
      category: 'navigation',
      data: {
        from: 'https://escapematch.com.br/#access_token=segredo',
        to: 'https://escapematch.com.br/login?code=abc',
      },
    }),
    {
      category: 'navigation',
      data: {
        from: 'https://escapematch.com.br/#access_token=[redigido]',
        to: 'https://escapematch.com.br/login?code=[redigido]',
      },
    },
  );

  assert.deepEqual(
    redigirBreadcrumb({
      category: 'fetch',
      data: { url: 'https://api.exemplo/rest?token=abc&provider_token=def' },
    }),
    {
      category: 'fetch',
      data: {
        url: 'https://api.exemplo/rest?token=[redigido]&provider_token=[redigido]',
      },
    },
  );
});

test('erros saem todos e o traço fica em 5%', () => {
  assert.equal(taxaAmostragemErros, 1);
  assert.equal(taxaAmostragemTraces, 0.05);
});

test('tira a chave de e-mail do evento', () => {
  const saida = redigirValor({
    user: { email: 'ana@casa.com', id: '42' },
    message: 'falha de ana@casa.com',
  });
  assert.deepEqual(saida, {
    user: { id: '42' },
    message: 'falha de [email]',
  });
});
