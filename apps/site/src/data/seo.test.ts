import assert from 'node:assert/strict';
import test from 'node:test';
import {
  aplicativo,
  definicao,
  definicaoCurta,
  descricaoHome,
  descricaoMarca,
  descricaoSobre,
  faqPage,
  grafoDaPagina,
  idAplicativo,
  idOrganizacao,
  idWebsite,
  meetup,
  nomesAlternativos,
  organizacao,
  paginaLd,
  textoAtualizado,
  tituloHome,
  tituloSobre,
  website,
} from './seo.ts';

const prefixo = 'EscapeMatch — app para jogar escape room sozinho no Brasil';

function chaves(valor: unknown, acc = new Set<string>()): Set<string> {
  if (Array.isArray(valor)) {
    for (const item of valor) chaves(item, acc);
    return acc;
  }
  if (valor && typeof valor === 'object') {
    for (const [chave, item] of Object.entries(valor)) {
      acc.add(chave);
      chaves(item, acc);
    }
  }
  return acc;
}

function idsReferenciados(valor: unknown, acc = new Set<string>()): Set<string> {
  if (Array.isArray(valor)) {
    for (const item of valor) idsReferenciados(item, acc);
    return acc;
  }
  if (!valor || typeof valor !== 'object') return acc;
  for (const [chave, item] of Object.entries(valor)) {
    const referencia = (
      chave === 'publisher'
      || chave === 'author'
      || chave === 'provider'
      || chave === 'isPartOf'
      || chave === 'about'
    ) && item && typeof item === 'object' && Object.keys(item).length === 1 && '@id' in item;
    if (referencia) {
      acc.add(String((item as { '@id': string })['@id']));
    } else if (chave !== '@id') {
      idsReferenciados(item, acc);
    }
  }
  return acc;
}

function idsDefinidos(valor: unknown, acc = new Set<string>()): Set<string> {
  if (Array.isArray(valor)) {
    for (const item of valor) idsDefinidos(item, acc);
    return acc;
  }
  if (valor && typeof valor === 'object') {
    const registro = valor as Record<string, unknown>;
    if (typeof registro['@id'] === 'string' && typeof registro['@type'] === 'string') {
      acc.add(registro['@id']);
    }
    for (const item of Object.values(registro)) idsDefinidos(item, acc);
  }
  return acc;
}

test('a Organization tem um @id estável e os fatos já publicados', () => {
  assert.equal(organizacao['@id'], 'https://escapematch.com.br/#organization');
  assert.equal(organizacao['@id'], idOrganizacao);
  assert.equal(organizacao.name, 'EscapeMatch');
  assert.equal(organizacao.legalName, 'ESCAPEMATCH TECNOLOGIA LTDA');
  assert.equal(organizacao.taxID, '70.100.608/0001-73');
  assert.deepEqual(organizacao.alternateName, ['Escape Match', 'escapematch']);
  assert.deepEqual(nomesAlternativos, organizacao.alternateName);
  assert.equal(organizacao.description, definicaoCurta);
  assert.equal(organizacao.disambiguatingDescription?.startsWith(descricaoMarca), true);
  assert.equal(organizacao.logo, 'https://escapematch.com.br/assets/logo-512.png');
  assert.deepEqual(organizacao.sameAs, [
    'https://www.instagram.com/escapematch/',
    meetup,
  ]);
  assert.equal(organizacao.founder['@type'], 'Person');
  assert.equal(organizacao.founder.name, 'Nícolas R. Saliba');
  assert.equal(organizacao.founder.url, meetup);
  assert.equal(organizacao.address.addressLocality, 'Curitiba');
  assert.equal(organizacao.address.addressRegion, 'PR');
  assert.equal(organizacao.address.addressCountry, 'BR');
  assert.equal(organizacao.foundingLocation.name, 'Curitiba');
  assert.equal(organizacao.foundingLocation.address.addressRegion, 'PR');
  assert.equal(organizacao.foundingLocation.address.addressCountry, 'BR');
  assert.equal(organizacao.areaServed['@type'], 'Country');
  assert.equal(organizacao.areaServed.name, 'Brasil');
  assert.equal('address' in organizacao.areaServed, false);
  assert.equal(aplicativo.areaServed['@type'], 'Country');
  assert.equal(aplicativo.areaServed.name, 'Brasil');
  const usadas = chaves(organizacao);
  assert.equal(usadas.has('telephone'), false);
  assert.equal(usadas.has('streetAddress'), false);
  assert.equal(usadas.has('award'), false);
});

test('WebSite e WebApplication apontam para a mesma Organization', () => {
  assert.equal(website['@id'], idWebsite);
  assert.equal(website.publisher['@id'], idOrganizacao);
  assert.equal(website.name, 'EscapeMatch');
  assert.equal(aplicativo['@type'], 'WebApplication');
  assert.equal(aplicativo['@id'], idAplicativo);
  assert.equal(aplicativo.name, 'EscapeMatch');
  assert.equal(aplicativo.provider['@id'], idOrganizacao);
  assert.equal(aplicativo.author['@id'], idOrganizacao);
  assert.equal(aplicativo.publisher['@id'], idOrganizacao);
  assert.equal(aplicativo.offers.price, 0);
  assert.equal(aplicativo.offers.priceCurrency, 'BRL');
  assert.equal('aggregateRating' in aplicativo, false);
});

test('guias e a página sobre publicam author e publisher', () => {
  const guia = paginaLd('/guia/escape-room-sozinho', 'Guia | EscapeMatch', definicaoCurta);
  assert.equal(guia['@type'], 'Article');
  assert.equal(guia.author['@id'], idOrganizacao);
  assert.equal(guia.publisher['@id'], idOrganizacao);
  assert.equal(guia.isPartOf['@id'], idWebsite);
  const sobre = paginaLd('/sobre', tituloSobre, descricaoSobre);
  assert.equal(sobre['@type'], 'AboutPage');
  assert.equal(sobre.headline, tituloSobre);
  assert.equal(sobre.author['@id'], idOrganizacao);
  const home = paginaLd('/', tituloHome, descricaoHome);
  assert.equal(home['@type'], 'WebPage');
  const faq = faqPage([{ pergunta: 'O que é o EscapeMatch?', resposta: definicaoCurta }]);
  assert.equal(faq.publisher['@id'], idOrganizacao);
  assert.equal(faq.author['@id'], idOrganizacao);
});

test('o grafo da home fecha as referências e o JSON é válido', () => {
  const blocos = grafoDaPagina({
    path: '/',
    title: tituloHome,
    description: descricaoHome,
    extra: faqPage([{ pergunta: 'O que é o EscapeMatch?', resposta: definicao }]),
  });
  const texto = JSON.stringify(blocos);
  const lido = JSON.parse(texto) as unknown[];
  assert.equal(Array.isArray(lido), true);
  assert.equal(texto.includes('streetAddress'), false);
  assert.equal(texto.includes('GameApplication'), false);
  assert.equal(texto.includes('ScapeMatch'), false);
  assert.equal(texto.includes('"name":"EscapeMatch"'), true);
  const definidos = idsDefinidos(lido);
  for (const id of idsReferenciados(lido)) {
    assert.equal(definidos.has(id), true, id);
  }
  assert.equal(definidos.has(idOrganizacao), true);
});

test('o artigo aceita manchete e datas sem mudar os outros guias', () => {
  const guia = paginaLd('/guia/escape-room-sozinho', 'Guia | EscapeMatch', definicaoCurta);
  assert.equal(guia.headline, 'Guia | EscapeMatch');
  assert.equal('datePublished' in guia, false);
  assert.equal('dateModified' in guia, false);
  const comData = paginaLd(
    '/guia/nao-tenho-amigos-para-escape-room',
    'Não tenho ninguém pra jogar escape room | EscapeMatch',
    definicaoCurta,
    {
      headline: 'Não tenho ninguém pra jogar escape room. O que fazer?',
      datePublished: '2026-11-13T00:00:00-03:00',
      dateModified: '2026-11-15T00:00:00-03:00',
    },
  );
  assert.equal(comData.headline, 'Não tenho ninguém pra jogar escape room. O que fazer?');
  assert.equal(comData.datePublished, '2026-11-13T00:00:00-03:00');
  assert.equal(comData.dateModified, '2026-11-15T00:00:00-03:00');
  assert.equal(textoAtualizado('2026-11-15T00:00:00-03:00'), 'Atualizado em 15/11/2026');
  const home = paginaLd('/', tituloHome, descricaoHome, {
    datePublished: '2026-11-13T00:00:00-03:00',
  });
  assert.equal('datePublished' in home, false);
});

test('título e descrição da home cabem e começam pela marca', () => {
  assert.equal(tituloHome.startsWith(prefixo), true);
  assert.equal(descricaoHome.startsWith(prefixo), true);
  assert.equal(descricaoSobre.startsWith(prefixo), true);
  assert.equal(tituloHome.length <= 60, true, String(tituloHome.length));
  assert.equal(tituloSobre.length <= 60, true, String(tituloSobre.length));
  assert.equal(descricaoHome.length <= 155, true, String(descricaoHome.length));
  assert.equal(descricaoSobre.length <= 155, true, String(descricaoSobre.length));
  assert.equal(definicao.startsWith(definicaoCurta), true);
  assert.equal(definicaoCurta, 'EscapeMatch é o app para achar grupo e jogar escape room sozinho no Brasil.');
  assert.equal(definicao.includes('!'), false);
  assert.equal(descricaoHome.includes('!'), false);
});
