import assert from 'node:assert/strict';
import test from 'node:test';
import {
  arquivoGoogle,
  linhaArquivoGoogle,
  tokenBuscador,
  xmlBing,
} from './verificacao-buscadores.mjs';

test('token vazio ou curto não vira meta', () => {
  assert.equal(tokenBuscador(undefined), null);
  assert.equal(tokenBuscador(''), null);
  assert.equal(tokenBuscador('curto'), null);
  assert.equal(tokenBuscador('changeme-changeme'), null);
  assert.equal(tokenBuscador('exemploexemploexemplo'), null);
  assert.equal(tokenBuscador('xxxxxxxxxxxxxxxx'), null);
});

test('token de buscador com formato real passa', () => {
  const google = 'aB3dEfgHiJkLmNoPqRsTuVwXyZ012345';
  const bing = '0123456789abcdef0123456789abcdef';
  assert.equal(tokenBuscador(`  ${google}  `), google);
  assert.equal(tokenBuscador(bing), bing);
});

test('arquivo HTML do Google só entra com o nome que o Search Console gera', () => {
  assert.equal(arquivoGoogle(''), null);
  assert.equal(arquivoGoogle('google.html'), null);
  assert.equal(arquivoGoogle('googleexemploexemplo.html'), null);
  assert.equal(arquivoGoogle('../googleabcdefghijklmnop.html'), null);
  const nome = 'googleAbcdEfgh12345678.html';
  assert.equal(arquivoGoogle(nome), nome);
  assert.equal(linhaArquivoGoogle(nome), `google-site-verification: ${nome}\n`);
});

test('XML do Bing usa o token e nada além dele', () => {
  const token = '0123456789abcdef0123456789abcdef';
  assert.equal(
    xmlBing(token),
    `<?xml version="1.0"?>\n<users>\n  <user>${token}</user>\n</users>\n`,
  );
});
