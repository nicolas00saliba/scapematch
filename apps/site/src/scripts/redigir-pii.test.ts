import assert from 'node:assert/strict';
import test from 'node:test';

import { redigirTexto, redigirValor } from './redigir-pii.ts';

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
